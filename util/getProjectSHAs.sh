#!/bin/bash

# This utility script will help you determine if all the latest github commits have been built in Jenkins by 
# comparing SHAs between those two systems. Should the script determine that there are commits in Github which have
# not yet been built in Jenkins, the script will dump URLs for invoking those missing builds without having to do 
#much more that selecting text and pasting it into a terminal to launch Firefox.
#
# See examples below for how to look for unbuilt commits, either based on a JIRA query or a list of projects.

usage ()
{
    echo "Usage:     $0 -branch GITHUBBRANCH -jbtstream JENKINSSTREAM -jbdsstream JENKINSSTREAM -ju JENKINSUSER -jp JENKINSPWD \\"
    echo "             -gu GITHUBUSER -gp GITHUBPWD -jbt JBOSSTOOLS-PROJECT1,JBOSSTOOLS-PROJECT2,JBOSSTOOLS-PROJECT3,... \\"
    echo "             -jbds JBDEVSTUDIO-PROJECT1,JBDEVSTUDIO-PROJECT2 \\"
    echo "             -iu issues.jboss.org_USER -ip issues.jboss.org_PWD -jbtm 4.2.0.MILESTONE -jbdsm 8.0.0.MILESTONE -respin a|b|c..."
    echo ""
    # for the milestone, find the related JIRAs and get the associated projects
    echo "Example 1: $0 -branch jbosstools-4.4.0.Alpha1x -jbtstream 4.4.neon -jbdsstream 10.0.neon -ju nboldt -jp j_pwd \\"
    echo "             -gu nickboldt@gmail.com -gp g_pwd -iu nickboldt -ip i_pwd -jbtm 4.4.0.Alpha1 -jbdsm 10.0.0.Alpha1 -respin a"
    echo ""
    # for a list of projects, find any unbuilt commits
    echo "Example 2: $0 -branch jbosstools-4.4.0.Alpha1x -jbtstream 4.4.neon -jbdsstream 10.0.neon -ju nboldt -jp j_pwd \\"
    echo "            -gu nickboldt@gmail.com -gp g_pwd -jbds product -jbt aerogear,arquillian,base,birt,browsersim,central,discovery,\\"
    echo "forge,freemarker,hibernate,javaee,jst,livereload,openshift,portlet,server,vpe,webservices"
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

#defaults
toggleJenkinsJobs=~/truu/jbdevstudio-ci/bin/toggleJenkinsJobs.py
#JBTPROJECT="aerogear,arquillian,base,birt,browsersim,central,discovery,forge,freemarker,hibernate,javaee,jst,livereload,openshift,portlet,server,vpe,webservices"
JBTPROJECT=""
#JBDSPROJECT="product"
JBDSPROJECT=""
jbtstream=4.4.neon # or master
jbdsstream=10.0.neon # or master 
branch=jbosstools-4.4.0.Alpha1x # or master
jbtpath=neon/snapshots/builds # or builds/staging, from JBDS 8 and before
jbdspath=10.0/snapshots/builds

while [[ "$#" -gt 0 ]]; do
  case $1 in
    # github credentials
    '-gu') g_user="$2"; shift 1;;
    '-gp') g_password="$2"; shift 1;;

    # issues.jboss.org credentials
    '-iu') i_user="$2"; shift 1;;
    '-ip') i_password="$2"; shift 1;;

    # jenkins credentials
    '-ju') j_user="$2"; shift 1;;
    '-jp') j_password="$2"; shift 1;;

    # list of projects to check
    '-jbt') JBTPROJECT="$2"; shift 1;;
    '-jbds') JBDSPROJECT="$2"; shift 1;;

    # script to use to perform Jenkins job enablement
    '-toggleJenkinsJobs') toggleJenkinsJobs="$2"; shift 1;;

    # branch and stream
    '-branch') branch="$2"; shift 1;;
    '-jbtstream') jbtstream="$2"; shift 1;;
    '-jbdsstream') jbdsstream="$2"; shift 1;;

    # milestone and respin-*
    '-jbtm') jbtm="$2"; shift 1;;
    '-jbdsm') jbdsm="$2"; shift 1;;
    '-respin') respin="$2"; shift 1;;
  esac
  shift 1
