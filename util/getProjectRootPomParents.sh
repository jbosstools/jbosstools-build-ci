#!/bin/bash

usage ()
{
    echo "Usage:     $0 -b GITHUBBRANCH -pv PARENTVERSION [-skipupdate]"
    echo ""
    echo "Example 1: $0 -b jbosstools-4.2.x -pv 4.2.0.Final-SNAPSHOT"
    echo ""
    echo "Example 2: $0 -pv 4.2.0.Final-SNAPSHOT -skipupdate"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

doGitUpdate=true
parent=4.2.0.Final-SNAPSHOT # or 4.3.0.Alpha1-SNAPSHOT
branch=jbosstools-4.2.x # or master

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') branch="$2"; shift 1;;
    '-pv') parent="$2"; shift 1;;
    '-skipupdate') doGitUpdate=false; shift 0;;
  esac
  shift 1
done

# TODO parameterize these?
logfile=/tmp/log.txt
errfile=/tmp/err.txt

gitUpdate () {
  branch=$1
  if [[ ${doGitUpdate} != "false" ]]; then 
    git stash; 
    git checkout -- .; git reset HEAD .
    git checkout -- .; git reset HEAD .
    git checkout master; git pull --rebase origin master -p; git rebase --abort 
    git pull origin
    git checkout ${branch}; git pull origin ${branch}
  fi
}

checkProjects () {
  prefix="$1"
  projects="$2"
  pomfile="$3"
  for j in ${projects} ; do
    if [[ ${doGitUpdate} != "false" ]]; then echo "== ${j} =="; fi
    pushd ${prefix}${j} >/dev/null
    gitUpdate ${branch}
    thisparent=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<"` # contains actual version
    isCorrectVersion=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<" | grep $parent` # empty string if wrong version
    #echo "thisparent = [$thisparent]"
    #echo "isCorrectVersion = [$isCorrectVersion]"
    if [[ ! $isCorrectVersion ]]; then
      echo -n "$j :: " >> $errfile
      echo $thisparent | grep version >> $errfile
    else
      echo $j :: $isCorrectVersion >> ${logfile}
    fi

    #if [[ $thisparent ]]
    popd >/dev/null
    if [[ ${doGitUpdate} != "false" ]]; then echo ""; fi
  done
}

echo "Found these root pom versions   [CORRECT]:" > ${logfile}; echo "" >> ${logfile}
echo "Found these root pom versions [INCORRECT]:" > ${errfile}; echo "" >> ${errfile}

checkProjects /home/nboldt/tru/jbosstools- "aerogear arquillian base birt browsersim central discovery forge freemarker hibernate javaee jst livereload openshift portlet server vpe webservices" pom.xml
checkProjects /home/nboldt/tru/jbosstools- "build-sites" aggregate/pom.xml
checkProjects  /home/nboldt/truu/jbdevstudio- "product" pom.xml

cat $logfile
echo ""
cat $errfile
echo ""