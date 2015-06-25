from github import Github, GithubException
import sys
import csv

if len(sys.argv) <> 3:
    print "Please specify both username and github password."
    print "Usage: checktags.py <username> <password>"
    sys.exit(-1)

repos = csv.reader(sys.stdin)
          
g = Github(sys.argv[1], sys.argv[2])

for counter, row in enumerate(repos):
    
    reponame = row[0].strip()
    sha1 = row[1].strip()
    tag = 'refs/tags/' + row[2].strip()
    results = "Failure!"
    print "Tagging " + reponame + " with " + sha1 +  " as "  + tag
    results = "Success!"
    try:
        repo = g.get_repo(reponame)
        repo.create_git_ref(tag , sha1)
        #ref = repo.get_git_ref('tags/' + row[2].strip())
        #ref.delete()
    except GithubException as ge:
        if ge.status == 422:
            results = str(ge)
        elif ge.status == 400:
            results = "Bad things happened 400"
        else:
            raise

        
    print results

    

