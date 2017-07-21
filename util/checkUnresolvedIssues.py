from jira import JIRA
import magic, ast, urllib, requests, re, sys
from xml.dom import minidom
from optparse import OptionParser
from requests.auth import HTTPBasicAuth

import components

# Requires jira-python (See http://jira-python.readthedocs.org/en/latest/)
# If connection to JIRA server fails with error: "The error message is __init__() got an unexpected keyword argument 'mime'"
# Then go edit /usr/lib/python2.7/site-packages/jira/client.py 
# replace 
#		 self._magic = magic.Magic(mime=True)
# with 
#		 self._magic = magic
# 
# ref: http://stackoverflow.com/questions/12609402/init-got-an-unexpected-keyword-argument-mime-in-python-django

usage = "Usage: python -W ignore %prog \\ \n\
  --jbt      <version_jbt>      --ds      <version_ds>      --sprint      <sprint> \\ \n\
  --jbt_NEXT <version_jbt_NEXT> --ds_NEXT <version_ds_NEXT> --sprint_NEXT <sprint_NEXT> \\ \n\
  --jira <JIRA server>          --jirauser <JIRA user>      --jirapwd <JIRA pwd>\n\
  \n\
Optional flags:\n\
  -S (skip validation of FixVersion values to save time) \n\
  -A (automatically apply suggested changes) \n\
  -X (to enable debugging) \n\
\n\
This script will check for unresolved issues from the specified JBIDE/JBDS fixversions or sprint, \n\
then move them to the next fixversion or to the .x backlog, depending on if they're \n\
already queued for a future sprint or are blocker/critical."
parser = OptionParser(usage)
parser.add_option("--sprint",     dest="sprint",           help="Current Sprint, eg., devex #134 Jun 2017")
parser.add_option("--sprint_NEXT",dest="sprint_NEXT",      help="Future Sprint, eg., devex #135 July 2017")
parser.add_option("--jbt",        dest="version_jbt",      help="Current JBIDE fix version")
parser.add_option("--jbt_NEXT",   dest="version_jbt_NEXT", help="Next JBIDE fix version")
parser.add_option("--ds",         dest="version_ds",       help="Current JBDS fix version")
parser.add_option("--ds_NEXT",    dest="version_ds_NEXT",  help="Next JBDS fix version")

