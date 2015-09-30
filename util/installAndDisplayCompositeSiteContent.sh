#!/bin/bash

# this Jenkins script is used to install a comma-separated list of IUs (.feature.groups) from a composite site into a pre-existing Eclipse installation, then diff 
# whether the fresh installation differs from a previously cached install manifest (list of features/plugins)
# if the install footprint is different from before, the composite site contains new content and we should fire a downstream job to produce a new aggregate site

# NOTE: if no list of IUs is provided, this script will simply call installFromTarget.sh and install all plugins and features from the list of SITES 

usage ()
{
	echo "Usage: $0 -COMP_PATH path/to/composite/ -SITES http://target-platform-site,http://composite-site/ -IUs a.feature.group,b.feature.group"
	echo "Example: $0 -COMP_PATH builds/staging/_composite_/core/trunk/ -SITES http://download.jboss.org/jbosstools/updates/kepler/,http://download.jboss.org/jbosstools/builds/staging/_composite_/core/trunk/ -IUs org.hibernate.eclipse.feature.feature.group,org.jboss.ide.eclipse.archives.feature.feature.group,..."
	echo "Usage 2: $0 -COMP_PATH path/to/composite/ -SITES http://target-platform-site,http://composite-site/ # install everything"
	echo "Example: $0 -COMP_PATH builds/staging/_composite_/core/trunk/ -SITES http://download.jboss.org/jbosstools/updates/kepler/,http://download.jboss.org/jbosstools/builds/staging/_composite_/core/trunk/"
	exit 1;
}

if [[ $# -lt 1 ]]; then
	usage;
fi

#defaults
COMP_PATH="builds/staging/_composite_/core/trunk/"
SITES="http://download.jboss.org/jbosstools/updates/kepler/,http://download.jboss.org/jbosstools/builds/staging/_composite_/core/trunk/"
IUs=""
DESTINATION="tools@filemgmt.jboss.org:/downloads_htdocs/tools"
DEST_URL="http://download.jboss.org/jbosstools"
manifest="composite.site.IUs.txt"

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-COMP_PATH') COMP_PATH="$2"; shift 1;;
		'-SITES') SITES="$2"; shift 1;;
		'-IUs') IUs="$2"; shift 1;;
		'-DESTINATION') DESTINATION="$2"; shift 1;;
		'-DEST_URL') DEST_URL="$2"; shift 1;;
	esac
	shift 1
done

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=`pwd`; fi
cd ${WORKSPACE}

# get previous manifest file, if it exists
rm -f ${WORKSPACE}/${manifest}_PREVIOUS
wget -q ${DEST_URL}/${COMP_PATH}/${manifest} -O ${WORKSPACE}/${manifest}_PREVIOUS --no-check-certificate -N
touch ${WORKSPACE}/${manifest}_PREVIOUS 

# if IUs are not defined via commandline, find all the IUs (plugins and features) on the specified SITES and install everything using installFromTarget.sh script
if [[ ! $IUs ]]; then 
	rm -fr ${WORKSPACE}/installFromTarget.sh ${WORKSPACE}/data
  # this file should already be in the workspace if you're running with Jenkins using
  # https://repository.jboss.org/nexus/content/repositories/snapshots/org/jboss/tools/releng/jbosstools-releng-publish/
  # but just in case fall back to github
  if [[ ! -f ${WORKSPACE}/sources/util/installFromTarget.sh ]]; then
		wget https://raw.github.com/jbosstools/jbosstools-build-ci/jbosstools-4.3.x/util/installFromTarget.sh -q --no-check-certificate -N
  else
    cp -f ${WORKSPACE}/sources/util/installFromTarget.sh ${WORKSPACE}/installFromTarget.sh
	fi
	chmod +x ${WORKSPACE}/installFromTarget.sh ${WORKSPACE}/eclipse/eclipse
	${WORKSPACE}/installFromTarget.sh -ECLIPSE ${WORKSPACE}/eclipse/ -INSTALL_PLAN ${SITES} -WORKSPACE ${WORKSPACE}/data
	res=$?
else
	# run scripted installation via p2.director
	rm -fr ${WORKSPACE}/director.xml ${WORKSPACE}/data
	wget ${DEST_URL}/updates/scripted-install/director.xml -q --no-check-certificate -N
	chmod +x ${WORKSPACE}/eclipse/eclipse
	${WORKSPACE}/eclipse/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml \
	-DtargetDir=${WORKSPACE}/eclipse -DsourceSites=${SITES} -Dinstall=${IUs}
	res=$?
fi

if [[ "${res}" -ne "0" ]]; then
	echo "Installation from composite failed with return code $res"
	exit $res
fi

# collect a list of IUs in the installation - if Eclipse version or any included IUs change, this will change and cause downstream to spin. THIS IS GOOD.
pushd ${WORKSPACE}/eclipse/ >/dev/null
find features/ plugins/ -maxdepth 1 | sort | tee ${WORKSPACE}/${manifest}
popd >/dev/null

# update cached copy of the manifest for subsequent checks
rsync -arzq --protocol=28 ${WORKSPACE}/${manifest} ${DESTINATION}/${COMP_PATH}/

# echo a string to the Jenkins console log which we can then search for using Jenkins Text Finder to determine if the build should be blue (STABLE) or yellow (UNSTABLE)
diff="`diff -U 0 ${WORKSPACE}/${manifest}_PREVIOUS ${WORKSPACE}/${manifest} 2>&1`"
if [[ ${diff} ]]; then
  echo "COMPOSITE HAS CHANGED" 	# mark build stable (blue) and fire downstream job
  echo "====================="
  echo "${diff}"
  echo "====================="
else
  echo "COMPOSITE UNCHANGED" 	# mark build unstable (yellow) and do not fire downstream job
fi
