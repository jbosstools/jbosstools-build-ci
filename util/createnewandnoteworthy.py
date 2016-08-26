from jira.client import JIRA

import pprint
import urllib

from optparse import OptionParser

pp = pprint.PrettyPrinter(indent=4)

usage = "usage: %prog -u <user> -p <password> --jbide <jbideversion> --jbds <jbdsversions> \nCreates NN jira + subtasks.\nRequires you have installed jira-python (See http://jira-python.readthedocs.org/en/latest/)"
parser = OptionParser(usage)
parser.add_option("-u", "--user", dest="username", help="jira username")
parser.add_option("-p", "--pwd", dest="password", help="jira password")
parser.add_option("-i", "--jbide", dest="jbidefixversion", help="JBIDE fix version")
parser.add_option("-d", "--jbds", dest="jbdsfixversion", help="JBDS fix version")

(options, args) = parser.parse_args()

if not options.username or not options.password or not options.jbidefixversion or not options.jbdsfixversion:
    parser.error("Need to specify all")
    
jira = JIRA(options={'server':'https://issues.jboss.org'}, basic_auth=(options.username, options.password))

jbide_fixversion = options.jbidefixversion
jbds_fixversion = options.jbdsfixversion

## The jql query across for all N&N
nnsearchquery = '((project in (JBDS) and fixVersion = "' + jbds_fixversion + '") or (project in (JBIDE) and fixVersion = "' + jbide_fixversion + '")) AND resolution = Done AND labels = new_and_noteworthy'

nnsearch = 'https://issues.jboss.org/issues/?jql=' + urllib.quote_plus(nnsearchquery)

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

print("created " + rootnn.key)

## map from descriptive name to list of JBIDE and/or JBDS components.
## it is assumed if the component name is the same, they are the same across the two jiras
components = {
    "BrowserSim" : { "browsersim"},
    "Live Reload" : { "livereload" },
    "Usage Analytics" : { "usage"},
    "Automatic Error reporting" : {"aeri"},
   ## Outdated?    "GWT" : { "gwt"},
    "CDI" : { "cdi"},
    "Batch": { "batch"},
    "Freemarker": {"freemarker"},
    "hibernate" : { "hibernate"}, 
   ## not needed anymore "JBoss ESB" : { "esb"},
    "server" : {  "server", "archives", "jmx" },
    "jst/jsf": { "jsp/jsf/xml/html-source-editing", "jsf"},
    "javascript": { "javascript", "nodejs"},
    "Visual Editor": { "visual-page-editor-core", "visual-page-editor-templates"},
    "Webservices and Rest": { "webservices"},
    "Project Examples": { "project-examples"},
    "Maven": { "maven"},
    "Forge": { "forge"},
    "OpenShift": { "openshift"},
    "Docker": { "docker"},
    "JBoss Central": { "central"},
    "Core/General": { "common/jst/core"},
    "Easy import": { "easymport"},
    "Arquillian": { "arquillian" },
    "Aerogear": { "aerogear-hybrid" }
    }


def nametuple(x):
    return { "name" : x }

def quote(x):
    return '"' + x + '"'

for name, comps in components.iteritems():
    
    cms = map(nametuple, comps)    
    #print name + "->" + str(cms)

    compnnsearch = 'https://issues.jboss.org/issues/?jql=' + urllib.quote_plus(nnsearchquery + " and component in (" + ",".join(map(quote,comps)) + ")")
    
    rootnn_description_milestone = 'This [query|' + compnnsearch + '] contains the search for the specific component(s), to see all, use this [query|' + nnsearch + '].\n\n If ' + name + ' is not listed here check if there are issues that should be added and add them.\n\n Document the ones relevant for ' + name + ' by adding to [whatsnew|https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew] and submit a pull request.\n\n If no news for this component please reject and close this issue.'

    rootnn_description_final = 'If no news for ' + jbide_fixversion + ' since the last CR release for this component please reject and close this issue. The final N&N page will be aggregated from all previous N&N documents.\n\n If you want to add a comment to the final document then create a separate <component>-news-' + jbide_fixversion + '.adoc file in [whatsnew|https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew] and submit a pull request. The final N&N page will be aggregated from all previous N&N documents plus this *.Final.adoc.\n\n If you want to replace all previous N&Ns by a new document then create a new <component>-news-' + jbide_fixversion + '.adoc file in [whatsnew|https://github.com/jbosstools/jbosstools-website/tree/master/documentation/whatsnew], add \"page-include-previous: false\" attribute to the document and submit a pull request.\n\n This [query|' + compnnsearch + '] contains the search for the specific component(s), to see all, use this [query|' + nnsearch + '].'

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
    print("created child for " + name +  "->" + child.key)

raw_input("Press Enter to delete...or ctrl+c to be ok with the created content")

rootnn.delete(deleteSubtasks=True)

