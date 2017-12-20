from __future__ import print_function
import httplib2
import os

from apiclient import discovery
from oauth2client import client
from oauth2client import tools
from oauth2client.file import Storage
from optparse import OptionParser
from jira import JIRA
from jira import Issue

# If modifying these scopes, delete your previously saved credentials
# at ~/.credentials/sheets.googleapis.com-python-quickstart.json
SCOPES = 'https://www.googleapis.com/auth/spreadsheets'
CLIENT_SECRET_FILE = 'backlog_secret.json'
APPLICATION_NAME = 'Backlog'
SPREADSHEET_ID = '15bOdu6DPJ4K-q3zUaNoKDfrGs-O60r_osbv04vn0vNw'


def get_credentials():
    """Gets valid user credentials from storage.

    If nothing has been stored, or if the stored credentials are invalid,
    the OAuth2 flow is completed to obtain the new credentials.

    Returns:
        Credentials, the obtained credential.
    """
    home_dir = os.path.expanduser('~')
    credential_dir = os.path.join(home_dir, '.credentials')
    if not os.path.exists(credential_dir):
        os.makedirs(credential_dir)
    credential_path = os.path.join(credential_dir,
                                   'backlog.json')

    store = Storage(credential_path)
    credentials = store.get()
    if not credentials or credentials.invalid:
        flow = client.flow_from_clientsecrets(CLIENT_SECRET_FILE, SCOPES)
        flow.user_agent = APPLICATION_NAME
        import argparse
        flags = argparse.ArgumentParser(parents=[tools.argparser]).parse_args([])
        flags.noauth_local_webserver = True
        credentials = tools.run_flow(flow, store, flags)
        print('Storing credentials to ' + credential_path)
    return credentials

def getValuesAPI(credentials):
    http = credentials.authorize(httplib2.Http())
    discoveryUrl = ('https://sheets.googleapis.com/$discovery/rest?'
                    'version=v4')
    service = discovery.build('sheets', 'v4', http=http,
                              discoveryServiceUrl=discoveryUrl)
    return service.spreadsheets().values()
    
def getBoard(jira,name):
    boards = jira.boards(name=name)
    sboards = [x for x in boards if x.name == name]
    return sboards[0]

def getBacklogIssues(jira,board,max):
    r_json = jira._get_json('board/%s/backlog?maxResults=%s' % (board.id,max),
                            base=jira.AGILE_BASE_URL)
    issues = [Issue(jira._options, jira._session, raw_issues_json) for raw_issues_json in
              r_json['issues']]
    return issues

def reportIssues(issues, spreadsheetId, valuesAPI, jiraServer, fieldName):
    rangeName = 'A2:D'
    result = valuesAPI.get(
        spreadsheetId=spreadsheetId, range=rangeName).execute()
    values = result.get('values', [])
    for issue in issues:
        insert = True
        if values:
            for row in values:
                if (row[0] == issue.key):
                    insert = False
                    break
        if insert:
            if (fieldName and issue.raw['fields'][fieldName]):
                request = valuesAPI.append(spreadsheetId=spreadsheetId, body={"values":[[issue.key, jiraServer + '/browse/' + issue.key, issue.fields.summary, issue.raw['fields'][fieldName]]]},range=rangeName,
            valueInputOption='RAW')
            else:
                request = valuesAPI.append(spreadsheetId=spreadsheetId, body={"values":[[issue.key, jiraServer + '/browse/' + issue.key, issue.fields.summary]]},range=rangeName,
            valueInputOption='RAW')
            update = request.execute()

def getStoryPointsFieldId(jira):
    id = None
    fields = jira.fields()
    for field in fields:
        if (field['name'] == 'Story Points'):
            id = field['id']
            break
    return id    

usage = 'Usage: %prog -u <user> -p <pass> [-s <JIRA server>] [-f client_secret file] [-i spreadsheet_id]'
parser = OptionParser(usage)
parser.add_option("-u", "--user", dest="usernameJIRA", help="JIRA Username")
parser.add_option("-p", "--pwd", dest="passwordJIRA", help="JIRA Password")
parser.add_option("-s", "--server", dest="jiraserver", default="https://issues.jboss.org", help="JIRA server, eg., https://issues.stage.jboss.org or https://issues.jboss.org")
parser.add_option("-l", "--length", dest="length", default=25, help="length, take the n top items from the baclog defaults to 25")
parser.add_option("-f", "--client_secret", dest="client_secret", default=CLIENT_SECRET_FILE, help="client secret file, eg. client_secret.json")
parser.add_option("-i", "--spreadsheet", dest="spreadsheetId", default=SPREADSHEET_ID, help="spreadsheet id")
(options, args) = parser.parse_args()
if not options.usernameJIRA or not options.passwordJIRA or not options.jiraserver:
    parser.error("Must specify ALL commandline flags")
credentials = get_credentials()
valuesAPI = getValuesAPI(credentials)
jira = JIRA(options={'server':options.jiraserver,'agile_rest_path':'agile'},basic_auth=(options.usernameJIRA,options.passwordJIRA))
board = getBoard(jira, 'ASSparta')
fieldName = getStoryPointsFieldId(jira)
issues = getBacklogIssues(jira, board, options.length)
reportIssues(issues, options.spreadsheetId, valuesAPI, options.jiraserver, fieldName)