done
JBTPROJECTS=" "`echo ${JBTPROJECT} | sed "s#,# #g"`
JBDSPROJECTS=" "`echo ${JBDSPROJECT} | sed "s#,# #g"`

if [[ ! ${JBTPROJECTS} ]] && [[ ! ${JBDSPROJECTS} ]] && [[ ! ${jbtm} ]] && [[ ! ${jbdsm} ]]; then
  echo "ERROR: no projects specified!"
  echo ""
  echo "Use -jbt or -jbds to specify which projects to check, or"
  echo "use -milestone to list milestone(s) to query for recently resolved issues."
  echo
  usage
fi

# for the milestone, find the related JIRAs and get the associated projects
if [[ ${jbtm} ]]; then
  echo "Search JIRA for milestone(s) = $jbtm (respin = $respin)..."
  # for CR2
  # ((project = "JBIDE" and fixVersion in ("4.2.0.CR2"))) and resolution != "Unresolved"
  # for CR2a
  # ((project = "JBIDE" and fixVersion in ("4.2.0.CR2"))) and resolution != "Unresolved" and labels in ("respin-a")
  # for GA/Final
  # ((project = "JBIDE" and fixVersion in ("4.2.0.Final"))) and resolution != "Unresolved"
  query="%28" # (
  if [[ ${jbtm} ]]; then 
    query=${query}"%20%28project%20in%20%28%22JBIDE%22,%22TOOLSDOC%22%29%20and%20fixVersion%20in%20%28%22${jbtm}%22%29%29"
  fi
  query=${query}"%20%29%20and%20resolution%20!%3D%20%22Unresolved%22"
  if [[ ${respin} ]]; then query=${query}"%20and%20labels%20in%20%28%22respin-${respin}%22%29"; fi
  # echo $query

  # https://issues.jboss.org/rest/api/2/search?jql=%28%28project%20%3D%20%22JBIDE%22%20and%20fixVersion%20in%20%28%224.2.0.CR2%22%2C%20%224.2.0.Final%22%29%29%20or%20%28project%20%3D%20%22JBDS%22%20and%20fixversion%20in%20%28%228.0.0.CR2%22%2C%228.0.0.GA%22%29%29%29%20and%20resolution%20!%3D%20%22Unresolved%22%20and%20labels%20in%20%28%22respin-a%22%29&fields=key,components
  wget --user=${i_user} --password="${i_password}" --no-check-certificate "https://issues.jboss.org/rest/api/2/search?fields=key,components&jql=${query}" -q -O /tmp/json.txt

  json=`cat /tmp/json.txt`
  cp /tmp/json.txt /tmp/json-jbt.txt
  rm -f /tmp/json.txt
  components=""
  while [[ $name != "," ]]; do
    name=${json#*\"name\":\"} # trim off everything up to the first "name":"
    name=${name%%\"*} # trim off everything after the quote
    json=${json#*\"name\":\"${name}\"}
    #echo $name
    # echo $projects :: $name
    if [[ ${components##* ${name}*} == $components ]] && [[ $name != "," ]]; then components="${components} ${name}"; fi
  done
  #echo "Got these issues.jboss.org components:${components}"

  if [[ $components ]]; then
    projects=""
    # define mapping between JIRA components and jenkins project names
    # if not listed then mapping between component and project are 1:1,eg., for forge, server, livereload, openshift, webservices, hibernate, birt, freemarker, browsersim, discovery
    declare -A projectMap=( 
      ["qa"]="versionwatch"
      ["aerogear-hybrid"]="aerogear"
      ["cordovasim"]="aerogear"
      ["arquillian"]="arquillian" 
      ["usage"]="base"
      ["updatesite"]="build-sites"
      ["central"]="central"
      ["maven"]="central"
      ["project-examples"]="central"
      ["common/jst/core"]="jst"
      ["jsp/jsf/xml/html-source-editing"]="jst"
      ["jsf"]="javaee"
      ["seam2"]="javaee"
      ["cdi"]="javaee"
      ["cdi-extensions"]="javaee"
      ["portal-gatein"]="portlet"
      ["visual-page-editor-core"]="vpe"
      ["build"]="build.parent"
      ["easymport"]="playground"
      ["integration-tests"]="integration-tests.aggregate"
    )

    # load list of projects from component::project mapping, adding only if unique
    for c in $components; do
      m=${projectMap[$c]}
      if [[ "${m}" ]] && [[ ${m##*jbdevstudio-*} == "" ]]; then # jbds project, not jbt
        if [[ ${JBDSPROJECTS##* ${m}*} == $JBDSPROJECTS ]]; then 
          JBDSPROJECTS="${JBDSPROJECTS} ${c}"
        fi
      elif [[ "${m}" ]] && [[ ${JBTPROJECTS##* ${m}*} == $JBTPROJECTS ]] && [[ ${projects##* ${m}*} == $projects ]]; then 
        projects="${projects} ${m}"
      elif [[ ! "${m}" ]] && [[ ${JBTPROJECTS##* ${c}*} == $JBTPROJECTS ]] && [[ ${projects##* ${m}*} == $projects ]]; then
        projects="${projects} ${c}"
      fi
    done
  fi
  if [[ $projects ]]; then
    echo "Got these Jenkins and Github projects:${projects}"
    JBTPROJECTS="${JBTPROJECTS} ${projects}"
  fi
fi

# for the milestone, find the related JIRAs and get the associated projects
if [[ ${jbdsm} ]]; then
  echo "Search JIRA for milestone(s) = $jbdsm (respin = $respin)..."
  # for CR2
  # ((project = "JBDS" and fixversion in ("8.0.0.CR2"))) and resolution != "Unresolved"
  # for CR2a
  # ((project = "JBDS" and fixversion in ("8.0.0.CR2"))) and resolution != "Unresolved" and labels in ("respin-a")
  # for GA/Final
  # ((project = "JBDS" and fixversion in ("8.0.0.GA"))) and resolution != "Unresolved"
  query="%28" # (
  if [[ ${jbdsm} ]]; then query=${query}"%20%28project%20%3D%20%22JBDS%22%20and%20fixVersion%20in%20%28%22${jbdsm}%22%29%29"; fi
  query=${query}"%20%29%20and%20resolution%20!%3D%20%22Unresolved%22"
  if [[ ${respin} ]]; then query=${query}"%20and%20labels%20in%20%28%22respin-${respin}%22%29"; fi
  # echo $query

  # https://issues.jboss.org/rest/api/2/search?jql=%28%28project%20%3D%20%22JBIDE%22%20and%20fixVersion%20in%20%28%224.2.0.CR2%22%2C%20%224.2.0.Final%22%29%29%20or%20%28project%20%3D%20%22JBDS%22%20and%20fixversion%20in%20%28%228.0.0.CR2%22%2C%228.0.0.GA%22%29%29%29%20and%20resolution%20!%3D%20%22Unresolved%22%20and%20labels%20in%20%28%22respin-a%22%29&fields=key,components
  wget --user=${i_user} --password="${i_password}" --no-check-certificate "https://issues.jboss.org/rest/api/2/search?fields=key,components&jql=${query}" -q -O /tmp/json.txt

  json=`cat /tmp/json.txt`
  rm -f /tmp/json.txt
  components=""
  while [[ $name != "," ]]; do
    name=${json#*\"name\":\"} # trim off everything up to the first "name":"
    name=${name%%\"*} # trim off everything after the quote
    json=${json#*\"name\":\"${name}\"}
    #echo $name
    # echo $projects :: $name
    if [[ ${components##* ${name}*} == $components ]] && [[ $name != "," ]]; then components="${components} ${name}"; fi
  done
  #echo "Got these issues.jboss.org components:${components}"

  projects=""
  if [[ $components ]]; then
    # define mapping between JIRA components and jenkins project names
    # if not listed then mapping between component and project are 1:1,eg., for forge, server, livereload, openshift, webservices, hibernate, birt, freemarker, browsersim, discovery
    declare -A projectMap=( 
      ["qa"]="qa"
      ["updatesite"]="product"
      ["target-platform"]="product"
    )

    # load list of projects from component::project mapping, adding only if unique
    for c in $components; do
      m=${projectMap[$c]}
      if [[ "${m}" ]] && [[ ${JBDSPROJECTS##* ${m}*} == $JBDSPROJECTS ]] && [[ ${projects##* ${m}*} == $projects ]]; then 
        projects="${projects} ${m}"
      elif [[ ! "${m}" ]] && [[ ${JBDSPROJECTS##* ${c}*} == $JBDSPROJECTS ]] && [[ ${projects##* ${c}*} == $projects ]]; then
        projects="${projects} ${c}"
      fi
    done
  fi

  if [[ $projects ]] || [[ $JBDSPROJECTS ]]; then
    echo "Got these Jenkins and Github projects:${JBDSPROJECTS}"
    JBDSPROJECTS="${JBDSPROJECTS} ${projects}"
  fi
fi

jobsToCheck=""
checkProjects () {
  jenkins_prefix="https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/"
  PROJECTS="$1" # ${JBTPROJECTS} or ${JBDSPROJECTS}
  g_project_prefix="$2" # jbosstools/jbosstools- or jbdevstudio/jbdevstudio-
  staging_url="$3" # http://download.jboss.org/jbosstools/${jbtpath}/ or http://www.qa.jboss.com/binaries/RHDS/${jbdspath}/
  jobname_prefix="$4" # jbosstools- or devstudio.
  stream="$5" # ${jbtstream} or ${jbdsstream}

  for j in ${PROJECTS}; do
    # in most cases the github project and jobname are the same, but for jbosstools-build, the jobname is jbosstools-build.parent
    if [[ ${j} == "build.parent" ]]; then 
      g_project="build"
      echo "== ${g_project} (${j}) =="
    else
      g_project="${j}"
      echo "== ${g_project} =="
    fi

    # githash=`firefox https://github.com/jbdevstudio/jbdevstudio-product/commits/jbosstools-4.4.0.Alpha1x` 
    # echo https://api.github.com/repos/jbdevstudio/jbdevstudio-${j}/commits/${branch}
    tmp=`mktemp`
    githash=`curl https://api.github.com/repos/${g_project_prefix}${g_project}/commits/${branch} -u "${g_user}:${g_password}" -s -S > ${tmp} && cat ${tmp} | head -2 | grep sha | \
    sed "s#  \"sha\": \"\(.\+\)\",#\1 (${branch})#" && rm -f ${tmp}`
    # alternate approach to curl, using wget 
    #githash=`wget -q --no-check-certificate https://api.github.com/repos/${g_project_prefix}${g_project}/commits/${branch} -O - | head -2 | grep sha | \
    #	sed "s#  \"sha\": \"\(.\+\)\",#\1 (${branch})#"`

    # new for JBDS 9 (used to pull logs/GIT_REVISION.txt) - use buildinfo.json
    jenkinshash=`wget -q --no-check-certificate ${staging_url}${jobname_prefix}${j}_${stream}/latest/all/repo/buildinfo.json -O - | \
      grep HEAD | grep -v currentBranch | head -1 | sed -e "s/.\+\"HEAD\" : \"\(.\+\)\",/\1/"`
    if [[ ! ${jenkinshash} ]]; then # try alternate URL
      jenkinshash=`wget -q --no-check-certificate ${staging_url}${jobname_prefix}${j}.aggregate_${stream}/latest/all/repo/buildinfo.json -O - | \
        grep HEAD | grep -v currentBranch | head -1 | sed -e "s/.\+\"HEAD\" : \"\(.\+\)\",/\1/"`
    fi
    if [[ ! ${jenkinshash} ]]; then # try alternate URL
      jenkinshash=`wget -q --no-check-certificate ${staging_url}${jobname_prefix}${j}.central_${stream}/latest/all/repo/buildinfo.json -O - | \
        grep HEAD | grep -v currentBranch | head -1 | sed -e "s/.\+\"HEAD\" : \"\(.\+\)\",/\1/"`
    fi
    if [[ ! ${jenkinshash} ]]; then # try Jenkins XML API instead
      jenkinshash=`wget -q --no-check-certificate --user=${j_user} --password="${j_password}" ${jenkins_prefix}${jobname_prefix}${j}_${stream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 -O - | \
        sed "s#<SHA1>\(.\+\)</SHA1>#\1#"`
      echo "backup: $jenkinshash from ${jenkins_prefix}${jobname_prefix}${j}_${stream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1"
    fi

    if [[ ! ${githash} ]] || [[ ! ${jenkinshash} ]]; then 
      if [[ ! ${githash} ]]; then
        echo "ERROR: branch $branch does not exist:" | egrep ERROR
        echo " >> https://github.com/${g_project_prefix}${j}/tree/${branch}"
      elif [[ ! ${jenkinshash} ]]; then
        echo "ERROR: could not retrieve GIT revision from:" | egrep ERROR
        echo " >> ${staging_url}${jobname_prefix}${j}_${stream}/latest/all/repo/buildinfo.json (file not found?) or from "
        echo " >> ${jenkins_prefix}${jobname_prefix}${j}_${stream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 (auth error?)"
      fi
      echo "Compare these URLs:"
      echo " >> ${jenkins_prefix}${jobname_prefix}${j}_${stream}/lastBuild/git/"
      echo " >> https://github.com/${g_project_prefix}${j}/commits/${branch}"
    elif [[ ${githash%% *} == ${jenkinshash%% *} ]]; then # match
    	echo "PASS: ${jenkinshash}"
    else
    	echo "FAIL:" | grep FAIL
    	echo "      Jenkins: $jenkinshash"
    	echo "      Github:  $githash"
      # because the SHAs don't match, prompt user to enable the job so it can run
      # echo "      ... enable job ${jobname_prefix}${j}_${stream} ..."
      if [[ ${branch} == "master" ]]; then view=DevStudio_Master; else view=DevStudio_${jbdsstream}; fi
      #echo "python ${toggleJenkinsJobs} --task enable --view ${view} --include ${jobname_prefix}${j}_${stream} -u ${j_user} -p [PASSWORD]"
      #python ${toggleJenkinsJobs} --task enable --view ${view} --include ${jobname_prefix}${j}_${stream} -u ${j_user} -p "${j_password}"
      jobsToCheck="${jobsToCheck} ${jenkins_prefix}${jobname_prefix}${j}_${stream}/build"
    fi
    echo ""
  done
}

checkProjects "${JBTPROJECTS}"  jbosstools/jbosstools-   http://download.jboss.org/jbosstools/${jbtpath}/ jbosstools- "${jbtstream}"
checkProjects "${JBDSPROJECTS}" jbdevstudio/jbdevstudio- http://www.qa.jboss.com/binaries/RHDS/${jbdspath}/ devstudio. "${jbdsstream}"

if [[ ${jobsToCheck} ]]; then
  echo "Run the following to build incomplete jobs:"
  echo ""
  echo "firefox${jobsToCheck}"
fi