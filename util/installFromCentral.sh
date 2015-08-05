#!/bin/bash

# this Jenkins script is used to install a comma-separated list of IUs (.feature.groups) from update site(s) into a pre-existing Eclipse installation
# sample invocation:
# eclipse=${HOME}/tmp/Eclipse_Bundles/eclipse-jee-luna-M6-linux-gtk-x86_64.tar.gz
# workspace=${HOME}/eclipse/workspace-clean44
# target=${HOME}/eclipse/44clean; rm -fr ${target}/eclipse ${workspace}
# echo "Unpack $eclipse ..."; pushd ${target}; tar xzf ${eclipse}; popd
# ./installFromCentral.sh -ECLIPSE ${target}/eclipse/ -WORKSPACE ${workspace} \
# -INSTALL_PLAN http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.product_master/all/repo/,http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/master/devstudio-directory.xml \
# | tee /tmp/installFromCentral_log.txt; cat /tmp/installFromCentral_log.txt | egrep -i "could not be found|FAILED|Missing|Only one of the following|being installed|Cannot satisfy dependency|cannot be installed"
#
# See also https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/jbosstools-install-p2director.install-tests.matrix_master/

usage ()
{
  echo "Usage: $0 -ECLIPSE /path/to/eclipse-install/ -INSTALL_PLAN http://JBT-or-JBDS-update-site;http://JBT-or-JBDS/composite/directory.xml"
  echo "Example: $0 -ECLIPSE ${WORKSPACE}/eclipse/ -INSTALL_PLAN http://download.jboss.org/jbosstools/updates/nightly/core/master/,http://download.jboss.org/jbosstools/discovery/nightly/core/master/jbosstools-directory.xml"
  echo "Example: $0 -ECLIPSE ${HOME}/eclipse/44clean/eclipse/ -INSTALL_PLAN http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.product_master/all/repo/,http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/master/devstudio-directory.xml"
  exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

#director.xml script is used with Eclipse's AntRunner to launch p2.director
DIRECTORXML="http://download.jboss.org/jbosstools/updates/scripted-install/director.xml"

# use Eclipse VM from JAVA_HOME if available
if [[ -x ${JAVA_HOME}/bin/java ]]; then VM="-vm ${JAVA_HOME}/bin/java"; fi

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
    '-vm') VM="-vm $2"; shift 1;;
  esac
  shift 1
done

if [[ ! $INSTALL_PLAN ]]; then usage; fi

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=`mktemp -d`; fi
mkdir -p ${WORKSPACE}; cd ${WORKSPACE}

# default path to Eclipse install for Jenkins 
if [[ ! ${ECLIPSE} ]] && [[ -d ${WORKSPACE}/eclipse/ ]] && [[ -x ${WORKSPACE}/eclipse/eclipse ]]; then ECLIPSE=${WORKSPACE}/eclipse; fi 
chmod +x ${ECLIPSE}/eclipse

# get director.xml script
if [[ -f ${DIRECTORXML} ]]; then
  cp -f ${DIRECTORXML} ${WORKSPACE}/director.xml
else
  curl -s -k ${DIRECTORXML} > ${WORKSPACE}/director.xml
fi

# wipe existing Eclipse workspace
rm -fr ${WORKSPACE}/data; mkdir -p ${WORKSPACE}/data