parser.add_option("--jira",     dest="jiraserver", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.org")
parser.add_option("--jirauser", dest="jirauser",   help="JIRA Username")
parser.add_option("--jirapwd",  dest="jirapwd",    help="JIRA Password")

parser.add_option("-S",  dest="skipVersionValidation", action="store_true", help="Skip validation of FixVersion values to save time")
parser.add_option("-A",  dest="autoApplyChanges", action="store_true", help="If set, automatically accept created issues")
parser.add_option("-X",  dest="debug", action="store_true", help="Debug output")
(options, args) = parser.parse_args()

if \
	not options.version_jbt or not options.version_jbt_NEXT or \
	not options.version_ds or not options.version_ds_NEXT or \
	not options.sprint or not options.sprint_NEXT or \
	not options.jiraserver or not options.jirauser or not options.jirapwd:
	parser.error("Must to specify ALL commandline flags")
	
jiraserver = options.jiraserver
jirauser = options.jirauser
jirapwd = options.jirapwd
debug = options.debug
components.debug = debug

version_jbt = options.version_jbt
version_jbt_NEXT = options.version_jbt_NEXT
fixversion_bits = version_jbt_NEXT.split(".")
version_jbt_DOTX = fixversion_bits[0]+"."+fixversion_bits[1]+".x"

version_ds = options.version_ds
version_ds_NEXT = options.version_ds_NEXT
fixversion_bits = version_ds_NEXT.split(".")
version_ds_DOTX = fixversion_bits[0]+".x"

sprint = options.sprint
sprint_NEXT = options.sprint_NEXT
sprintId = None # not used other than to verify the sprint exists
sprintId_NEXT = None # used to set a new sprint value

def missingFixversion(version_jbt, version_ds):
	sys.exit("[ERROR] FixVersion does not exist. Go bug " + components.defaultAssignee() + " to get it created.")

sprintId = components.getSprintId(sprint, jiraserver, jirauser, jirapwd)
sprintId_NEXT = components.getSprintId(sprint_NEXT, jiraserver, jirauser, jirapwd)
if not options.skipVersionValidation:
	if components.checkFixVersionsExist(version_jbt, version_ds, jiraserver, jirauser, jirapwd) == False:
		missingFixversion(version_jbt, version_ds)
	if components.checkFixVersionsExist(version_jbt_NEXT, version_ds_NEXT, jiraserver, jirauser, jirapwd) == False:
		missingFixversion(version_jbt_NEXT, version_ds_NEXT)
	if components.checkFixVersionsExist(version_jbt_DOTX, version_ds_DOTX, jiraserver, jirauser, jirapwd) == False:
		missingFixversion(version_jbt_DOTX, version_ds_DOTX)

###################################################

def updateIssues(issuelist, NEXTorDOTX, description):
	numExistingIssues = len(issuelist) if not issuelist == None else 0
	if numExistingIssues > 0 : 
		if debug: print "[DEBUG] Move " + str(numExistingIssues) + " " + description
		jira = JIRA(options={'server':jiraserver}, basic_auth=(jirauser, jirapwd))

		for s in issuelist :
			key = components.getText(components.findChildNodeByName(s, 'key').childNodes)

			operation = " + Update " + \
				components.getText(components.findChildNodeByName(s, 'link').childNodes) + " : " + \
				components.getText(components.findChildNodeByName(s, 'summary').childNodes).strip()
			if options.autoApplyChanges: 
				print operation
			else:
				yesno = raw_input(operation + " ? [Y/n] ")
			if options.autoApplyChanges or yesno.capitalize() in ["Y"]:
				# move issue to next fixversion
				if components.findChildNodeByName(s, 'project').attributes["key"].value == "JBIDE": # JBIDE or JBDS
					fixversion = version_jbt
					fixversion_NEXT = version_jbt_NEXT if NEXTorDOTX else version_jbt_DOTX
				else:
					fixversion = version_ds
					fixversion_NEXT = version_ds_NEXT if NEXTorDOTX else version_ds_DOTX

				fixVersions = []
				issue = jira.issue(key)
				# NOTE: if there is more than one fixversion, the others will not be changed
				for version in issue.fields.fixVersions:
					if version.name != fixversion:
						fixVersions.append({'name': version.name})
				fixVersions.append({'name': fixversion_NEXT})
				issue.update(fields={'fixVersions': fixVersions})

				# only for NEXT, not for .x
				if NEXTorDOTX:
					# move issue to new sprint
					jira.add_issues_to_sprint(sprintId_NEXT, [key])

print "[INFO] [1] Check " + sprint + " + " + sprint_NEXT + ", JBIDE " + version_jbt + " + JBDS " + version_ds + \
	", for unresolved blockers/criticals + issues in NEXT sprint: " + \
	"move to NEXT sprint/milestone"
query = 'resolution = null AND ( \
	( \
	( (project = JBIDE AND fixVersion = "' + version_jbt + '") OR (project = JBDS AND fixVersion = "' + version_ds + '") ) \
	AND \
	sprint ="' + sprint_NEXT + '") OR \
	(sprint="' + sprint + '" AND priority in (blocker,critical)) \
	)'
updateIssues(components.getIssuesFromQuery(query, jiraserver, jirauser, jirapwd), True, \
	"issues to fixversion = " + version_jbt_NEXT + "/" + version_ds_NEXT + " and sprint = " + sprint_NEXT + " (" + sprintId_NEXT + ")")

# TODO should these be removed from the current sprint?
print "[INFO] [2] Check JBIDE " + version_jbt + " + JBDS " + version_ds + \
	", for unresolved issues NOT in the next sprint: " + \
	"move to .x"
query = 'resolution = null AND \
	((project = JBIDE AND fixVersion = "' + version_jbt + '") OR (project = JBDS AND fixVersion = "' + version_ds + '")) AND \
	sprint not IN ("' + sprint_NEXT + '")'
updateIssues(components.getIssuesFromQuery(query, jiraserver, jirauser, jirapwd), False, \
	"issues to fixversion = .x")


# Sample usage: see checkUnresolvedIssues.py.examples.txt