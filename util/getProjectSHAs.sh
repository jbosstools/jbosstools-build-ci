#!/bin/bash

usage ()
{
    echo "Usage:   $0 -branch GITHUBBRANCH -jbtstream JENKINSSTREAM -jbdsstream JENKINSSTREAM -ju JENKINSUSER -jp JENKINSPWD \\"
    echo "           -gu GITHUBUSER -gp GITHUBPWD -jbt JBOSSTOOLS-PROJECT1,JBOSSTOOLS-PROJECT2,JBOSSTOOLS-PROJECT3,... \\"
    echo "           -jbds JBDEVSTUDIO-PROJECT1,JBDEVSTUDIO-PROJECT2"
    echo ""
    echo "Example: $0 -branch jbosstools-4.2.x -jbtstream 4.2.luna -jbdsstream 8.0.luna -ju nboldt -jp j_pwd \\"
    echo "           -gu nickboldt@gmail.com -gp g_pwd -jbt aerogear,discovery -jbds product"
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
jbtstream=4.2.luna # or master
jbdsstream=8.0.luna # or master 
branch=jbosstools-4.2.x # or master

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-ju') j_user="${2/;/,}"; shift 1;; # replace ; with ,
    '-jp') j_password="$2"; shift 1;;
    '-gu') g_user="$2"; shift 1;;
    '-gp') g_password="$2"; shift 1;;
    '-jbt') JBTPROJECT="$2"; shift 1;;
    '-jbds') JBDSPROJECT="$2"; shift 1;;
    '-toggleJenkinsJobs') toggleJenkinsJobs="$2"; shift 1;;
    '-branch') branch="$2"; shift 1;;
    '-jbtstream') jbtstream="$2"; shift 1;;
    '-jbdsstream') jbdsstream="$2"; shift 1;;

  esac
  shift 1
done
JBTPROJECTS=`echo ${JBTPROJECT} | sed "s#,# #g"`
JBDSPROJECTS=`echo ${JBDSPROJECT} | sed "s#,# #g"`

if [[ ! ${JBTPROJECTS} ]] && [[ ! ${JBDSPROJECTS} ]]; then
  echo "ERROR: no projects specified!"
  echo
  usage
fi

for j in ${JBTPROJECTS}; do
  echo "== ${j} =="
  githash=`wget -q https://api.github.com/repos/jbosstools/jbosstools-${j}/commits/${branch} -O - | head -2 | grep sha | \
  	sed "s#  \"sha\": \"\(.\+\)\",#\1 (${branch})#"`

  jenkinshash=`wget -q http://download.jboss.org/jbosstools/builds/staging/jbosstools-${j}_${jbtstream}/logs/GIT_REVISION.txt -O - | grep ${branch} | \
  	sed "s#\(.\+\)\@\(.\+\)#\2 (${jbtstream}, \1)#"`
  if [[ ! ${jenkinshash} ]]; then # try Jenkins XML API instead
    jenkinshash=`wget -q --no-check-certificate --user=${j_user} --password="${j_password}" -q https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/jbosstools-${j}_${jbtstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 -O - | \
    sed "s#<SHA1>\(.\+\)</SHA1>#\1#"`
  fi

  if [[ ! ${githash} ]] || [[ ! ${jenkinshash} ]]; then 
    if [[ ! ${githash} ]]; then
      echo "ERROR: branch $branch does not exist:" | egrep ERROR
      echo " >> https://github.com/jbosstools/jbosstools-${j}/tree/${branch}"
    elif [[ ! ${jenkinshash} ]]; then
      echo "ERROR: could not retrieve GIT revision from:" | egrep ERROR
      echo " >> http://download.jboss.org/jbosstools/builds/staging/jbosstools-${j}_${jbtstream}/logs/GIT_REVISION.txt (file not found?) or from "
      echo " >> https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/jbosstools-${j}_${jbtstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 (auth error?)"
    fi
    echo "Compare these URLs:"
    echo " >> https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/jbosstools-${j}_${jbtstream}/lastBuild/git/"
    echo " >> https://github.com/jbosstools/jbosstools-${j}/commits/${branch}"
  elif [[ ${githash%% *} == ${jenkinshash%% *} ]]; then # match
  	echo "PASS: ${jenkinshash}"
  else
  	echo "FAIL:" | grep FAIL
  	echo "      $jenkinshash"
  	echo "      $githash"
    # because the SHAs don't match, prompt user to enable the job so it can run
    # echo "      ... enable job jbosstools-${j}_${jbtstream} ..."
    if [[ ${branch} == "master" ]]; then view=DevStudio_Master; else view=DevStudio_${jbdsstream}; fi
    python ${toggleJenkinsJobs} --task enable --view ${view} --include jbosstools-${j}_${jbtstream} -u ${j_user} -p ${j_password}
  fi
  echo ""
