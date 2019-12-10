import urllib, sys, os

from jira import JIRA
from optparse import OptionParser

# Requires jira (`pip install jira python-magic`), not jira-python - https://stackoverflow.com/questions/30915236/jira-python-package-in-pip-has-gone
# If connection to JIRA server fails with error: "The error message is __init__() got an unexpected keyword argument 'mime'"
# Then go edit /usr/lib/python2.7/site-packages/jira/client.py 
# replace 
#		 self._magic = magic.Magic(mime=True)
# with 
#		 self._magic = magic
# 
# ref: http://stackoverflow.com/questions/12609402/init-got-an-unexpected-keyword-argument-mime-in-python-django

usage = "Creates a New + Noteworthy jira + subtasks for all components.\n\nUsage:   python " + sys.argv[0] + \
  " -s <jira server> --jbide <jbidefixversion> --jbds <jbdsfixversion> --fuse <fusefixversion> --user <JIRA user> --pwd <JIRA pass> \n" + \
  "Example: python " + sys.argv[0] + " -s https://issues.stage.jboss.org -i 4.5.0.AM2 -d 11.0.0.AM2 -u jirauser -p jirapwd\n\
\n\
NOTE: rather than passing in --user and --pwd, you can `export userpass=jirauser:jirapwd`, \n\
and this script will read those values from the shell"

parser = OptionParser(usage)
parser.add_option("-i", "--jbide", dest="jbidefixversion", help="JBIDE fix version")
parser.add_option("-d", "--jbds", dest="jbdsfixversion", help="JBDS fix version")
parser.add_option("-f", "--fuse", dest="fusefixversion", help="FUSETOOLS fix version (default: JBDS fixversion (a-1).b.c.d")

parser.add_option("-s", "--server", dest="jiraserver", help="JIRA server, eg., https://issues.stage.redhat.com or https://issues.redhat.com")
parser.add_option("-u", "--user", dest="jirauser", help="JIRA Username")
parser.add_option("-p", "--pwd", dest="jirapwd", help="JIRA Password")
# NOTE: rather than passing in two flags here, you can `export userpass=jirauser:jirapwd`, 
# and this script will read those values from the shell

(options, args) = parser.parse_args()

if (not options.jirauser or not options.jirapwd) and "userpass" in os.environ:
	# check if os.environ["userpass"] is set and use that if defined
	#sys.exit("Got os.environ[userpass] = " + os.environ["userpass"])
	userpass_bits = os.environ["userpass"].split(":")
	options.jirauser = userpass_bits[0]
	options.jirapwd = userpass_bits[1]

if not options.jirauser or not options.jirapwd or not options.jbidefixversion or not options.jbdsfixversion:
	parser.error("Must specify ALL required commandline flags")
	
jbide_fixversion = options.jbidefixversion
jbds_fixversion = options.jbdsfixversion
if options.fusefixversion:
	fuse_fixversion = options.fusefixversion
else:
	# set fuse fixversion a.b.c.d = JBDS fixversion (a-1).b.c.d
	fuse_bits = jbds_fixversion.split(".")
	fuse_fixversion = str(int(fuse_bits[0]) - 1) + "." + fuse_bits[1] + "." + fuse_bits[2] + "." + fuse_bits[3]
# sys.exit("jbds_fixversion = " + jbds_fixversion + "\n" + "fuse_fixversion = " + fuse_fixversion) # debug

jiraserver = options.jiraserver
jira = JIRA(options={'server':jiraserver}, basic_auth=(options.jirauser, options.jirapwd))
CL = jira.project_components(jira.project('JBIDE')) # full list of components in JBIDE

from components import checkFixVersionsExist, queryComponentLead, defaultAssignee

def setComponentLead(theissue,componentLead):
	try:
		jira.assign_issue(theissue, componentLead)
	except:
		print "[WARNING] Unexpected error! User {0} tried to assign {1} to {2}: {3}".format(options.jirauser, theissue, componentLead, sys.exc_info()[0])


def setTaskLabel(theissue):
	try:
		issue = jira.issue(theissue.key)
		issue.fields.labels.append(u'task')
		issue.update(fields={"labels": issue.fields.labels})
	except:
		print "[WARNING] Unexpected error! User {0} tried to set label = 'task' on {1}: {2}".format(options.jirauser, theissue, sys.exc_info()[0])


