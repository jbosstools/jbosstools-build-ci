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
    echo "Example 2: $0 -pv 4.4.0.Final-SNAPSHOT -skipupdate -w1 /home/nboldt/tru -w2 /home/nboldt/truu"
    echo ""
    echo "Example 3: $0 -b master -pv 4.4.1.Alpah1-SNAPSHOT -w1 \${WORKSPACE}/jbosstools.github -w2 \${WORKSPACE}/jbdevstudio.github"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

doGitUpdate=true
version_parent=4.4.1.Alpha1-SNAPSHOT # or 4.4.0.Final-SNAPSHOT
github_branch=jbosstools-4.4.x # or master

WORKSPACE1=${HOME}/tru
WORKSPACE2=${HOME}/truu
PROJECTS1="aerogear arquillian base browsersim central discovery forge freemarker hibernate javaee jst livereload openshift server vpe webservices"
PROJECTS2="build-sites"
PROJECTS3="product"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') github_branch="$2"; shift 1;;
    '-pv') version_parent="$2"; shift 1;;
    '-skipupdate'|'-k') doGitUpdate=false; shift 0;;
    '-w1') WORKSPACE1="$2"; shift 1;;
    '-w2') WORKSPACE2="$2"; shift 1;;
    '-p1') PROJECTS1="$2"; shift 1;; # jbosstools-* projects
    '-p2') PROJECTS2="$2"; shift 1;; # jbosstools-build-* projects
    '-p3') PROJECTS3="$2"; shift 1;; # jbdevstudio-* projects
    '-sj') stream_jbt="$2"; shift 1;;
    '-sd') stream_ds="$2"; shift 1;;
  esac
  shift 1
done

# backups if not set above
if [[ ! ${stream_jbt} ]] || [[ ! ${stream_ds} ]]; then 
  if [[ $github_branch == "master" ]]; then
    stream_jbt="master"
    stream_ds="master"
  elif [[ ${github_branch/4.4/} != ${github_branch} ]]; then
    stream_jbt="4.4.neon"
    stream_ds="10.0.neon"
  fi
fi

# TODO parameterize these?
logfile=/tmp/getProjectRootPomParents.log.txt
errfile=/tmp/getProjectRootPomParents.err.txt

gitUpdate () {
  github_branch=$1
  if [[ ${doGitUpdate} != "false" ]]; then
    git stash; 
    git checkout -- .; git reset HEAD .
    git checkout -- .; git reset HEAD .
    git checkout master; git pull --rebase origin master -p; git rebase --abort 
    git pull origin
    git checkout ${github_branch}; git pull origin ${github_branch}
  fi
}

jobsToCheck=""
reposToCheck=""
checkProjects () {
  workspace="${1}"
  prefix="$2"
  projects="$3"
  pomfile="$4"
  jobname_prefix="$5" # jbosstools- or devstudio.
  g_project_prefix="$6" # jbosstools/jbosstools- or jbdevstudio/jbdevstudio-
  stream="$7" # ${stream_jbt} or ${stream_ds}
  for j in ${projects} ; do
    if [[ ! -d ${workspace}/${prefix}${j} ]]; then
      # fetch the project to the workspace as it's not already here!
      mkdir -p ${workspace} && pushd ${workspace} >/dev/null && git clone -q https://github.com/${g_project_prefix}${j}.git && popd >/dev/null
    fi
    if [[ ${doGitUpdate} != "false" ]]; then echo "== ${j} =="; fi
    pushd ${workspace}/${prefix}${j} >/dev/null
    gitUpdate ${github_branch}
    thisparent=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<"` # contains actual version
    isCorrectVersion=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<" | grep ${version_parent}` # empty string if wrong version
    #echo "thisparent = [$thisparent]"
    #echo "isCorrectVersion = [$isCorrectVersion]"
    if [[ ! $isCorrectVersion ]]; then
      echo -n "$j :: " >> $errfile
      # https://github.com/jbosstools/jbosstools-aerogear/commits/jbosstools-4.2.x
      reposToCheck="${reposToCheck} https://github.com/${g_project_prefix}${j}/commits/${github_branch}"
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


mkdir -p ${WORKSPACE1} ${WORKSPACE2}
checkProjects ${WORKSPACE1} jbosstools-  "${PROJECTS1}" pom.xml           jbosstools- jbosstools/jbosstools-   "${stream_jbt}"
checkProjects ${WORKSPACE1} jbosstools-  "${PROJECTS2}" aggregate/pom.xml jbosstools- jbosstools/jbosstools-   "${stream_jbt}"
checkProjects ${WORKSPACE2} jbdevstudio- "${PROJECTS3}" pom.xml           devstudio.  jbdevstudio/jbdevstudio- "${stream_ds}"

cat $logfile
echo ""

if [[ ${reposToCheck} ]]; then
  echo "Run the following to check Github for new commits on the ${github_branch} github_branch:"
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

if [[ $(cat $errfile) ]]; then 
  echo "Found these root pom versions [INCORRECT]:"; echo ""
  cat $errfile
  echo ""
  exit 1
fi