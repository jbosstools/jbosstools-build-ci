import pprint, requests, re, os
import sys
from xml.dom import minidom
from optparse import OptionParser
import json

pp = pprint.PrettyPrinter(indent=4)

# moar output, set = 1
debug=0

usage = "Usage: cat buildinfo.json | %prog [-n NAME] \n\n\
This script will convert a buildinfo.json to CSV list of projects, SHAs, and tags/branches."
parser = OptionParser(usage)

# required
parser.add_option("-n", dest="name", help="symbolic name to use, jbosstools-4.4.0.Alpha1")

(options, args) = parser.parse_args()

if (not options.name):
    parser.error("Must to specify ALL commandline flags; use -h for help")

j = json.load(sys.stdin) 
if j:
  
  # upstream/*/revision/knownReferences[0]/url = git repo from which build happened, eg., "git://github.com/jbosstools/jbosstools-base.git"
  # upstream/*/revision/knownReferences[0]/ref = branch from which build happened, eg., "jbosstools-4.4.0.Alpha1x" or "master"
  for entry in j['upstream']:
      if debug : print "[DEBUG] " + entry
      if type(j['upstream'][entry]) is dict :
          if debug : print "[DEBUG] " + " >> " + j['upstream'][entry]["revision"]["HEAD"]
          if debug : print "[DEBUG] " + " >> " + j['upstream'][entry]["revision"]["knownReferences"][0]["url"] # github project: "git://github.com/jbosstools/jbosstools-base.git"
          if debug : print "[DEBUG] " + " >> " + j['upstream'][entry]["revision"]["knownReferences"][0]["ref"] # branch: "jbosstools-4.4.0.Alpha1x" or "master"
          m = re.search('.+/([^/]+)/([^/]+)\.git', j['upstream'][entry]["revision"]["knownReferences"][0]["url"]) 
          if m:
            org = m.group(1)
            repo = m.group(2)
            print(org + '/' + repo + ', ' + j['upstream'][entry]['revision']['HEAD'] + ', ' + options.name)
      else :
          print >> sys.stderr, "ERROR: Missing data for " + entry + ":" + j['upstream'][entry]

else:
  print "[ERROR] Could not load json"
