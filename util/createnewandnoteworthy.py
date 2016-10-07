import pprint, urllib

from jira.client import JIRA
from optparse import OptionParser

pp = pprint.PrettyPrinter(indent=4)

usage = "usage: %prog -u <user> -p <password> --jbide <jbideversion> --jbds <jbdsversions> \nCreates NN jira + subtasks.\nRequires you have installed jira-python (See http://jira-python.readthedocs.org/en/latest/)"
parser = OptionParser(usage)
parser.add_option("-u", "--user", dest="username", help="jira username")
parser.add_option("-p", "--pwd", dest="password", help="jira password")
parser.add_option("-i", "--jbide", dest="jbidefixversion", help="JBIDE fix version")
parser.add_option("-d", "--jbds", dest="jbdsfixversion", help="JBDS fix version")
parser.add_option("-s", "--server", dest="jiraserver", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.org")

(options, args) = parser.parse_args()

if not options.username or not options.password or not options.jbidefixversion or not options.jbdsfixversion:
	parser.error("Need to specify all")
	
jiraserver = options.jiraserver
jira = JIRA(options={'server':jiraserver}, basic_auth=(options.username, options.password))

jbide_fixversion = options.jbidefixversion
jbds_fixversion = options.jbdsfixversion

from components import checkFixVersionsExist

if checkFixVersionsExist(jbide_fixversion, jbds_fixversion, jiraserver, options.username, options.password) == True:
	## The jql query across for all N&N - to find issues for which N&N needs to be written
	nnsearchquery = '((project in (JBDS) and fixVersion = "' + jbds_fixversion + '") or (project in (JBIDE) and fixVersion = "' + jbide_fixversion + '")) AND resolution = Done AND labels = new_and_noteworthy'
	nnsearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(nnsearchquery)

	# queries to find other created N&N Task issues, not issues for which N&N should be written
	nnissuesqueryall = 'summary ~ "New and Noteworthy" AND project in (JBIDE, JBDS) ORDER BY key DESC'
	nnissuesquerythisversion = 'summary ~ "New and Noteworthy" AND ((project in (JBDS) and fixVersion = "' + jbds_fixversion + '") or (project in (JBIDE) and fixVersion = "' + jbide_fixversion + '")) ORDER BY key DESC'

	rootnn_description_milestone = 'This [query|' + nnsearch + '] contains the search for all N&N'
	rootnn_description_final = 'This [query|' + nnsearch + '] contains the search for all N&N'

	if jbide_fixversion.endswith(".Final"):
		rootnn_description = rootnn_description_final
	else:
		rootnn_description = rootnn_description_milestone

	rootnn_dict = {
		'project' : { 'key': 'JBIDE' },
		'summary' : 'Create New and Noteworthy for ' + jbide_fixversion,
		'description' : rootnn_description,
		'issuetype' : { 'name' : 'Task' },
		'priority' : { 'name' :'Blocker'},
		'fixVersions' : [{ "name" : jbide_fixversion }],
		'components' : [{ "name" : "website" }]
		}

		#pp.pprint(rootnn_dict)
	rootnn = jira.create_issue(fields=rootnn_dict)

	print("JBoss Tools	   : " + jiraserver + '/browse/' + rootnn.key)

	def nametuple(x):
		return { "name" : x }

	def quote(x):
		return '"' + x + '"'

	# see JIRA_components listing in components.py
	from components import NN_components

	for name, comps in NN_components.iteritems():
		
		cms = map(nametuple, comps)	
		#print name + "->" + str(cms)

		compnnsearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(nnsearchquery + " and component in (" + ",".join(map(quote,comps)) + ")")

		query_links = '\n\n Queries:\n' + \
			'* [Completed ' + name + ' JIRAs marked N&N|' + compnnsearch + ']\n' + \
			'* [All Completed JIRAs marked N&N|' + nnsearch + ']\n' + \
			'* [N&N Task JIRAs for this milestone|' + jiraserver + '/issues/?jql=' + urllib.quote_plus(nnissuesquerythisversion) + ']\n' + \
			'* [All N&N Task JIRAs|' + jiraserver + '/issues/?jql=' + urllib.quote_plus(nnissuesqueryall) + ']\n\n'

		rootnn_description_milestone = 'Search for your component\'s New and Noteworthy issues:' + query_links + \
			'If no N&N issues are found for ' + name.strip() + ', check if there are issues that SHOULD have been labelled with *Labels =* _new_and_noteworthy_, and add them.\n\n ' + \
			'Document the ones relevant for ' + name.strip() + ' by submitting a pull request against:\n\n' + \
			'* https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew\n\n' + \
			'If your PR\'s commit comment is of the form \'JBIDE-56789 #comment Create N&N for ' + name.strip() + jbide_fixversion + ' #close\', and your github user\'s email address is the same as your JIRA one, ' + \
			'then this JIRA should be closed automatically when the PR is applied.\n\n' + \
			'If there is nothing new or noteworthy for ' + name.strip() + ' for this milestone, please *reject* and *close* this issue.\n\n'

		rootnn_description_final = rootnn_description_milestone + '----\n' + \
		    'If there is nothing new or noteworthy for ' + jbide_fixversion + ' since the AM3 release of ' + name.strip() + ', please *reject* and ' + \
			'*close* this issue. The final N&N page will be aggregated from all previous N&N documents.\n\n' + \
			'If you want to _add a comment to the final document_ then submit a PR to create a separate <component>-news-' + jbide_fixversion + '.adoc file here:\n\n' + \
			'* https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew\n\n' + \
			'\n\nThe final N&N page will be aggregated from all previous N&N documents plus this *.Final.adoc.\n\n' + \
			'However, if you want to _replace all previous N&Ns by a *new* document_, then submit a PR to create a *new* <component>-news-' + jbide_fixversion + '.adoc file, ' + \
			'adding: {code}page-include-previous: false{code}.\n\n'

		if jbide_fixversion.endswith(".Final"):
			rootnn_description = rootnn_description_final
		else:
			rootnn_description = rootnn_description_milestone
		
		rootnn_dict = {
			'project' : { 'key': 'JBIDE' },
			'summary' : name + ' New and Noteworthy for ' + jbide_fixversion,
			'description' : rootnn_description,
			'issuetype' : { 'name' : 'Sub-task' },
			'parent' : { 'id' : rootnn.key},
			'priority' : { 'name': 'Critical'},
			'components' : cms,
		}

		#pp.pprint(cms)
		child = jira.create_issue(fields=rootnn_dict)
		print(name +  ": " + jiraserver + '/browse/' + child.key)

	accept = raw_input("Accept created JIRAs? [Y/n] ")
	if accept.capitalize() in ["N"]:
		rootnn.delete(deleteSubtasks=True)
