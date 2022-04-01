#!/bin/bash

# This utility script will help you determine if all the latest builds have been composed in Jenkins by 
# comparing SHAs between those two jobs.
#
# Usually used when releasing new major version, along with verifying that all commits are built. see ./getProjectSHAs.sh

usage ()
{
    echo "Usage:     $0 -jbtstream JENKINSjbtstream -ju JENKINSUSER -jp JENKINSPWD \\"
    echo "             -jbt JBOSSTOOLS-PROJECT1,JBOSSTOOLS-PROJECT2,JBOSSTOOLS-PROJECT3,..."
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

#defaults
jenkinsURL="https://studio-jenkins-csb-codeready.apps.ocp-c1.prod.psi.redhat.com/"
JBTPROJECT=""
jbtstream=master 
jbtpath=photon/snapshots
launchBrowser=0; # set to 1 to automatically launch a browser if any missing builds are found
quiet="" # or "" or "-q"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    # jenkins credentials
    '-ju') j_user="$2"; shift 1;;
    '-jp') j_password="$2"; shift 1;;

    # list of projects to check
    '-jbt') JBTPROJECT="$2"; shift 1;;

    # jbtstream and path
    '-jbtstream') jbtstream="$2"; shift 1;;
    '-jbtpath') jbtpath="$2"; shift 1;; 

    # other
    '-launch') launchBrowser=1; shift 0;;
    '-q') quiet="-q"; shift 0;;

  esac
  shift 1
done
JBTPROJECTS=" "`echo ${JBTPROJECT} | sed "s#,# #g"`

if [[ ! ${JBTPROJECTS} ]]; then
  echo "ERROR: no projects specified!"
  echo ""
  echo "Use -jbt to specify which projects to check."
  echo
  usage
fi

declare -A projectMap=(
  ["aerogear-hybrid"]="aerogear"
  ["build"]="build.parent"
  ["cdi"]="javaee"
  ["cdi-extensions"]="javaee"
  ["central"]="central"
  ["central-update"]="discovery"
  ["common"]="base"
  ["cordovasim"]="aerogear"
  ["foundation"]="base"
  ["fusetools"]="fuse"
  ["fusetools-extras"]="fuse-extras"
  ["integration-tests"]="integration-tests.aggregate"
  ["jsf"]="javaee"
  ["maven"]="central"
  ["project-examples"]="central"
  ["qa"]="versionwatch"
  ["seam2"]="javaee"
  ["updatesite"]="build-sites"
  ["usage"]="base"
  ["visual-page-editor-core"]="vpe"
)

jobsToCheck=""
jenkins_prefix="${jenkinsURL}/job/Studio/job/Engineering/job/build_${jbtstream}/job/"
composite_url="https://download.jboss.org/jbosstools/${jbtpath}/updates/core/${jbtstream}/buildinfo.json"
staging_url="https://download.jboss.org/jbosstools/${jbtpath}/builds/"
checkProjects () {
    
  for j in ${JBTPROJECTS}; do
    echo "== ${j} =="
    # use buildinfo.json from latest build of project
    if [[ ${quiet} != "-q" ]]; then echo "[DEBUG] [1] ${staging_url}jbosstools-${j}_${jbtstream}/latest/all/repo/buildinfo.json"; fi
    jenkinshash=`wget -q --no-check-certificate ${staging_url}jbosstools-${j}_${jbtstream}/latest/all/repo/buildinfo.json -O - | \
      grep HEAD | grep -v currentBranch | head -1 | sed -e "s/.\+\"HEAD\" : \"\(.\+\)\",/\1/"`
    if [[ ! ${jenkinshash} ]]; then # try Jenkins XML API instead
      jenkinshash=`wget -q --no-check-certificate --user=${j_user} --password="${j_password}" ${jenkins_prefix}jbosstools-${j}_${jbtstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 -O - | \
        sed "s#<SHA1>\(.\+\)</SHA1>#\1#"`
      if [[ ${jenkinshash} ]]; then
        echo "backup: $jenkinshash from ${jenkins_prefix}jbosstools-${j}_${jbtstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1"
      fi
    fi

    # get corresponding hash from aggregate
    if [[ ${quiet} != "-q" ]]; then echo "[DEBUG] [1] ${composite_url}"; fi
    compositehash=`wget -q --no-check-certificate ${composite_url} -O - | \
      grep -A 3 "${staging_url}jbosstools-${j}_${jbtstream}/latest/all/repo" | grep HEAD | sed -e "s/.\+\"HEAD\" : \"\(.\+\)\",/\1/"`

    if [[ ! ${compositehash} ]] || [[ ! ${jenkinshash} ]]; then 
      if [[ ! ${compositehash} ]]; then
        echo "ERROR: cannot get hash from aggregate" | egrep ERROR
      elif [[ ! ${jenkinshash} ]]; then
        echo "ERROR: could not retrieve hash from:" | egrep ERROR
        echo " >> ${staging_url}jbosstools-${j}_${jbtstream}/latest/all/repo/buildinfo.json (file not found?) or from "
        echo " >> ${jenkins_prefix}jbosstools-${j}_${jbtstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 (auth error?)"
      fi
      echo "Compare these URLs:"
      echo " >> ${jenkins_prefix}jbosstools-${j}_${jbtstream}/lastBuild/git/"
      echo " >> ${composite_url}"
    elif [[ ${compositehash%% *} == ${jenkinshash%% *} ]]; then # match
        echo "PASS: ${jenkinshash}"
    else
        echo "FAIL:" | grep FAIL
        echo "      Jenkins: $jenkinshash"
        echo "      Aggregate:  $compositehash"
      # because the SHAs don't match, prompt user to enable the job so it can run
      jobsToCheck="${jobsToCheck} ${jenkins_prefix}jbosstools-${j}_${jbtstream}/build"
    fi
    echo ""
  done
}

checkProjects

if [[ ${jobsToCheck} ]]; then
  composite_job="${jenkins_prefix}jbosstools-composite-install_master/"
  echo "Composite does not contains latest commited code from repo!"
  echo "Run the following command locally to build incomplete jobs, if any."
  echo ""
  echo "google-chrome ${jobsToCheck}"
  echo ""
  echo "then run the aggregator to create a correct composite:"
  echo ""
  echo "google-chrome ${composite_job}"
  if [[ ${launchBrowser} == 1 ]]; then 
    google-chrome && google-chrome ${jobsToCheck}
    google-chrome && google-chrome ${composite_job}
  fi
  # if we had errors, make sure any jenkins wrappers fail too
  exit 1
fi
