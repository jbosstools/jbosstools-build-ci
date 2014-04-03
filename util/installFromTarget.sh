#!/bin/bash

# this Jenkins script is used to install all IUs (plugins and feature.groups) from a target platform update site(s) into a pre-existing Eclipse installation
# sample invocation:
# eclipse=${HOME}/tmp/Eclipse_Bundles/eclipse-jee-luna-M6-linux-gtk-x86_64.tar.gz
# workspace=${HOME}/eclipse/workspace-clean44
# target=${HOME}/eclipse/44clean; rm -fr ${target}/eclipse ${workspace}
# echo "Unpack $eclipse ..."; pushd ${target}; tar xzf ${eclipse}; popd
# ./installFromTarget.sh -ECLIPSE ${target}/eclipse/ -WORKSPACE ${workspace} \
# -INSTALL_PLAN file://${HOME}/eclipse/workspace-jboss/jbosstools-github-master/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/ \
# | tee /tmp/log.txt; cat /tmp/log.txt | egrep -i "could not be found|FAILED|Missing|Only one of the following|being installed|Cannot satisfy dependency|cannot be installed"
#
# See also https://jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/Target-Platforms/job/jbosstoolstargetplatforms-matrix/

usage ()
{
  echo "Usage: $0 -ECLIPSE /path/to/eclipse-install/ -INSTALL_PLAN /path/to/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/"
  echo "Example: $0 -ECLIPSE ${WORKSPACE}/eclipse/ -INSTALL_PLAN ${WORKSPACE}/jbosstools/multiple/target/jbosstools-multiple.target.repo/"
  echo "Example: $0 -ECLIPSE ${HOME}/eclipse/44clean/eclipse/ -INSTALL_PLAN file://${HOME}/eclipse/workspace-jboss/jbosstools-github-master/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/"
  exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

#director.xml script is used with Eclipse's AntRunner to launch p2.director
DIRECTORXML="http://download.jboss.org/jbosstools/updates/scripted-installation/director.xml"

# read commandline args
# NOTE: Jenkins matrix jobs require semi-colons here, but to pass to shell, must use quotes
# On commandline, can use comma-separated pair instead so quotes aren't needed
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-INSTALL_PLAN') INSTALL_PLAN="${2/;/,}"; shift 1;; # replace ; with ,
    '-ECLIPSE') ECLIPSE="$2"; shift 1;;
    '-WORKSPACE') WORKSPACE="$2"; shift 1;;
    '-DIRECTORXML') DIRECTORXML="$2"; shift 1;;
    '-CLEAN') CLEAN="$2"; shift 1;;
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
if [[ -f ${DIRECTORXML} ]]; then
  cp -f ${DIRECTORXML} ${WORKSPACE}/director.xml
else
  wget ${DIRECTORXML} -q --no-check-certificate -N -O ${WORKSPACE}/director.xml
fi

# wipe existing Eclipse workspace
rm -fr ${WORKSPACE}/data; mkdir -p ${WORKSPACE}/data

# collect feature.groups to install
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${ECLIPSE} \
list.feature.groups -Doutput=${WORKSPACE}/feature.group.list.properties -DsourceSites=${INSTALL_PLAN}
# collect plugins to install (in case we have orphan plugins not inside feature.groups)
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${ECLIPSE} \
list.plugins -Doutput=${WORKSPACE}/plugin.list.properties -DsourceSites=${INSTALL_PLAN}
BASE_IUs=""
for f in feature.group.list.properties plugin.list.properties; do
  if [[ -f ${WORKSPACE}/${f} ]]; then 
    # TODO: find a better way to filter swt platform fragments like org.eclipse.swt.cocoa.macosx.x86_64 and org.eclipse.swt.cocoa.win32.win32.x86_64 
    # which are not identified as fragments and which cannot be installed onto a linux machine during this install test
    ALL_IUS=`cat ${WORKSPACE}/${f} | egrep -v "win32|cocoa|macosx|x86|_64|ppc|aix|solaris|hpux|s390|ia64" | grep "=" | sed "s#\(.\+\)=.\+#\1#" | sort | uniq`
    for f in $ALL_IUS; do BASE_IUs="${BASE_IUs},${f}"; done
  fi
done
BASE_IUs=${BASE_IUs:1}
date; du -sh ${ECLIPSE}

# run scripted installation via p2.director
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml -DtargetDir=${ECLIPSE} \
-DsourceSites=${INSTALL_PLAN} -Dinstall=${BASE_IUs}

date; du -sh ${ECLIPSE}

echo "-------------"
echo "IUs INSTALLED"
echo "-------------"

# cleanup
if [[ $CLEAN ]]; then
  rm -f ${WORKSPACE}/director.xml
  rm -f ${WORKSPACE}/*.list.properties 
  rm -f ${WORKSPACE}/directory.xml ${WORKSPACE}/plugin.jar ${WORKSPACE}/plugin.xml ${WORKSPACE}/get-ius-and-siteUrls.xsl ${WORKSPACE}/plugin.transformed.xml 
fi