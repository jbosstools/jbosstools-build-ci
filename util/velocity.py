from jira import JIRA
from jira import Issue
from optparse import OptionParser

def getIssues(jira, board_id, sprint_id):
    """Return the issues for the sprint."""
    r_json = jira._get_json('board/%s/sprint/%s/issue?maxResults=1000' % (board_id, sprint_id),
                            base=jira.AGILE_BASE_URL)
    issues = [Issue(jira._options, jira._session, raw_issues_json) for raw_issues_json in
              r_json['issues']]
    return issues

def report(jira,name):
    boards = jira.boards(name=name)
    sboards = [x for x in boards if x.name == name]
    board = sboards[0]
    sprints = jira.sprints(board.id,maxResults=10000)
    asprints = [x for x in sprints if x.state == 'active']
    sprint = asprints[len(asprints) - 1]
    issues = getIssues(jira, board.id, sprint.id)
    reports = {}
    for x in issues:
        if x.fields.assignee:
            key = x.fields.assignee.name
            assigneeName = x.fields.assignee.displayName
        else:
            key = 'unassigned'
            assigneeName = 'Unassigned'
        if key not in reports.keys():
            reports[key] = [assigneeName,0,0]
        if x.fields.status.id == '10011' or x.fields.status.id == '5':
            reports[key][1] = reports[key][1] + 1
        else :
            reports[key][2] = reports[key][2] + 1
    print 'Status for ' + name + ' ' + sprint.name
    format=u'{:<20}{:<10}{:<10}{:<10}'
    print format.format('Name', 'Completed', 'Todo', 'Status')
    for x in reports:
        done = reports[x][1]
        todo = reports[x][2]
        ratio = (float(done) / (done + todo)) * 100
        print format.format(reports[x][0].encode('ascii', 'ignore'), done, todo, str(int(ratio)) + '%')

usage = 'Usage: %prog -u <user> -p <pass> [-s <JIRA server>]'
parser = OptionParser(usage)
parser.add_option("-u", "--user", dest="usernameJIRA", help="JIRA Username")
parser.add_option("-p", "--pwd", dest="passwordJIRA", help="JIRA Password")
parser.add_option("-s", "--server", dest="jiraserver", default="https://issues.jboss.org", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.or
g")
(options, args) = parser.parse_args()
if not options.usernameJIRA or not options.passwordJIRA or not options.jiraserver:
    parser.error("Must specify ALL commandline flags")

jira = JIRA(options={'server':options.jiraserver,'agile_rest_path':'agile'},basic_auth=(options.usernameJIRA,options.passwordJIRA))
report(jira,'ASSparta')
report(jira,'devstudio everything')