from jira.client import JIRA
import magic
import pprint
import urllib

from optparse import OptionParser

pp = pprint.PrettyPrinter(indent=4)

# Requires jira-python (See http://jira-python.readthedocs.org/en/latest/)
# If connection to JIRA server fails with error: "The error message is __init__() got an unexpected keyword argument 'mime'"
# Then go edit /usr/lib/python2.7/site-packages/jira/client.py 
# replace 
#         self._magic = magic.Magic(mime=True)
# with 
#         self._magic = magic
# 
# ref: http://stackoverflow.com/questions/12609402/init-got-an-unexpected-keyword-argument-mime-in-python-django

usage = "Usage: %prog -u <user> -p <password> -s <JIRA server> --jbide <jbideversion> --jbds <jbdsversion> \
-t <short task summary> -f <full detailed task description>\n\nThis script will create 1 JBDS and 1 JBIDE JIRA with the specified task summary + description, \
then create \nsub-tasks of the JBIDE JIRA for each of the JBIDE components with matching Github jbosstools-* repos"
parser = OptionParser(usage)
parser.add_option("-u", "--user", dest="username", help="JIRA Username")
parser.add_option("-p", "--pwd", dest="password", help="JIRA Password")
parser.add_option("-s", "--server", dest="jiraserver", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.org")
parser.add_option("-i", "--jbide", dest="jbidefixversion", help="JBIDE Fix Version, eg., 4.1.0.qualifier")
parser.add_option("-d", "--jbds", dest="jbdsfixversion", help="JBDS Fix Version, eg., 7.0.0.qualifier")
parser.add_option("-t", "--task", dest="taskdescription", help="Task Summary, eg., \"Code Freeze + Branch\"")
parser.add_option("-f", "--taskfull", dest="taskdescriptionfull", help="Task Description, eg., \"Please perform the following tasks...\"")
parser.add_option("-A", "--auto-accept", dest="autoaccept", action="store_true", help="if set, automatically accept created issues")
parser.add_option("-c", "--component", dest="component", help="JBIDE component, eg., server, seam2, openshift, or ALL")

# see createTaskJIRAs.py.examples.txt for examples of taskdescriptionfull

(options, args) = parser.parse_args()

if not options.username or not options.password or not options.jiraserver or not options.jbidefixversion or not options.jbdsfixversion or not options.taskdescription:
    parser.error("Must to specify ALL commandline flags")
    
jiraserver = options.jiraserver
jira = JIRA(options={'server':jiraserver}, basic_auth=(options.username, options.password))

jbide_fixversion = options.jbidefixversion
jbds_fixversion = options.jbdsfixversion
taskdescription = options.taskdescription
taskdescriptionfull = options.taskdescriptionfull
if not options.taskdescriptionfull:
    taskdescriptionfull = options.taskdescription

if not options.component or options.component == "ALL":
    # see JIRA_components listing in components.py
    from components import JIRA_components
    componentList = JIRA_components
    issuetype = 'Sub-task'
else:
    # just one task at a time
    componentList = { options.component: {options.component} }
    issuetype = 'Task'

## The jql query across for all task issues
tasksearchquery = '((project in (JBDS) and fixVersion = "' + jbds_fixversion + '") or (project in (JBIDE) and fixVersion = "' + jbide_fixversion + '")) AND labels = task'

tasksearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(tasksearchquery)

def nametuple(x):
    return { "name" : x }

def quote(x):
    return '"' + x + '"'

if not options.component or options.component == "ALL":
    rootJBDS_dict = {
        'project' : { 'key': 'JBDS' },
        'summary' :     'For JBDS ' + jbds_fixversion + ': ' + taskdescription,
        'description' : 'For JBDS ' + jbds_fixversion + ': ' + taskdescriptionfull + '\n\n[Search for all task JIRA|' + tasksearch + ']',
        'issuetype' : { 'name' : 'Task' },
        'priority' : { 'name' :'Blocker'},
        'fixVersions' : [{ "name" : jbds_fixversion }],
        'components' : [{ "name" : "installer" }],
        'labels' : [ "task" ],
        }
    rootJBDS = jira.create_issue(fields=rootJBDS_dict)
    print("Task JIRA created for this milestone include:")
    print("")

    print("JBDS              : " + jiraserver + '/browse/' + rootJBDS.key)

    rootJBIDE_dict = {
        'project' : { 'key': 'JBIDE' },
        'summary' :     'For JBIDE ' + jbide_fixversion + ': ' + taskdescription,
        'description' : 'For JBIDE ' + jbide_fixversion + ': ' + taskdescriptionfull + 
            '\n\n[Search for all task JIRA|' + tasksearch + ']\n\nSee also: ' + rootJBDS.key,
        'issuetype' : { 'name' : 'Task' },
        'priority' : { 'name' :'Blocker'},
        'fixVersions' : [{ "name" : jbide_fixversion }],
        'components' : [{ "name" : "build" }],
        'labels' : [ "task" ]
        }
    rootJBIDE = jira.create_issue(fields=rootJBIDE_dict)
    print("JBoss Tools       : " + jiraserver + '/browse/' + rootJBIDE.key)

for name, comps in componentList.iteritems():
    
    cms = map(nametuple, comps)    
    # print name + "->" + str(cms)

    comptasksearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(tasksearchquery + " and component in (" + ",".join(map(quote,comps)) + ")")
    
    rootJBIDE_dict = {
        'project' : { 'key': 'JBIDE' },
        'summary' :     'For JBIDE ' + jbide_fixversion + ': ' + taskdescription + ' [' + name.strip() + ']',
        'description' : 'For JBIDE ' + jbide_fixversion + ' [' + name.strip() + ']: ' + taskdescriptionfull + 
            '\n\n[Search for all task JIRA|' + tasksearch + '], or [Search for ' + name.strip() + ' task JIRA|' + comptasksearch + ']',
        'issuetype' : { 'name' : issuetype },
        #'parent' : { 'id' : rootJBIDE.key},
        'priority' : { 'name': 'Blocker'},
        'components' : cms,
        'labels' : [ "task" ]
    }
    # if subtask, set parent
    if issuetype == 'Sub-task' and rootJBIDE.key:
        rootJBIDE_dict['parent'] = { 'id' : rootJBIDE.key }
    else:
        # if task, set fixversion
        rootJBIDE_dict['fixVersions'] =[{ "name" : jbide_fixversion }]

    child = jira.create_issue(fields=rootJBIDE_dict)
    print(name +  ": " + jiraserver + '/browse/' + child.key)

if (not options.autoaccept):
    accept = raw_input("Accept created JIRAs? [Y/n] ")
    if accept.capitalize() in ["N"]:
        try:
            rootJBIDE
        except NameError:
            child.delete()
        else:
            rootJBIDE.delete(deleteSubtasks=True)
        try:
            rootJBDS
        except NameError:
            True
        else:
            rootJBDS.delete(deleteSubtasks=True)

# For sample usage, see createTaskJIRAs.py.examples.txt
