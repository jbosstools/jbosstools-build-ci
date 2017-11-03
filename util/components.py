debug = 'debug' in globals()

## map from descriptive name to list of JBIDE and/or JBDS components in JIRA.
JIRA_components = {
    "Aerogear          ": { "aerogear-hybrid", "cordovasim" },
    "Arquillian        ": { "arquillian" },
    # "Error Reporting " : {"aeri"},
    "Base              ": { "common", "foundation", "usage" },
    # "Batch           ": { "batch"},
    "BrowserSim        ": { "browsersim" },
    "build, ci, maven-plugins": { "build" },
    "build-sites       ": { "updatesite" },
    "Central           ": { "central", "maven", "project-examples" },
    # "CDI             " : { "cdi"},
    "Discovery         ": { "central-update" },
    # "Docker          ": { "docker" },
    "dl.j.o, devdoc    ": { "website" },
    # "Easymport       ": { "easymport" },
    "Forge             ": { "forge" },
    #"Freemarker        ": { "freemarker" },
    "Fuse Tooling      ": { "fusetools" },
    "Fuse Tooling Extras":{ "fusetools-extras" },
    "Hibernate         ": { "hibernate"},
    "Integration-Tests ": { "qa" },
    "JavaEE            ": { "jsf", "seam2", "cdi", "cdi-extensions", "jsp/jsf/xml/html-source-editing"},
    # "javascript      ": { "javascript", "nodejs"},
    "JST               ": { "jst"},
    "LiveReload        ": { "livereload" },
    # "Maven           ": { "maven"},
    "OpenShift         ": { "openshift", "cdk" },
    # "Project Examples": { "project-examples"},
    "Server            " : {  "server", "archives", "jmx" },
    # "Usage Analytics " : { "usage"},
    "versionwatch      ": { "versionwatch" },
    "VPE               ": { "visual-page-editor-core", "visual-page-editor-templates"},
    "Webservices       ": { "webservices"}
    }

# there are more N&N pages than there are JIRA components (eg., jbosstools-central includes Central, Maven and Project Examples) so this list is a bit different from teh above one
# # first component listed in the set will be the one used to assign the JIRA
NN_components = {
    "Aerogear          ": { "aerogear-hybrid", "cordovasim" },
    "Arquillian        ": { "arquillian" },
    "Error Reporting   " : {"aeri"},
    "Base              ": { "common", "foundation", "usage" },
    "Batch             ": { "batch"},
    "BrowserSim        ": { "browsersim" },
    # "build, ci, maven-plugins": { "build" },
    # "build-sites     ": { "updatesite" },
    "Central           ": { "central", "maven", "project-examples" },
    "CDI               ": { "cdi"},
    # "Discovery       ": { "central-update" },
    "Docker            ": { "docker" },
    # "dl.j.o, devdoc  ": { "website" },
    "Easymport         ": { "easymport" },
    "Forge             ": { "forge"},
    #"Freemarker        ": {"freemarker"},
    "Fuse Tools        ": { "fusetools", "fusetools-extras" },
    "Hibernate         ": { "hibernate"},
    # "Integration-Tests": { "qa" },
    # "JavaEE          ": { "jsf", "seam2", "cdi", "cdi-extensions" },
    "Javascript        ": { "javascript", "nodejs"},
    "JSF               ": { "jsp/jsf/xml/html-source-editing", "jsf"},
    "JST               ": { "jst"},
    "LiveReload        ": { "livereload" },
    "Maven             ": { "maven"},
    "OpenShift         ": { "openshift", "cdk" },
    "Project Examples  ": { "project-examples"},
    "Server            " : {  "server", "archives", "jmx" },
    "Usage Analytics   " : { "usage"},
    # "versionwatch    ": { "versionwatch" },
    "Visual Editor     ": { "visual-page-editor-core", "visual-page-editor-templates"},
    "Webservices / Rest": { "webservices"}
    }

# def checkSprintExists (sprint_name, jiraserver, jirauser, jirapwd):
#     import requests, re, urllib
#     from requests.auth import HTTPBasicAuth

#     # should never happen
#     if sprint_name is None:
#         print "\n[ERROR] Sprint " + sprint_name + " can not be None\n"
#         return False

#     testSprintExistsQuery = 'sprint = "' + sprint_name + '"'
#     # print "\n" + 'Search for sprint ' + sprint_name + ":\n * " + jiraserver + \
#     #    '/issues/?jql=' + urllib.quote_plus(testSprintExistsQuery) + "\n" + \
#     #    " * https://issues.stage.jboss.org/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?tempMax=1000&jqlQuery=" + \
#     #   urllib.quote_plus(testSprintExistsQuery)
#     q = requests.get(jiraserver + '/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?tempMax=1000&jqlQuery=' + \
#         urllib.quote_plus(testSprintExistsQuery), \
#         auth=HTTPBasicAuth(jirauser, jirapwd), verify=False)
#     # print q.text
#     if re.search("Sprint with name '" + sprint_name + "' does not exist or you do not have permission to view it", q.text):
#         print "\n[ERROR] Sprint with name '" + sprint_name + "' does not exist or you do not have permission to view it, on " + jiraserver + "\n"
#         return None
#     else:
#         return getSprintId(sprint_name)