# get list of sites from which to resolve IUs (based on list in INSTALL_PLAN);  and trim /*-directory.xml at the end
SITES=${INSTALL_PLAN%/*directory.xml}/
# trim double // at end of URL 
SITES=${SITES%//}/

checkLogForErrors ()
{
  errors="$(cat $1 | egrep -B1 -A2 "BUILD FAILED|Cannot complete the install|Only one of the following|exec returned: 13")"
  if [[ $errors ]]; then
    echo "--------------------------------"
    echo "INSTALL FAILED"
    echo ""
    echo "$errors"
    echo "--------------------------------"
    exit 2
  fi
}

# get a list of IUs to install from the JBT or JBDS update site (using p2.director -list)
BASE_URL=${SITES%,*}
# include source features too?
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} -DtargetDir=${ECLIPSE} \
list.feature.groups -Doutput=${WORKSPACE}/feature.groups.properties -DsourceSites=${BASE_URL} | tee ${WORKSPACE}/installFromCentral_log.1.txt
checkLogForErrors ${WORKSPACE}/installFromCentral_log.1.txt

BASE_IUs=""
if [[ -f ${WORKSPACE}/feature.groups.properties ]]; then 
  FEATURES=`cat ${WORKSPACE}/feature.groups.properties | grep ".feature.group=" | sed "s#\(.\+.feature.group\)=.\+#\1#" | sort | uniq`
  for f in $FEATURES; do BASE_IUs="${BASE_IUs},${f}"; done; BASE_IUs=${BASE_IUs:1}
fi

date; du -sh ${ECLIPSE}

# run scripted installation via p2.director
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} -DtargetDir=${ECLIPSE} \
-DsourceSites=${SITES} -Dinstall=${BASE_IUs} | tee ${WORKSPACE}/installFromCentral_log.2.txt
checkLogForErrors ${WORKSPACE}/installFromCentral_log.2.txt

date; du -sh ${ECLIPSE}

echo "--------------------------------"
echo "BASE FEATURES INSTALLED"
echo "--------------------------------"

# get a list of IUs to install from the Central site (based on the discovery.xml -> plugin.jar -> plugin.xml)
CENTRAL_URL=${INSTALL_PLAN#*,}; # here, we include discovery.xml
# echo CENTRAL_URL = $CENTRAL_URL
if [[ $CENTRAL_URL != $INSTALL_PLAN ]]; then 
  curl -k ${CENTRAL_URL} > ${WORKSPACE}/directory.xml 
  PLUGINJAR=`cat ${WORKSPACE}/directory.xml | egrep "org.jboss.tools.central.discovery_|com.jboss.jbds.central.discovery_" | sed "s#.\+url=\"\(.\+\).jar\".\+#\1.jar#"`
  echo "Discovery plugin jar: $PLUGINJAR"
  CENTRAL_URL=${SITES#*,}; # this time it excludes discovery.xml
  # echo CENTRAL_URL = $CENTRAL_URL
  curl -k ${CENTRAL_URL}/${PLUGINJAR} > ${WORKSPACE}/plugin.jar
  unzip -oq ${WORKSPACE}/plugin.jar plugin.xml

  # extract the <iu id=""> and <connectorDescriptor siteUrl=""> properties, excluding commented out stuff
  # DO NOT INDENT the next lines after cat
  cat << XSLT > ${WORKSPACE}/get-ius-and-siteUrls.xsl
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="2.0">
  <xsl:output omit-xml-declaration="yes"/>
  <xsl:template match="comment()" />
  <xsl:template match="connectorDescriptor">
    <xsl:copy >
      <xsl:for-each select="@siteUrl">
        <xsl:copy />
      </xsl:for-each>
      <xsl:apply-templates />
    </xsl:copy>
  </xsl:template>
  <xsl:template match="iu">
    <xsl:copy >
      <xsl:for-each select="@id">
        <xsl:copy />
      </xsl:for-each>
      <xsl:apply-templates />
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
XSLT

  ${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} \
  transform -Dxslt=${WORKSPACE}/get-ius-and-siteUrls.xsl -Dinput=${WORKSPACE}/plugin.xml -Doutput=${WORKSPACE}/plugin.transformed.xml -q | tee ${WORKSPACE}/installFromCentral_log.3.txt
  checkLogForErrors ${WORKSPACE}/installFromCentral_log.3.txt

  # parse the list of features from plugin.transformed.xml
  FEATURES=`cat ${WORKSPACE}/plugin.transformed.xml | grep "iu id" | sed "s#.\+id=\"\(.\+\)\"\ */>#\1#" | sort | uniq`
  CENTRAL_IUs=""; for f in $FEATURES; do CENTRAL_IUs="${CENTRAL_IUs},${f}.feature.group"; done; CENTRAL_IUs=${CENTRAL_IUs:1}; #echo $CENTRAL_IUs

  # parse the list of 3rd party siteUrl values from plugin.transformed.xml; exclude jboss.discovery.site.url entries
  EXTRA_URLS=`cat ${WORKSPACE}/plugin.transformed.xml | grep -i siteUrl | egrep -v "jboss.discovery.site.url|jboss.discovery.earlyaccess.site.url" | sed "s#.\+siteUrl=\"\(.\+\)\"\ *>#\1#" | sort | uniq`
  EXTRA_SITES=""; for e in $EXTRA_URLS; do 
    if [[ ${e/http/} != ${e} ]] || [[ ${e/ftp:/} != ${e} ]]; then EXTRA_SITES="${EXTRA_SITES},${e}"; else echo "[WARN] Skip EXTRA_SITE = $e"; fi
  done
  EXTRA_SITES=${EXTRA_SITES:1}; # echo $EXTRA_SITES

  date; du -sh ${ECLIPSE}

  # run scripted installation via p2.director
  ${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} -DtargetDir=${ECLIPSE} \
  -DsourceSites=${SITES},${EXTRA_SITES} -Dinstall=${CENTRAL_IUs} | tee ${WORKSPACE}/installFromCentral_log.4.txt
  checkLogForErrors ${WORKSPACE}/installFromCentral_log.4.txt

  date; du -sh ${ECLIPSE}

  echo "--------------------------------"
  echo "CENTRAL FEATURES INSTALLED"
  echo "--------------------------------"
else
  echo "--------------------------------"
  echo "NO CENTRAL DISCOVERY URL FOUND FOR"
  echo "INSTALL_PLAN = ${INSTALL_PLAN}"
  echo "--------------------------------"
fi

# cleanup
if [[ $CLEAN ]]; then
  rm -f ${WORKSPACE}/installFromCentral_log*.txt ${WORKSPACE}/director.xml ${WORKSPACE}/feature.groups.properties ${WORKSPACE}/directory.xml ${WORKSPACE}/plugin.jar ${WORKSPACE}/plugin.xml ${WORKSPACE}/get-ius-and-siteUrls.xsl ${WORKSPACE}/plugin.transformed.xml 
fi