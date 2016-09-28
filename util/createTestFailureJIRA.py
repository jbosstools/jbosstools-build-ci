from jira.client import JIRA
import magic, pprint, ast, urllib, requests, re
from xml.dom import minidom
from optparse import OptionParser
from requests.auth import HTTPBasicAuth

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

usage = "Usage: %prog --affected <jbide version> --component <jbide component> --jira <JIRA server> --jirauser <JIRA user> --jirapwd <JIRA pwd> \
--test https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/<job_name>/<build_num>/testReport/ --testuser <user for test server> --testpwd <pwd for test server>  \n\n\
This script will create 1 JBIDE JIRA for the specified component, reporting the test failure from the Test Server testReport URL"
parser = OptionParser(usage)
parser.add_option("-a", "--affected", dest="jbideversion", help="JBIDE Affected Version, eg., 4.1.1.Alpha1")
parser.add_option("-c", "--component", dest="component", help="JBIDE component, eg., server, seam2, openshift")

parser.add_option("-j", "--jira", dest="jiraserver", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.org")
parser.add_option("-k", "--jirauser", dest="usernameJIRA", help="JIRA Username")
parser.add_option("-l", "--jirapwd", dest="passwordJIRA", help="JIRA Password")

parser.add_option("-t", "--test", dest="testurl", help="URL of the test failure(s), eg., https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/jbosstools-server_41/113/testReport/")
parser.add_option("-u", "--testuser", dest="usernameTestServer", help="Test Server Username, eg., shortname")
parser.add_option("-v", "--testpwd", dest="passwordTestServer", help="Test Server Password, eg., kerberos pwd")

(options, args) = parser.parse_args()

if not options.jbideversion or not options.component or \
    not options.jiraserver or not options.usernameJIRA or not options.passwordJIRA or \
    not options.testurl or not options.usernameTestServer or not options.passwordTestServer:
    parser.error("Must to specify ALL commandline flags")
    
jiraserver = options.jiraserver
jira = JIRA(options={'server':jiraserver}, basic_auth=(options.usernameJIRA, options.passwordJIRA))

jbide_affectedversion = options.jbideversion
component = options.component
testurl = options.testurl

## The jql query across for all testfailure issues
testfailuresearchquery = 'labels IN ("testfailure") AND project IN (JBIDE) AND affectedVersion IN ("' + jbide_affectedversion + '") AND component IN ("' + component + '")'
testfailuresearch = jiraserver + '/issues/?jql=' + urllib.quote_plus(testfailuresearchquery)
testfailuresearchlabel = 'Search for Test Failure JIRAs in JBIDE ' + jbide_affectedversion + ' for ' + component + ' component'

# result here is pretty-printed XML
def prettyXML(xml):
    uglyXml = xml.toprettyxml(indent='  ')
    text_re = re.compile('>\n\s+([^<>\s].*?)\n\s+</', re.DOTALL)    
    out = text_re.sub('>\g<1></', uglyXml)
    return out

def findChildNodeByName(parent, name):
    for node in parent.childNodes:
        if node.nodeType == node.ELEMENT_NODE and node.localName == name:
            return node
    return None

def getText(nodelist):
    rc = []
    for node in nodelist:
        if node.nodeType == node.TEXT_NODE:
            rc.append(node.data)
    return ''.join(rc)

print "\n" + testfailuresearchlabel + ":\n\n * " + testfailuresearch + "\n"

# query JIRA for existing issues, or else find "No issues were found to match your search"
#  https://issues.stage.jboss.org/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?jqlQuery=labels+%3D+testfailure&tempMax=1000
q = requests.get(jiraserver + '/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?tempMax=1000&jqlQuery=' + urllib.quote_plus(testfailuresearchquery), auth=HTTPBasicAuth(options.usernameJIRA, options.passwordJIRA), verify=False)
#print q.text
xml = minidom.parseString(q.text)
issuelist = xml.getElementsByTagName('item')
numExistingIssues = len(issuelist)
if numExistingIssues > 0 : 
    print "Found " + str(numExistingIssues) + " existing JIRAs:\n"
    for s in issuelist :
        print " * " + getText(findChildNodeByName(s, 'link').childNodes) + ": " + getText(findChildNodeByName(s, 'summary').childNodes).strip() + "\n"

accept = raw_input("Create new JIRA? [Y/n] ")
if accept.capitalize() not in ["N"] :

    ## get the XML or JSON content from the Jenkins test report page
    payload = {'wrapper': 'failures', 'xpath': "//case[status='FAILED']"}
    # print testurl
    r = requests.get(testurl + "api/xml", auth=HTTPBasicAuth(options.usernameTestServer, options.passwordTestServer), params=payload, verify=False)
    # print r.text
    xml = minidom.parseString(r.text)

    testcaselist = xml.getElementsByTagName('case') 
    failureSummary = '*' + str(len(testcaselist)) + ' Test Failure(s) in JBIDE ' + jbide_affectedversion + ' for ' + component + ' component:*\n\n' + testurl.strip() + '\n\n'
    failureDetails = '\n\n[' + testfailuresearchlabel + '|' + testfailuresearch + ']\n\n-----\n'

    for s in testcaselist :
        className = getText(findChildNodeByName(s, 'className').childNodes)
        className_re = re.sub(r'\.([a-zA-Z0-9_]+$)',"/\g<1>",className.strip())
        name = getText(findChildNodeByName(s, 'name').childNodes)
        name_re = re.sub(r'[\[\]]+',"_",name)
        age = getText(findChildNodeByName(s, 'age').childNodes)
        failureSummary = failureSummary + '# [' + className + '|' + testurl + '' + className_re + '/' + name_re + '] (failing for ' + age + ' builds)\n'

        failureDetails = failureDetails + '* {color:red}' + className + " : " + name + '{color} (failing for ' + age + ' builds) \n \n '
        failureDetails = failureDetails + '{code:title=' + testurl + '' + className_re + '/' + name_re + '}\n'
        failureDetails = failureDetails + prettyXML(s)
        failureDetails = failureDetails + '\n{code}\n\n'
        #print failureDetails

    rootJBIDE_dict = {
        'project' : { 'key': 'JBIDE' },
        'summary' :     str(len(testcaselist)) + ' Test Failure(s) in JBIDE ' + jbide_affectedversion + ' for ' + component + ' component',
        'description' :  failureSummary + failureDetails,
        'issuetype' : { 'name' : 'Task' },
        'priority' : { 'name' :'Critical'},
        'versions' : [{ "name" : jbide_affectedversion }],
        'components' : [{ "name" : component }],
        'labels' : [ "testfailure" ]
        }

    rootJBIDE = jira.create_issue(fields=rootJBIDE_dict)
    accept = raw_input("\nAccept new JIRA " + jiraserver + '/browse/' + rootJBIDE.key + " ? [Y/n] ")
    if accept.capitalize() in ["N"] :
        rootJBIDE.delete()

# see JIRA_components listing in components.py

# Sample usage: see createTestFailureJIRA.py.examples.txt