def checkFixVersionsExist (jbide_fixversion, jbds_fixversion, jiraserver, jirauser, jirapwd):
    import requests, re, urllib
    from requests.auth import HTTPBasicAuth

    # should never happen
    if jbide_fixversion is None:
        print "\n[ERROR] JBIDE fixversion " + jbide_fixversion + " can not be None\n"
        return False

    # verify that fixversions are valid and exist on the target jira server
    if jbds_fixversion is not None:
        testFixVersionsExistQuery = '((project IN (JBIDE) AND fixVersion = "' + jbide_fixversion + '") AND (project IN (JBDS) AND fixVersion = "' + jbds_fixversion + '"))'
    else:
        testFixVersionsExistQuery = 'project IN (JBIDE) AND fixVersion = "' + jbide_fixversion + '"'
    # print "\n" + 'Search for JIRAs in JBIDE ' + jbide_fixversion + ' and JBDS ' + jbds_fixversion + ":\n\n * " + jiraserver + \
    #   '/issues/?jql=' + urllib.quote_plus(testFixVersionExistsSearchquery) + \
    #   " * https://issues.stage.jboss.org/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?tempMax=1000&jqlQuery=" + \
    #   urllib.quote_plus(testFixVersionExistsSearchquery)
    q = requests.get(jiraserver + '/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?tempMax=1000&jqlQuery=' + \
        urllib.quote_plus(testFixVersionsExistQuery), \
        auth=HTTPBasicAuth(jirauser, jirapwd), verify=False)
    # check for string: The value '4.4.7.foo' does not exist for the field 'fixVersion'
    if re.search("The value '" + jbide_fixversion + "' does not exist for the field 'fixVersion'", q.text):
       print "\n[ERROR] JBIDE fixversion " + jbide_fixversion + " does not exist on " + jiraserver + "\n"
       return False
    elif jbds_fixversion is not None and re.search("The value '" + jbds_fixversion + "' does not exist for the field 'fixVersion'", q.text):
       print "\n[ERROR] JBDS fixversion " + jbds_fixversion + " does not exist on " + jiraserver + "\n"
       return False
    else:
        return True

# default assignee if can't find one in JIRA
def defaultAssignee():
    return "jeffmaury"

def queryComponentLead (componentList, componentID, nameOrDisplayName):
    # print "Search for component lead of " + projectID+":"+componentID+" on "+jiraserver+"..."
    for c in componentList:
        # print c.name
        if c.name == componentID:
            if nameOrDisplayName == 1:
                return c.lead.displayName # pretty name
            else:
                return c.lead.name # ID
    # if component not found, return default assignee
    return defaultAssignee()
# examples
# jira = JIRA(options={'server':jiraserver}, basic_auth=(options.usernameJIRA, options.passwordJIRA))
# print queryComponentLead(jira.project_components(jira.project('JBIDE')), 'build', 0)
# print queryComponentLead(jira.project_components(jira.project('JBIDE')), 'build', 1)

# result here is pretty-printed XML
def prettyXML(xml):
    uglyXml = xml.toprettyxml(indent='  ')
    text_re = re.compile('>\n\s+([^<>\s].*?)\n\s+</', re.DOTALL)    
    out = text_re.sub('>\g<1></', uglyXml)
    return out

def findChildNodeByNameCheckData(parent, name, dataMatch):
    for node in parent.childNodes:
        if node.nodeType == node.ELEMENT_NODE and node.localName == name:
            if debug: print "[DEBUG] Check this Sprint node: " + node.toxml()
            for n in node.childNodes:
                if n.nodeType == n.TEXT_NODE:
                    if n.data == dataMatch:
                        return node
    return None

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

def getSprintId(sprint, jiraserver, jirauser, jirapwd):
    import sys
    
    customfieldvalues = doQuery('sprint ="' + sprint + '"', 'customfield', jiraserver, jirauser, jirapwd, 1, 
        "Sprint with name '" + sprint + "' does not exist or you do not have permission to view it")
    if customfieldvalues != None:
        for s in customfieldvalues :
            if getText(findChildNodeByName(s, 'customfieldname').childNodes) == "Sprint":
                sprintNode = findChildNodeByNameCheckData(findChildNodeByName(s, 'customfieldvalues'), 'customfieldvalue',sprint)
                if debug: print "[DEBUG] Found sprint node matching " + sprintNode.childNodes[0].data
                sprintId = sprintNode.attributes["id"].value
                if debug: print "[DEBUG] Found sprintId = " + sprintId + " in " + sprintNode.toxml()
                return sprintId
    sys.exit("[ERROR] Sprint '" + sprint + "' does not yet exist. Go bug " + defaultAssignee() + " to get it created.")
    return None

def getIssuesFromQuery(query, jiraserver, jirauser, jirapwd):
    return doQuery(query, 'item', jiraserver, jirauser, jirapwd, 1000)

def doQuery(query, field, jiraserver, jirauser, jirapwd, limit, failcheck = None):
    # debug = True
    import requests, re, urllib
    from requests.auth import HTTPBasicAuth
    from xml.dom import minidom
    queryURL = jiraserver + '/issues/?jql=' + urllib.quote_plus(query)
    payloadURL = jiraserver + '/sr/jira.issueviews:searchrequest-xml/temp/SearchRequest.xml?tempMax='+str(limit)+'&jqlQuery=' + \
        urllib.quote_plus(query)
    if debug:
        print "[DEBUG] " + query
        print "[DEBUG] " + queryURL
        print "[DEBUG] " + payloadURL
    q = requests.get(payloadURL, auth=HTTPBasicAuth(jirauser, jirapwd), verify=False)
    # print q.text
    if failcheck != None:
        if re.search(failcheck, q.text):
            return None
    xml = minidom.parseString(q.text)
    issuelist = xml.getElementsByTagName(field)
    numExistingIssues = len(issuelist)
    if numExistingIssues > 0 : 
        if debug: print "[DEBUG] Found " + str(numExistingIssues) + " nodes(s) to process"
    return issuelist
