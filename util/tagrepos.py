# Requires: 
# sudo pip install pygithub
# 
from github import Github, GithubException
from optparse import OptionParser
import sys, csv, os

usage = "Usage: \\ \n\
   cat buildinfo.json | python buildinfo2tags.py -n <tagname> | \\ \n\
   python tagrepos.py --ghuser <github user> --ghpwd <github pwd> \n\
\n\
NOTE: rather than passing in --ghuser and --ghpwd, you can `export userpass=ghuser:ghpwd`, \n\
and this script will read those values from the shell\n\
\n\
This script takes CSV formatted stream as input following the format: \n\
github-reponame, sha1, tag\n\
Example: jbosstools/jbosstools-hibernate, a1f287bf825a891901b41739f6a4bbaafc70bcdd, jbosstools-4.2.1.Alpha23" 
parser = OptionParser(usage)
parser.add_option("--ghuser", dest="ghuser",   help="github Username")
parser.add_option("--ghpwd",  dest="ghpwd",    help="github Password")
# NOTE: rather than passing in two flags here, you can `export userpass=ghuser:ghpwd`, 
# and this script will read those values from the shell

(options, args) = parser.parse_args()

if (not options.ghuser or not options.ghpwd) and "userpass" in os.environ:
	# check if os.environ["userpass"] is set and use that if defined
	#sys.exit("Got os.environ[userpass] = " + os.environ["userpass"])
	userpass_bits = os.environ["userpass"].split(":")
	options.ghuser = userpass_bits[0]
	options.ghpwd = userpass_bits[1]

if not options.ghuser or not options.ghpwd:
	parser.error("Must specify ALL required commandline flags")
	
repos = csv.reader(sys.stdin)
		  
g = Github(options.ghuser, options.ghpwd)

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

	

