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
parser.add_option("-s", "--server", dest="jiraserver", help="JIRA server, eg., https://issues-stg.jboss.org or https://issues.jboss.org")
parser.add_option("-i", "--jbide", dest="jbidefixversion", help="JBIDE Fix Version, eg., 4.1.0.qualifier")
parser.add_option("-d", "--jbds", dest="jbdsfixversion", help="JBDS Fix Version, eg., 7.0.0.qualifier")
parser.add_option("-t", "--task", dest="taskdescription", help="Task Summary, eg., \"Code Freeze + Branch\"")
parser.add_option("-f", "--taskfull", dest="taskdescriptionfull", help="Task Description, eg., \"Please perform the following tasks...\"")
parser.add_option("-A", "--auto-accept", dest="autoaccept", action="store_true", help="if set, automatically accept created issues")

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

## The jql query across for all task issues
tasksearchquery = '((project in (JBDS) and fixVersion = "' + jbds_fixversion + '") or (project in (JBIDE) and fixVersion = "' + jbide_fixversion + '")) AND labels = task'

tasksearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(tasksearchquery)

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
    'description' : 'For JBIDE ' + jbide_fixversion + ': ' + taskdescriptionfull + '\n\n[Search for all task JIRA|' + tasksearch + ']\n\nSee also: ' + rootJBDS.key,
    'issuetype' : { 'name' : 'Task' },
    'priority' : { 'name' :'Blocker'},
    'fixVersions' : [{ "name" : jbide_fixversion }],
    'components' : [{ "name" : "build" }],
    'labels' : [ "task" ]
    }
rootJBIDE = jira.create_issue(fields=rootJBIDE_dict)
print("JBoss Tools       : " + jiraserver + '/browse/' + rootJBIDE.key)

## map from descriptive name to list of JBIDE and/or JBDS components.
JBT_components = {

# active projects
    "Aerogear          ": { "aerogear-hybrid", "cordovasim" },
    "Base              ": { "common/jst/core", "usage" },
    "Forge             ": { "forge" },
    "Server            ": { "server" },
    "Webservices       ": { "webservices" },
    "Hibernate         ": { "hibernate"}, 
    "VPE               ": { "visual-page-editor-core" },
    "BrowserSim        ": { "browsersim" },
    "JST               ": { "common/jst/core" },
    "JavaEE            ": { "jsf", "seam2", "cdi", "cdi-extensions" },
    "Central           ": { "central", "maven", "project-examples" },
    "Arquillian        ": { "arquillian" }, # Note: s/testing-tools/arquillian/
    "LiveReload        ": { "livereload" },
    "OpenShift         ": { "openshift", "cdk" },
    "Freemarker        ": { "freemarker" },

    "Integration Tests ": { "qa" },
    "Central Discovery ": { "central-update" },
    "build, build-sites, build-ci, maven-plugins, dl.jb.org, devdoc, versionwatch": { "build" }
    }

def nametuple(x):
    return { "name" : x }

def quote(x):
    return '"' + x + '"'

for name, comps in JBT_components.iteritems():
    
    cms = map(nametuple, comps)    
    #print name + "->" + str(cms)

    comptasksearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(tasksearchquery + " and component in (" + ",".join(map(quote,comps)) + ")")
    
    rootJBIDE_dict = {
        'project' : { 'key': 'JBIDE' },
        'summary' :     'For JBIDE ' + jbide_fixversion + ': ' + taskdescription + ' [' + name.strip() + ']',
        'description' : 'For JBIDE ' + jbide_fixversion + ' [' + name.strip() + ']: ' + taskdescriptionfull + 
            '\n\n[Search for all task JIRA|' + tasksearch + '], or [Search for ' + name.strip() + ' task JIRA|' + comptasksearch + ']',
        'issuetype' : { 'name' : 'Sub-task' },
        'parent' : { 'id' : rootJBIDE.key},
        'priority' : { 'name': 'Blocker'},
        'components' : cms,
        'labels' : [ "task" ]
    }

    child = jira.create_issue(fields=rootJBIDE_dict)
    print(name +  ": " + jiraserver + '/browse/' + child.key)

if (not options.autoaccept):
    accept = raw_input("Accept created JIRAs? [Y/n] ")
    if accept.capitalize() in ["N"]:
        rootJBIDE.delete(deleteSubtasks=True)
        rootJBDS.delete(deleteSubtasks=True)

# For sample usage, see createTaskJIRAs.py.examples.txt
