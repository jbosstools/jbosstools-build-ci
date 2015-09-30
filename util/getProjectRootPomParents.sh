#!/bin/bash

# This utility script will help you determine if all your projects have correctly updated their root poms to use the 
# latest parent pom version. It will first pull down the latest sources from origin/master, then parse the root pom and
# compare that to the requested parent pom version. Should any mismatches be found, the offending lines are shown and 
# links to github (to review latest commits) and Jenkins (to run any missing builds) are provided.

# This script is mostly used by releng right before a code freeze to determine which projects are building w/ an outdated
# parent pom.

usage ()
{
    echo "Usage:     $0 -b GITHUBBRANCH -pv PARENTVERSION [-skipupdate] -w1 [/path/to/jbosstools-projects/parent-folder] -w2 [/path/to/jbdevstudio-projects/parent-folder]"
    echo ""
    echo "Example 1: $0 -b jbosstools-4.2.x -pv 4.2.3.CR1-SNAPSHOT -w1 /home/nboldt/42x -w2 /home/nboldt/42xx"
    echo ""
    echo "Example 2: $0 -pv 4.4.0.Alpha1-SNAPSHOT -skipupdate -w1 /home/nboldt/tru -w2 /home/nboldt/truu"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

doGitUpdate=true
parent=4.4.0.Alpha1-SNAPSHOT # or 4.4.0.Final-SNAPSHOT
branch=jbosstools-4.4.x # or master
jbtstream=4.4.neon  # or master
jbdsstream=10.0.neon # or master 

WORKSPACE1=${HOME}/tru
WORKSPACE2=${HOME}/truu

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') branch="$2"; shift 1;;
    '-pv') parent="$2"; shift 1;;
    '-skipupdate'|'-k') doGitUpdate=false; shift 0;;
    '-w1') WORKSPACE1="$2"; shift 1;;
    '-w2') WORKSPACE2="$2"; shift 1;;
  esac
  shift 1
done

if [[ $branch == "master" ]]; then
  jbtstream="master"
  jbdsstream="master"
elif [[ ${branch/4.4/} != ${branch} ]]; then
  jbtstream="4.4.neon"
  jbdsstream="10.0.neon"
fi

# TODO parameterize these?
logfile=/tmp/getProjectRootPomParents.log.txt
errfile=/tmp/getProjectRootPomParents.err.txt

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

checkProjects ${WORKSPACE1}/jbosstools- "aerogear arquillian base birt browsersim central discovery forge freemarker hibernate javaee jst livereload openshift portlet server vpe webservices" pom.xml jbosstools- jbosstools/jbosstools- "${jbtstream}"
checkProjects ${WORKSPACE1}/jbosstools- "build-sites" aggregate/pom.xml jbosstools- jbosstools/jbosstools- "${jbtstream}"
checkProjects ${WORKSPACE2}/jbdevstudio- "product" pom.xml devstudio. jbdevstudio/jbdevstudio- "${jbdsstream}"

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