if checkFixVersionsExist(jbide_fixversion, jbds_fixversion, jiraserver, options.jirauser, options.jirapwd) == True:
	## The jql query across for all N&N - to find issues for which N&N needs to be written
	nnsearchquery = '((project in (JBDS) and fixVersion = "' + \
		jbds_fixversion + '") or (project in (FUSETOOLS) and fixVersion = "' + \
		fuse_fixversion + '") or (project in (JBIDE) and fixVersion = "' + \
		jbide_fixversion + '")) AND resolution = Done AND labels = new_and_noteworthy'
	nnsearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(nnsearchquery)

	# queries to find other created N&N Task issues, not issues for which N&N should be written
	nnissuesqueryall = 'summary ~ "New and Noteworthy" AND project in (JBDS, FUSETOOLS, JBIDE) ORDER BY key DESC'
	nnissuesquerythisversion = 'summary ~ "New and Noteworthy" AND ((project in (JBDS) and fixVersion = "' + \
		jbds_fixversion + '") or (project in (FUSETOOLS) and fixVersion = "' + \
		fuse_fixversion + '") or (project in (JBIDE) and fixVersion = "' + \
		jbide_fixversion + '")) ORDER BY key DESC'

	rootnn_description = 'This [query|' + nnsearch + '] contains the search for all N&N. See subtasks below.'
	rootnn_dict = {
		'project' : { 'key' : 'JBIDE' },
		'summary' : 'Create New and Noteworthy for ' + jbide_fixversion,
		'description' : rootnn_description,
		'issuetype' : { 'name' : 'Task' },
		'priority' : { 'name' :'Blocker'},
		'fixVersions' : [{ "name" : jbide_fixversion }],
		'components' : [{ "name" : "website" }]
		}
	rootnn = jira.create_issue(fields=rootnn_dict)
	componentLead = defaultAssignee()

	setComponentLead(rootnn,componentLead)

	setTaskLabel(rootnn)

	print("JBoss Tools       : " + jiraserver + '/browse/' + rootnn.key + " => " + componentLead + "")

	def nametuple(x):
		return { "name" : x }

	def quote(x):
		return '"' + x + '"'

	# see JIRA_components listing in components.py
	from components import NN_components

	for name, comps in NN_components.iteritems():
		for firstcomponent in comps:
			break
		cms = map(nametuple, comps)
		componentLead = queryComponentLead(CL, firstcomponent, 0)
		#print(name + "->" + str(cms) + " => " + componentLead)

		compnnsearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(nnsearchquery + " and component in (" + ",".join(map(quote,comps)) + ")")

		query_links = '\n\n Queries:\n' + \
			'* [Completed ' + name + ' JIRAs marked N&N|' + compnnsearch + ']\n' + \
			'* [All Completed JIRAs marked N&N|' + nnsearch + ']\n' + \
			'* [N&N Task JIRAs for this milestone|' + jiraserver + '/issues/?jql=' + urllib.quote_plus(nnissuesquerythisversion) + ']\n' + \
			'* [All N&N Task JIRAs|' + jiraserver + '/issues/?jql=' + urllib.quote_plus(nnissuesqueryall) + ']\n\n'

		childnn_description_milestone = \
			queryComponentLead(CL, firstcomponent, 1) + ",\n\n" + \
			'Search for your component\'s New and Noteworthy issues:' + query_links + \
			'If no N&N issues are found for ' + name.strip() + ', check if there are issues that SHOULD have been labelled with *Labels =* _new_and_noteworthy_, and add them.\n\n ' + \
			'Document the ones relevant for ' + name.strip() + ' by submitting a pull request against:\n\n' + \
			'* https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew\n\n' + \
			'If your PR\'s commit comment is of the form... {code}' + rootnn.key + ' #comment Create N&N for ' + name.strip() + " " + jbide_fixversion + ' #close{code}... and your github user\'s email address is the same as your JIRA one, ' + \
			'then this JIRA should be closed automatically when the PR is applied.\n\n' + \
			'If there is nothing new or noteworthy for ' + name.strip() + ' for this milestone, please *reject* and *close* this issue.\n\n'

		childnn_description_final = childnn_description_milestone + '----\n' + \
			'If there is nothing new or noteworthy for ' + jbide_fixversion + ' since the AM3 release of ' + name.strip() + ', please *reject* and ' + \
			'*close* this issue. The final N&N page will be aggregated from all previous N&N documents.\n\n' + \
			'If you want to _add a comment to the final document_ then submit a PR to create a separate <component>-news-' + jbide_fixversion + '.adoc file here:\n\n' + \
			'* https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew\n\n' + \
			'\n\nThe final N&N page will be aggregated from all previous N&N documents plus this *.Final.adoc.\n\n' + \
			'However, if you want to _replace all previous N&Ns by a *new* document_, then submit a PR to create a *new* <component>-news-' + jbide_fixversion + '.adoc file, ' + \
			'adding: {code}page-include-previous: false{code}.\n\n'

		if jbide_fixversion.endswith(".Final"):
			childnn_description = childnn_description_final
		else:
			childnn_description = childnn_description_milestone
		
		childnn_dict = {
			'project' : { 'key' : 'JBIDE' },
			'summary' : name + ' New and Noteworthy for ' + jbide_fixversion,
			'description' : childnn_description,
			'issuetype' : { 'name' : 'Sub-task' },
			'parent' : { 'id' : rootnn.key},
			'priority' : { 'name': 'Critical'},
			'fixVersions' : [{ "name" : jbide_fixversion }],
			'components' : cms,
		}

		child = jira.create_issue(fields=childnn_dict)

		setComponentLead(child,componentLead)

		setTaskLabel(child)

		print(name +  ": " + jiraserver + '/browse/' + child.key + " => " + componentLead)

	accept = raw_input("Accept created JIRAs? [Y/n] ")
	if accept.capitalize() in ["N"]:
		rootnn.delete(deleteSubtasks=True)
