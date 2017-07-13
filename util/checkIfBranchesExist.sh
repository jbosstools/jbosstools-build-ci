#!/bin/bash

debug=0

usage ()
{
  echo "Usage: $0 -b newbranchname [project1] [project2] [project3] ..."
  echo "Example1: $0 -b jbosstools-4.4.0.x aerogear arquillian base browsersim build build-ci build-sites \\"
  echo " central devdoc discovery download.jboss.org forge fuse fuse-extras hibernate integration-tests javaee jst \\"
  echo " livereload maven-plugins openshift server versionwatch vpe webservices" # freemarker portlet playground
  echo "Use -s to report similar branches (eg., for 4.4.x, search for *Alpha1x)"
  echo "Example2: $0 -b jbosstools-4.4.0.x -g jbdevstudio/jbdevstudio- devdoc product website"
  exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

# projects to check if branched
# JBIDE-24484 remove freemarker, portlet, playground
# projects="aerogear arquillian base browsersim build build-ci build-sites central devdoc discovery download.jboss.org forge fuse fuse-extras hibernate integration-tests javaee jst livereload maven-plugins openshift server versionwatch vpe webservices"

quiet=0
checkAlternatives=0
g_project_prefix=jbosstools/jbosstools- # or jbdevstudio/jbdevstudio-

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') branch="$2"; shift 1;;
    '-q') quiet=1; shift 0;;
    '-s') checkAlternatives=1; shift 0;;
    '-g') g_project_prefix="$2"; shift 1;;
    *) projects="$projects $1";;
  esac
  shift 1
done

if [[ ! $branch ]]; then 
  echo "branch is not set!"; exit 1
fi
if [[ ! $projects ]]; then 
  echo "no project(s) selected!"; exit 1
fi

debug ()
{
  if [[ $debug -gt 0 ]]; then echo "$1"; fi
}

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"

# for branch = jbosstools-4.4.x  check also for a branch ending in Alpha1x
branchAlt=${branch##*.}; 
cd /tmp
cnt=0
OK=0
notOK=0
for d in $projects; do 
    let cnt+=1
  if [[ $quiet == 0 ]]; then echo -n -e "[${cnt}] ${norm}$d"; fi
  if [[ `wget https://github.com/${g_project_prefix}${d}/tree/${branch} 2>&1 | egrep "ERROR 404"` ]]; then
    #echo " * Not found  checking https://api.github.com/repos/${g_project_prefix}${d}/branches for branches ending in ${branchAlt} ..."
    if [[ $quiet == 1 ]]; then echo -n -e "[${cnt}] ${norm}$d"; fi
    echo -e " ... ${red}NO${norm}"
    let notOK+=1
    if [[ $checkAlternatives == 1 ]]; then
      altBranches=`wget https://api.github.com/repos/${g_project_prefix}${d}/branches 2>/dev/null -O - | egrep "\"name\":" | egrep "${branchAlt}"`
      if [[ $altBranches ]]; then
        echo "* Found possible alternate branches:" 
        echo "$altBranches"
      else
        debug "* Branch $branch not found; no alternates found at https://api.github.com/repos/${g_project_prefix}${d}/branches:"
        debug "$altBranches"
      fi
      if [[ $quiet == 0 ]]; then echo ""; fi 
    fi
  else
    if [[ $quiet == 0 ]]; then echo -e " ... ${green}OK${norm}"; fi
    let OK+=1
  fi
  rm -f ${branch} branches
done
echo -e "${norm}OK: ${green}$OK${norm} of $cnt"

exit ${notOK}
