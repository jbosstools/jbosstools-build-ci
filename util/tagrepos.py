from github import Github, GithubException
import sys
import csv

if len(sys.argv) <> 4:
    print "Please specify both username and github password."
    print "Usage: checktags.py <username> <password> <tagfile>"
    sys.exit(-1)

repos = csv.reader(open(sys.argv[3]))
          
g = Github(sys.argv[1], sys.argv[2])

for counter, row in enumerate(repos):
    
    reponame = row[0].strip()
    sha1 = row[1].strip()
    tag = 'refs/tags/test' + str(counter)
    results = "Failure!"
    print "Tagging " + row[0] + " with " + row[1] +  " as "  + tag
    results = "Success!"
    try:
        repo = g.get_repo(reponame)
        repo.create_git_ref(tag , sha1)
    except GithubException as ge:
        if ge.status == 422:
            results = ge['message']
            print results
        else:
            raise
        
    print results

    

