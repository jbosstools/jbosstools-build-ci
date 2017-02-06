from jira import JIRA
from subprocess import Popen, PIPE
import magic
import urllib, os, sys
from optparse import OptionParser

# TODO: don't generate JIRAs unless there's actually a missing commit/merge across branches.
# TODO: check that branch != master


# Requires jira-python (See http://jira-python.readthedocs.org/en/latest/)
# If connection to JIRA server fails with error: "The error message is __init__() got an unexpected keyword argument 'mime'"
# Then go edit /usr/lib/python2.7/site-packages/jira/client.py 
# replace 
#		 self._magic = magic.Magic(mime=True)
# with 
#		 self._magic = magic
# 
# ref: http://stackoverflow.com/questions/12609402/init-got-an-unexpected-keyword-argument-mime-in-python-django

usage = "Usage: %prog -u <user> -p <pass> -s <JIRA server> --jbide <jbideversion> --jbds <jbdsversion> -b <branch> \
-t <short task summary> -f <full detailed task description>\n\nThis script will create 1 JBDS and 1 JBIDE JIRA with the specified task summary + description, \
then create \nsub-tasks of the JBIDE JIRA for each of the JBIDE components with matching Github jbosstools-* repos"
parser = OptionParser(usage)
parser.add_option("-u", "--user", dest="usernameJIRA", help="JIRA Username")
parser.add_option("-p", "--pwd", dest="passwordJIRA", help="JIRA Password")
parser.add_option("-s", "--server", dest="jiraserver", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.org")
parser.add_option("-b", "--branch", dest="frombranch", help="The branch containing commits that should be in master (ie, our maintenance branch, jbosstools-4.3.x")
parser.add_option("-i", "--jbide", dest="jbidefixversion", help="JBIDE Fix Version, eg., 4.1.0.qualifier")
parser.add_option("-d", "--jbds", dest="jbdsfixversion", help="JBDS Fix Version, eg., 7.0.0.qualifier")
parser.add_option("-t", "--task", dest="taskdescription", help="Task Summary, eg., \"Code Freeze + Branch\"")
parser.add_option("-f", "--taskfull", dest="taskdescriptionfull", help="Task Description, eg., \"Please perform the following tasks...\"");
# see createTaskJIRAs.py.examples.txt for examples of taskdescriptionfull

(options, args) = parser.parse_args()

if not options.usernameJIRA or not options.passwordJIRA or not options.jiraserver or not options.frombranch or not options.jbidefixversion or not options.jbdsfixversion or not options.taskdescription:
	parser.error("Must to specify ALL commandline flags")
	
jiraserver = options.jiraserver
jbide_fixversion = options.jbidefixversion
jbds_fixversion = options.jbdsfixversion

from components import checkFixVersionsExist, queryComponentLead, defaultAssignee

if checkFixVersionsExist(jbide_fixversion, jbds_fixversion, jiraserver, options.usernameJIRA, options.passwordJIRA) == True:

	frombranch = options.frombranch
	jira = JIRA(options={'server':jiraserver}, basic_auth=(options.usernameJIRA, options.passwordJIRA))
	CLJBIDE = jira.project_components(jira.project('JBIDE')) # full list of components in JBIDE
	CLJBDS = jira.project_components(jira.project('JBDS')) # full list of components in JBIDE

	taskdescription = options.taskdescription
	taskdescriptionfull = options.taskdescriptionfull
	if not options.taskdescriptionfull:
		taskdescriptionfull = options.taskdescription

	## The jql query across for all task issues
	tasksearchquery = '((project in (JBDS) and fixVersion = "' + jbds_fixversion + '") or (project in (JBIDE) and fixVersion = "' + jbide_fixversion + '")) AND labels = task'

	tasksearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(tasksearchquery)

	rootJBDS_dict = {
		'project' : { 'key': 'JBDS' },
		'summary' : 'For JBDS ' + jbds_fixversion + ': ' + taskdescription,
		'description' : 'For JBDS ' + jbds_fixversion + ': ' + taskdescriptionfull + '\n\n[Search for all task JIRA|' + tasksearch + ']',
		'issuetype' : { 'name' : 'Task' },
		'priority' : { 'name' :'Blocker'},
		'fixVersions' : [{ "name" : jbds_fixversion }],
		'components' : [{ "name" : "installer" }],
		'labels' : [ "task" ],
		}
	rootJBDS = jira.create_issue(fields=rootJBDS_dict)
	componentLead = defaultAssignee()
	try:
		jira.assign_issue(rootJBDS, componentLead)
	except:
		print "[WARNING] Unexpected error! User {0} tried to assign {1} to {2}: {3}".format(options.usernameJIRA, rootJBDS, componentLead, sys.exc_info()[0])
	print("Task JIRA created for this milestone include:")
	print("")

	print("JBDS              : " + jiraserver + '/browse/' + rootJBDS.key + " => " + componentLead)

	rootJBIDE_dict = {
		'project' : { 'key': 'JBIDE' },
		'summary' : 'For JBIDE ' + jbide_fixversion + ': ' + taskdescription,
		'description' : 'For JBIDE ' + jbide_fixversion + ': ' + taskdescriptionfull + '\n\n[Search for all task JIRA|' + tasksearch + ']\n\nSee also: ' + rootJBDS.key,
		'issuetype' : { 'name' : 'Task' },
		'priority' : { 'name' :'Blocker'},
		'fixVersions' : [{ "name" : jbide_fixversion }],
		'components' : [{ "name" : "build" }],
		'labels' : [ "task" ]
		}
	rootJBIDE = jira.create_issue(fields=rootJBIDE_dict)
	try:
		jira.assign_issue(rootJBIDE, componentLead)
	except:
		print "[WARNING] Unexpected error! User {0} tried to assign {1} to {2}: {3}".format(options.usernameJIRA, rootJBIDE, componentLead, sys.exc_info()[0])
	print("JBoss Tools       : " + jiraserver + '/browse/' + rootJBIDE.key + " => " + componentLead + "")


	# Currently, the repo url (for printing links to the missing commits)
	# is calculated as  "https://github.com/jbosstools/jbosstools-$key.git"
	# If this is wrong, it will need to be refactored.

	def nametuple(x):
		return { "name" : x }

	def quote(x):
		return '"' + x + '"'

	# We've made the first parent jira. 
	# To avoid cloning all repos here in this folder,
	# lets make a sub-directory to do our work in
	workingdir = os.getcwd();
	tmpsubdir = workingdir + "/tmplostpatches"
	try:
		os.stat(tmpsubdir)
	except:
		os.mkdir(tmpsubdir)

	os.chdir(tmpsubdir)

	# see JIRA_components listing in components.py
	from components import JIRA_components

	for name, comps in JIRA_components.iteritems():
		for firstcomponent in comps:
			break
		cms = map(nametuple, comps)
		componentLead = queryComponentLead(CLJBIDE, firstcomponent, 0)
		#print(name + "->" + str(cms) + " => " + componentLead)
		workingdir = os.getcwd()
		# skip if name contains spaces in components.py
		if " " not in name.rstrip():
			subfoldername="jbosstools-" + name.lower()
			githubrepo = "https://github.com/jbosstools/" + subfoldername.strip() + ".git"
			print githubrepo;
			# use shallow clone for faster checkout
			os.system("git clone --depth 1 " + githubrepo)
			os.chdir(workingdir + "/" + subfoldername.strip())
			p = Popen(['bash', '../../findlostpatchesonerepository.sh', frombranch], stdout=PIPE, stderr=PIPE, stdin=PIPE)
			output = p.stdout.read()
			print output
			comptasksearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(tasksearchquery + " and component in (" + ",".join(map(quote,comps)) + ")")
			
			rootJBIDE_dict = {
				'project' : { 'key': 'JBIDE' },
				'summary' : 'For JBIDE ' + jbide_fixversion + ': ' + taskdescription + ' [' + name.strip() + ']',
				'description' : 'For JBIDE ' + jbide_fixversion + ' [' + name.strip() + ']: ' + taskdescriptionfull + "\n\n" + output + 
					'\n\n[Search for all task JIRA|' + tasksearch + '], or [Search for ' + name.strip() + ' task JIRA|' + comptasksearch + ']',
				'issuetype' : { 'name' : 'Sub-task' },
				'parent' : { 'id' : rootJBIDE.key},
				'priority' : { 'name': 'Blocker'},
				'components' : cms,
				'labels' : [ "task" ]
			}
			os.chdir(workingdir)

			child = jira.create_issue(fields=rootJBIDE_dict)
			try:
				jira.assign_issue(child, componentLead)
			except:
				print "[WARNING] Unexpected error! User {0} tried to assign {1} to {2}: {3}".format(options.usernameJIRA, child, componentLead, sys.exc_info()[0])
			print(name +  ": " + jiraserver + '/browse/' + child.key + " => " + componentLead)

	accept = raw_input("Accept created JIRAs? [Y/n] ")

	if accept.capitalize() in ["N"]:
		rootJBIDE.delete(deleteSubtasks=True)
		rootJBDS.delete(deleteSubtasks=True)

	# For sample usage, see findlostpatches.py.examples.txt
