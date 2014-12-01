#!/bin/bash

# This utility script will help you determine if all your projects have correctly updated their root poms to use the 
# latest parent pom version. It will first pull down the latest sources from origin/master, then parse the root pom and
# compare that to the requested parent pom version. Should any mismatches be found, the offending lines are shown and 
# links to github (to review latest commits) and Jenkins (to run any missing builds) are provided.

# This script is mostly used by releng right before a code freeze to determine which projects are building w/ an outdated
# parent pom.

usage ()
{
    echo "Usage:     $0 -b GITHUBBRANCH -pv PARENTVERSION [-skipupdate]"
    echo ""
    echo "Example 1: $0 -b jbosstools-4.2.x -pv 4.2.1.CR1-SNAPSHOT"
    echo ""
    echo "Example 2: $0 -pv 4.2.1.Final-SNAPSHOT -skipupdate"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

doGitUpdate=true
parent=4.2.1.Final-SNAPSHOT # or 4.3.0.Alpha1-SNAPSHOT
branch=jbosstools-4.2.x # or master
jbtstream=4.2.luna # or master
jbdsstream=8.0.luna # or master 

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') branch="$2"; shift 1;;
    '-pv') parent="$2"; shift 1;;
    '-skipupdate'|'-k') doGitUpdate=false; shift 0;;
  esac
  shift 1
done

if [[ $branch == "master" ]]; then
  jbtstream="master"
  jbdsstream="master"
elif [[ ${branch/4.3/} != ${branch} ]]; then
  # TODO: maybe we want to use mars + 9.0 to match changes in JBDS-3208 ?
  jbtstream="4.3.mars"
  jbdsstream="9.0.mars"
fi

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

jobsToCheck=""
reposToCheck=""
checkProjects () {
  prefix="$1"
  projects="$2"
  pomfile="$3"
  jobname_prefix="$4" # jbosstools- or devstudio.
  g_project_prefix="$5" # jbosstools/jbosstools- or jbdevstudio/jbdevstudio-
  stream="$6" # ${jbtstream} or ${jbdsstream}
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
      # https://github.com/jbosstools/jbosstools-aerogear/commits/jbosstools-4.2.x
      reposToCheck="${reposToCheck} https://github.com/${g_project_prefix}${j}/commits/${branch}"
      jobsToCheck="${jobsToCheck} https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${jobname_prefix}${j}_${stream}/build"
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

checkProjects /home/nboldt/tru/jbosstools- "aerogear arquillian base birt browsersim central discovery forge freemarker hibernate javaee jst livereload openshift portlet server vpe webservices" pom.xml jbosstools- jbosstools/jbosstools- "${jbtstream}"
checkProjects /home/nboldt/tru/jbosstools- "build-sites" aggregate/pom.xml jbosstools- jbosstools/jbosstools- "${jbtstream}"
checkProjects  /home/nboldt/truu/jbdevstudio- "product" pom.xml devstudio. jbdevstudio/jbdevstudio- "${jbdsstream}"

cat $logfile
echo ""
cat $errfile
echo ""

if [[ ${reposToCheck} ]]; then
  echo "Run the following to check Github for new commits on the ${branch} branch:"
  echo ""
  echo "firefox${reposToCheck}"
  echo ""
fi
if [[ ${jobsToCheck} ]]; then
  echo "Run the following to build incomplete jobs:"
  echo ""
  echo "firefox${jobsToCheck}"
  echo ""
fi