#!/bin/bash

# this Jenkins script is used to install a comma-separated list of IUs (.feature.groups) from a composite site into a pre-existing Eclipse installation, then diff 
# whether the fresh installation differs from a previously cached install manifest (list of features/plugins)
# if the install footprint is different from before, the composite site contains new content and we should fire a downstream job to produce a new aggregate site

usage ()
{
	echo "Usage: $0 -ECLIPSE /path/to/eclipse-install/ -INSTALL_PLAN http://JBT-or-JBDS-update-site;http://JBT-or-JBDS/composite/directory.xml "
  echo "Example: $0 -ECLIPSE ${WORKSPACE}/eclipse/ -INSTALL_PLAN http://download.jboss.org/jbosstools/updates/nightly/core/master/,http://download.jboss.org/jbosstools/discovery/nightly/core/master/jbosstools-directory.xml"
  echo "Example: $0 -ECLIPSE ${HOME}/eclipse/44clean/eclipse/ -INSTALL_PLAN http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.product_master/all/repo/,http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/master/devstudio-directory.xml"
	exit 1;
}

if [[ $# -lt 1 ]]; then
	usage;
fi

#defaults
DIRECTORXML="http://download.jboss.org/jbosstools/updates/scripted-installation/director.xml"

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-INSTALL_PLAN') INSTALL_PLAN="${2/;/,}"; shift 1;; # replace ; with ,
    '-ECLIPSE') ECLIPSE="$2"; shift 1;;
    '-WORKSPACE') WORKSPACE="$2"; shift 1;;
	esac
	shift 1
done

if [[ ! $INSTALL_PLAN ]]; then usage; fi

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=`pwd`; fi
mkdir -p ${WORKSPACE}; cd ${WORKSPACE}

# default path to Eclipse install for Jenkins 
if [[ ! ${ECLIPSE} ]] && [[ -d ${WORKSPACE}/eclipse/ ]] && [[ -x ${WORKSPACE}/eclipse/eclipse ]]; then ECLIPSE=${WORKSPACE}/eclipse; fi 
chmod +x ${ECLIPSE}/eclipse

# get director.xml script
wget ${DIRECTORXML} -q --no-check-certificate -N -O ${WORKSPACE}/director.xml

# wipe existing Eclipse workspace
rm -fr ${WORKSPACE}/data; mkdir -p ${WORKSPACE}/data

# get list of sites from which to resolve IUs (based on list in INSTALL_PLAN);  and trim /*-directory.xml at the end
SITES=${INSTALL_PLAN%/*}/

# get a list of IUs to install from the JBT or JBDS update site (based on category.xml)
BASE_URL=${SITES%,*}
wget ${BASE_URL}/category.xml -q --no-check-certificate -N -O category.xml

# parse the list of features from the category.xml
# include source features too?
FEATURES=`cat category.xml | egrep -v "<--|-->" |grep "<feature" | sed "s#.\+id=\"\([^\"]\+\)\".\+#\1#" | sort | uniq`
BASE_IUs=""; for f in $FEATURES; do BASE_IUs="${BASE_IUs},${f}.feature.group"; done; BASE_IUs=${BASE_IUs:1}

# run scripted installation via p2.director
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${ECLIPSE} \
-DsourceSites=${SITES} -Dinstall=${BASE_IUs} 
echo "--------------------------------"
echo "BASE FEATURES INSTALLED"
echo "--------------------------------"

# get a list of IUs to install from the Central site (based on the discovery.xml -> plugin.jar -> plugin.xml)
CENTRAL_URL=${INSTALL_PLAN#*,} # includes discovery.xml
# echo $CENTRAL_URL
wget ${CENTRAL_URL} -q --no-check-certificate -N -O directory.xml
PLUGINJAR=`cat directory.xml | egrep "org.jboss.tools.central.discovery_|com.jboss.jbds.central.discovery_" | sed "s#.\+url=\"\(.\+\).jar\".\+#\1.jar#"`
# echo "Got $PLUGINJAR"
CENTRAL_URL=${SITES#*,} # excludes discovery.xml
wget ${CENTRAL_URL}/${PLUGINJAR} -q --no-check-certificate -N -O plugin.jar
unzip -oq plugin.jar plugin.xml

# parse the list of features from the plugin.xml
FEATURES=`cat plugin.xml | egrep -v "<--|-->" |grep "iu id" | sed "s#.\+id=\"\(.\+\)\"\ */>#\1#" | sort | uniq`
CENTRAL_IUs=""; for f in $FEATURES; do CENTRAL_IUs="${CENTRAL_IUs},${f}.feature.group"; done; CENTRAL_IUs=${CENTRAL_IUs:1}

# parse the list of 3rd party siteUrl values from the plugin.xml; exclude jboss.discovery.site.url entries
EXTRA_URLS=`cat plugin.xml | grep -i siteUrl | grep -v jboss.discovery.site.url | sed "s#.\+siteUrl=\"\(.\+\)\"\ *>#\1#" | sort | uniq`
EXTRA_SITES=""; for e in $EXTRA_URLS; do EXTRA_SITES="${EXTRA_SITES},${e}"; done; EXTRA_SITES=${EXTRA_SITES:1}

# run scripted installation via p2.director
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${ECLIPSE} \
-DsourceSites=${SITES},${EXTRA_SITES} -Dinstall=${CENTRAL_IUs} 
echo "--------------------------------"
echo "CENTRAL FEATURES INSTALLED"
echo "--------------------------------"

# cleanup
rm -f ${WORKSPACE}/director.xml ${WORKSPACE}/directory.xml ${WORKSPACE}/plugin.jar ${WORKSPACE}/plugin.xml ${WORKSPACE}/category.xml