#!/bin/bash

debug=0

usage ()
{
	echo "Usage: $0 -b newbranchname [project1] [project2] [project3] ..."
	echo "Example: $0 -b jbosstools-4.4.0.Alpha1x aerogear arquillian base birt browsersim build build-ci build-sites \\"
	echo " central devdoc discovery download.jboss.org forge freemarker hibernate integration-tests javaee jst \\"
	echo " livereload maven-plugins openshift playground server versionwatch vpe webservices" # portlet
	echo "Use -s to report similar branches (eg., for 4.4.0.Alpha1x, search for *Alpha1x)"
	exit 1;
}

if [[ $# -lt 1 ]]; then
	usage;
fi

# projects to check if branched
# projects="aerogear arquillian base birt browsersim build build-ci build-sites central devdoc discovery download.jboss.org forge freemarker hibernate integration-tests javaee jst livereload maven-plugins openshift playground server versionwatch vpe webservices"

quiet=0
checkAlternatives=0

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-b') branch="$2"; shift 1;;
		'-q') quiet=1; shift 0;;
		'-s') checkAlternatives=1; shift 0;;
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

# for branch = jbosstools-4.4.0.Alpha1x  check also for a branch ending in Alpha1x
branchAlt=${branch##*.}; 
cd /tmp
cnt=0
OK=0
for d in $projects; do 
  (( cnt++ ))
	if [[ $quiet == 0 ]]; then echo -n -e "[${cnt}] ${norm}$d"; fi
	if [[ `wget https://github.com/jbosstools/jbosstools-${d}/tree/${branch} 2>&1 | egrep "ERROR 404"` ]]; then
		#echo " * Not found  checking https://api.github.com/repos/jbosstools/jbosstools-${d}/branches for branches ending in ${branchAlt} ..."
		if [[ $quiet == 1 ]]; then echo -n -e "[${cnt}] ${norm}$d"; fi
		echo -e " ... ${red}NO${norm}"
		if [[ $checkAlternatives == 1 ]]; then
			altBranches=`wget https://api.github.com/repos/jbosstools/jbosstools-${d}/branches 2>/dev/null -O - | egrep "\"name\":" | egrep "${branchAlt}"`
			if [[ $altBranches ]]; then
				echo "* Found possible alternate branches:" 
				echo "$altBranches"
			else
				debug "* Branch $branch not found; no alternates found at https://api.github.com/repos/jbosstools/jbosstools-${d}/branches:"
				debug "$altBranches"
			fi
			if [[ $quiet == 0 ]]; then echo ""; fi 
		fi
	else
		if [[ $quiet == 0 ]]; then echo -e " ... ${green}OK${norm}"; fi
		(( OK++ ))
	fi
	rm -f ${branch} branches
done
echo -e "${norm}OK: ${green}$OK${norm} of $cnt"