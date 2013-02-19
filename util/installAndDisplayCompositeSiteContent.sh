#!/bin/bash

# this Jenkins script is used to install a comma-separated list of IUs (.feature.groups) from a composite site into a pre-existing Eclipse installation, then diff 
# whether the fresh installation differs from a previously cached install manifest (list of features/plugins)
# if the install footprint is different from before, the composite site contains new content and we should fire a downstream job to produce a new aggregate site

cd ${WORKSPACE}

DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools
JBT_SITE=http://download.jboss.org/jbosstools

tmpfile=`mktemp`
manifest=composite.site.IUs.txt

# get previous manifest file, if it exists
if [[ ! `wget ${JBT_SITE}/${JBT_PATH}/${manifest} -O ${tmpfile} 2>&1 | egrep "ERROR 404" && rm -f ${tmpfile}` ]]; then
  rsync -arzq --protocol=28 ${DESTINATION}/${JBT_PATH}/${manifest} ${manifest}_PREVIOUS
else
  # remote file not exist so create empty file to diff
  touch ${manifest}_PREVIOUS 
fi

# run scripted installation via p2.director
rm -f ${WORKSPACE}/director.xml
wget ${JBT_SITE}/updates/scripted-installation/director.xml -q --no-check-certificate -N
chmod +x ${WORKSPACE}/eclipse/eclipse
${WORKSPACE}/eclipse/eclipse -consolelog -nosplash -data /tmp -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${WORKSPACE}/eclipse \
 -DsourceSites=${JBT_UPSTREAM_SITES},${JBT_SITE}/${JBT_PATH} -DIUs=${JBT_IUs} 

# collect a list of IUs in the installation - if Eclipse version or any included IUs change, this will change and cause downstream to spin. THIS IS GOOD.
find ${WORKSPACE}/eclipse/features/ ${WORKSPACE}/eclipse/plugins/ -maxdepth 1 -type f | tee ${manifest}

# update cached copy of the manifest for subsequent checks
rsync -arzq --protocol=28 ${manifest} ${DESTINATION}/${JBT_PATH}/

# echo a string to the Jenkins console log which we can then search for using Jenkins Text Finder to determine if the build should be blue (STABLE) or yellow (UNSTABLE)
if [[ `diff ${manifest} ${manifest}_PREVIOUS` ]]; then
  echo "COMPOSITE HAS CHANGED" 	# mark build stable (blue) and fire downstream job
else
  echo "COMPOSITE UNCHANGED" 	# mark build unstable (yellow) and do not fire downstream job
fi
