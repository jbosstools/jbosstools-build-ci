from github import Github
import sys
import semantic_version
import csv
        
def checkexistingtags(g, reponame, expectedsha, expectedtag):
    
        repo = g.get_repo(reponame)

        foundtag = None
        
        for tag in repo.get_tags():
            if tag.name == expectedtag:
                foundtag = tag
                break
            
        if foundtag:
            if foundtag.commit.sha != expectedsha:
                print "WARNING:" + reponame + " has '" + foundtag.name + "' but expected sha '" + expectedsha + "' does not match '" + foundtag.commit.sha + "'"
            else:
                print "OK: " + reponame + " has '" + foundtag.name + "' with expected sha: '" + foundtag.commit.sha + "'"
        else:
            print "ERROR: " + reponame + ": tag '" + expectedtag + "' not found."
            answer = raw_input("Create '" + expectedtag + "' with sha: '" + expectedsha + "' in '" + reponame + "' ? ")
            if (answer=="y"):
                repo.create_git_ref("refs/tags/" + expectedtag , expectedsha)
                print "Tag created!"
            else:
                print "Ok - tag not created"
                    
           
if len(sys.argv) <> 4:
    print "Please specify username, github password and file with tag info"
    print "Usage: checktags.py <username> <password> <tagfile>"
    sys.exit(-1)
    
g = Github(sys.argv[1], sys.argv[2])


shas = {}

with open(sys.argv[3], 'rb') as csvfile:
    content = csv.reader(csvfile, delimiter=",")
    for row in content:
        if len(row) <> 3:
            print "bad row: " + str(row)
        else:
            checkexistingtags(g, row[0].strip(), row[1].strip(), row[2].strip())
