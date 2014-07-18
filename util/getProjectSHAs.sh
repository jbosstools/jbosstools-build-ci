#!/bin/bash

stream=4.2.luna
branch=4.2.0.Beta3x

for j in aerogear birt central forge server hibernate javaee jst openshift vpe webservices; do
  echo "== ${j} =="
  githash=`wget -q https://api.github.com/repos/jbosstools/jbosstools-${j}/commits/jbosstools-${branch} -O - | head -2 | grep sha | \
  	sed "s#  \"sha\": \"\(.\+\)\",#\1 (${branch})#"`
  jenkinshash=`wget -q http://download.jboss.org/jbosstools/builds/staging/jbosstools-${j}_${stream}/logs/GIT_REVISION.txt -O - | grep jbosstools | \
  	sed "s#\(.\+\)\@\(.\+\)#\2 (${stream}, \1)#"`
  if [[ ${githash%% *} == ${jenkinshash%% *} ]]; then # match
  	echo "PASS: ${jenkinshash}"
  else
  	echo "FAIL:" | grep FAIL
  	echo "      $jenkinshash"
  	echo "      $githash"
  fi
  echo ""
done

