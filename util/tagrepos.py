from github import Github, GithubException
import sys
import csv

if len(sys.argv) <> 3:
	print "Please specify both username and github password."
	print "Usage: cat tags.csv | tagrepos.py <username> <password>"
	print "Takes CSV formatted stream as input following the format: "
	print "github-reponame, sha1, tag"
	print "Example:"
	print "jbosstools/jbosstools-hibernate, a1f287bf825a891901b41739f6a4bbaafc70bcdd, jbosstools-4.2.1.Alpha23"
	print
	print "Useful when combined with buildinfo.json: "
	print "cat buildinfo.json | python buildinfo2tags.py -n <tagname> | python tagrepos.py <taggeruser> <secret>" 
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
		if ge.status == 422 or ge.status == 400:
			results = str(ge)
		else:
			raise

		
	print results

	

