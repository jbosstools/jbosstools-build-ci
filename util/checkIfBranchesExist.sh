#!/bin/bash

debug=0

usage ()
{
	echo "Usage: $0 -b newbranchname [project1] [project2] [project3] ..."
	echo "Example: $0 -b jbosstools-4.3.0.Alpha1x aerogear arquillian base birt browsersim central forge \\"
	echo " freemarker hibernate javaee jst livereload openshift portlet server vpe webservices discovery \\"
	echo " build build-ci build-sites download.jboss.org"
	echo "Use -s to report similar branches (eg., for 4.3.0.Beta2x, search for *Beta2x)"
	exit 1;
}

if [[ $# -lt 1 ]]; then
	usage;
fi

# projects to check if branched
#projects="base birt build build-ci build-sites central download.jboss.org forge freemarker hibernate intergration-tests javaee jst maven-plugins openshift playground portlet server target-platforms vpe webservices"

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-b') branch="$2"; shift 1;;
		'-s') checkAlternatives=1; shift;;
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

# for branch = jbosstools-4.3.0.Alpha1x  check also for a branch ending in Alpha1x
branchAlt=${branch##*.}; 
cd /tmp
cnt=0
OK=0
for d in $projects; do 
  (( cnt++ ))
	echo -n -e "[${cnt}] ${norm}$d"
	if [[ `wget https://github.com/jbosstools/jbosstools-${d}/tree/${branch} 2>&1 | egrep "ERROR 404"` ]]; then
		#echo " * Not found  checking https://api.github.com/repos/jbosstools/jbosstools-${d}/branches for branches ending in ${branchAlt} ..."
		if [[ $checkAlternatives ]]; then
			echo " ... "
			altBranches=`wget https://api.github.com/repos/jbosstools/jbosstools-${d}/branches 2>/dev/null -O - | egrep "\"name\":" | egrep "${branchAlt}"`
			if [[ $altBranches ]]; then
				echo "* Found possible alternate branches:" 
				echo "$altBranches"
			else
				debug "* Branch $branch not found; no alternates found at https://api.github.com/repos/jbosstools/jbosstools-${d}/branches:"
				debug "$altBranches"
			fi
		else
			echo -e "... ${red}NO${norm}"
		fi
	else
		echo -e " ... ${green}OK${norm}"
		(( OK++ ))
	fi
	rm -f ${branch} branches
	echo ""
done
echo -e "${norm}OK: ${green}$OK${norm} of $cnt"