done

for j in ${JBDSPROJECTS}; do
  echo "== ${j} =="
  # githash=`firefox https://github.com/jbdevstudio/jbdevstudio-product/commits/jbosstools-4.2.x` 
  # echo https://api.github.com/repos/jbdevstudio/jbdevstudio-${j}/commits/${branch}
  tmp=`mktemp`
  githash=`curl https://api.github.com/repos/jbdevstudio/jbdevstudio-${j}/commits/${branch} -u "${g_user}:${g_password}" -s -S > ${tmp} && cat ${tmp} | head -2 | grep sha | \
    sed "s#  \"sha\": \"\(.\+\)\",#\1 (${branch})#" && rm -f ${tmp}`
  jenkinshash=`wget -q --no-check-certificate http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.${j}_${jbdsstream}/logs/GIT_REVISION.txt -O - | grep ${branch} | \
    sed "s#\(.\+\)\@\(.\+\)#\2 (${jbdsstream}, \1)#"`
  if [[ ! ${jenkinshash} ]]; then # try Jenkins XML API instead
    jenkinshash=`wget -q --no-check-certificate --user=${j_user} --password="${j_password}" -q https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/devstudio.${j}_${jbtstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 -O - | \
    sed "s#<SHA1>\(.\+\)</SHA1>#\1#"`
  fi

  if [[ ! ${githash} ]] || [[ ! ${jenkinshash} ]]; then 
    if [[ ! ${githash} ]]; then
      echo "ERROR: branch $branch does not exist:" | egrep ERROR
      echo " >> https://github.com/jbdevstudio/jbdevstudio-${j}/tree/${branch}"
    elif [[ ! ${jenkinshash} ]]; then
      echo "ERROR: could not retrieve GIT revision from:" | egrep ERROR
      echo " >> http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.${j}_${jbdsstream}/logs/GIT_REVISION.txt (file not found?) or from "
      echo " >> https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/devstudio.${j}_${jbdsstream}/lastBuild/git/api/xml?xpath=//lastBuiltRevision/SHA1 (auth error?)"
    fi
    echo "Compare these URLs:"
    echo " >> https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/devstudio.${j}_${jbdsstream}/lastBuild/git/"
    echo " >> https://github.com/jbdevstudio/jbdevstudio-${j}/commits/${branch}"
  elif [[ ${githash%% *} == ${jenkinshash%% *} ]]; then # match
    echo "PASS: ${jenkinshash}"
  else
    echo "FAIL:" | grep FAIL
    echo "      $jenkinshash"
    echo "      $githash"
    # because the SHAs don't match, prompt user to enable the job so it can run
    # echo "      ... enable job devstudio.${j}_${jbdsstream} ..."
    if [[ ${branch} == "master" ]]; then view=DevStudio_Master; else view=DevStudio_${jbdsstream}; fi
    python ${toggleJenkinsJobs} --task enable --view ${view}   --include devstudio.${j}_${jbdsstream} -u ${j_user} -p ${j_password}
  fi
  echo ""
done

