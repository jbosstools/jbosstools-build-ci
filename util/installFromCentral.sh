#!/bin/bash

# this Jenkins script is used to install a comma-separated list of IUs (.feature.groups) from update site(s) into a pre-existing Eclipse installation
# sample invocation:
# eclipse=${HOME}/tmp/Eclipse_Bundles/eclipse-jee-neon-M3-linux-gtk.tar.gz
# workspace=${HOME}/eclipse/workspace-clean46
# target=${HOME}/eclipse/46clean; rm -fr ${target}/eclipse ${workspace}
# echo "Unpack $eclipse ..."; pushd ${target}; tar xzf ${eclipse}; popd
# ./installFromCentral.sh -ECLIPSE ${target}/eclipse/ -WORKSPACE ${workspace} \
# -INSTALL_PLAN "https://devstudio.redhat.com/10.0/snapshots/builds/jbosstools-discovery.central_4.4.neon/latest/all/repo/;https://devstudio.redhat.com/10.0/snapshots/builds/jbosstools-discovery.earlyaccess_4.4.neon/latest/all/repo/devstudio-directory.xml" \
# | tee /tmp/installFromCentral_log.txt; cat /tmp/installFromCentral_log.txt | egrep -i "could not be found|FAILED|Missing|Only one of the following|being installed|Cannot satisfy dependency|cannot be installed"
#
# See also https://jenkins.hosts.mwqe.eng.bos.redhat.com/hudson/job/jbosstools-install-p2director.install-tests.matrix_master/

usage ()
{
  echo ""
  echo "Usage: $0 -ECLIPSE /path/to/eclipse-install/ -INSTALL_PLAN \\"
  echo "  \"http://JBT-or-JBDS-update-site;http://JBT-or-JBDS-composite-discovery-site/directory.xml\""
  echo ""
  echo "Example: $0 -ECLIPSE ${WORKSPACE}/eclipse/ -INSTALL_PLAN \\"
  echo "  \"http://download.jboss.org/jbosstools/neon/snapshots/builds/jbosstools-discovery.central_4.4.neon/latest/all/repo/;\\"
  echo "http://download.jboss.org/jbosstools/neon/snapshots/builds/jbosstools-discovery.earlyaccess_4.4.neon/latest/all/repo/jbosstools-directory.xml\""
  echo ""
  echo "Example: $0 -ECLIPSE ${HOME}/eclipse/46clean/eclipse/ -INSTALL_PLAN \\"
  echo "  \"https://devstudio.redhat.com/10.0/snapshots/builds/jbosstools-discovery.central_4.4.neon/latest/all/repo/;\\"
  echo "https://devstudio.redhat.com/10.0/snapshots/builds/jbosstools-discovery.earlyaccess_4.4.neon/latest/all/repo/devstudio-directory.xml\""
  echo ""
  exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

# comma-separated list of IUs to exclude from installation
EXCLUDES=""

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
    '-EXCLUDES') EXCLUDES="$2"; shift 1;;
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
    echo ""
    echo "--------------------------------"
    echo "[ERROR] INSTALL FAILED"
    echo ""
    echo "$errors"
    echo "--------------------------------"
    echo ""
    exit 2
  fi
}

echo ""
echo "--------------------------------"
date
echo "[INFO] FOR ECLIPSE = ${ECLIPSE}"
installedFeatures0=$(ls ${ECLIPSE}/features | wc -l)
echo "[INFO] ${installedFeatures0} BASE FEATURES INSTALLED ["$(cd $ECLIPSE;du -sh)"]"
echo "--------------------------------"
echo ""

# get a list of IUs to install from the JBT or JBDS update site (using p2.director -list)
BASE_URL=${SITES%,*}
# include source features too?
${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} -DtargetDir=${ECLIPSE} \
list.feature.groups -Doutput=${WORKSPACE}/feature.groups.properties -DsourceSites=${BASE_URL} | tee ${WORKSPACE}/installFromCentral_log.1.txt
checkLogForErrors ${WORKSPACE}/installFromCentral_log.1.txt

BASE_IUs=""
if [[ -f ${WORKSPACE}/feature.groups.properties ]]; then 
  FEATURES=`cat ${WORKSPACE}/feature.groups.properties | grep ".feature.group=" | sed "s#\(.\+.feature.group\)=.\+#\1#" | sort | uniq`
  if [[ ${EXCLUDES} ]]; then echo "[INFO] [B] EXCLUDES = $EXCLUDES"; fi
  for f in $FEATURES; do
    include=1
    if [[ ${EXCLUDES} ]]; then 
      # only add the found features if they're NOT matched by the EXCLUDE rule
      for e in ${EXCLUDES//,/ }; do
        if [[ ${e} != ${e//\*/} ]] && [[ $(echo ${f} | egrep "${e}") ]]; then # using a * wildcard & matched grep pattern
          echo "[INFO] [B] Exclude ${f} by ${e}"
          include=0
          break
        elif [[ ${f/.feature.group/} == ${e/.feature.group/} ]]; then # matched exact IU (without .feature.group suffix)
          echo "[INFO] [B] Exclude ${f}"
          include=0
          break
        fi
      done
    fi
    if [[ $include == 1 ]]; then BASE_IUs="${BASE_IUs},${f}"; fi
  done
  BASE_IUs=${BASE_IUs:1}
fi

if [[ ${BASE_IUs} ]]; then 
  # run scripted installation via p2.director
  ${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} -DtargetDir=${ECLIPSE} \
  -DsourceSites=${SITES} -Dinstall=${BASE_IUs} | tee ${WORKSPACE}/installFromCentral_log.2.txt
  checkLogForErrors ${WORKSPACE}/installFromCentral_log.2.txt

  echo ""
  echo "--------------------------------"
  date
  echo "[INFO] [B] FOR INSTALL_PLAN = ${INSTALL_PLAN}"
  installedFeatures1=$(ls ${ECLIPSE}/features | wc -l)
  echo  $(( installedFeatures1 - installedFeatures0 ))" NEW FEATURES INSTALLED ["$(cd $ECLIPSE;du -sh)"]"
  echo "[INFO] [B] FROM ${SITES}"
  # echo "${BASE_IUs}"
  echo "--------------------------------"
  echo ""
else
  echo ""
  echo "--------------------------------"
  echo "[WARNING] [B] NO IUs FOUND FOR"
  echo "[WARNING] [B] INSTALL_PLAN = ${INSTALL_PLAN}"
  echo "[WARNING] [B] and SITES = ${SITES}"
  echo "--------------------------------"
  cat ${WORKSPACE}/feature.groups.properties
  echo "--------------------------------"
  echo ""
  installedFeatures1=0
fi

# get a list of IUs to install from the Central site (based on the discovery.xml -> plugin.jar -> plugin.xml)
CENTRAL_URL=${INSTALL_PLAN#*,}; # here, we include discovery.xml
#echo CENTRAL_URL = ${CENTRAL_URL}

if [[ $CENTRAL_URL != $INSTALL_PLAN ]]; then 
  curl -s -k ${CENTRAL_URL} > ${WORKSPACE}/directory.xml
  PLUGINJARS=`cat ${WORKSPACE}/directory.xml | egrep "org.jboss.tools.central.discovery|com.jboss.jbds.central.discovery" | sed "s#.\+url=\"\(.\+\).jar\".\+#\1.jar#"`
  if [[ ${PLUGINJARS} ]]; then 
    echo "[INFO] [C] Discovery plugin jars found: ${PLUGINJARS}"
  else
    echo "[ERROR] [C] Discovery plugin jars NOT found in ${WORKSPACE}/directory.xml:"
    echo "--------------------------------"
    cat ${WORKSPACE}/feature.groups.properties
    echo "--------------------------------"
    exit 1
  fi

  CENTRAL_URL=${SITES#*,}; # this time it excludes discovery.xml
  # echo CENTRAL_URL = $CENTRAL_URL

  CENTRAL_IUs=""
  EXTRA_SITES=""

  # extract the <iu id=""> and <connectorDescriptor siteUrl=""> properties, excluding commented out stuff
  # DO NOT INDENT the next lines after cat
  cat << EOXSLT > ${WORKSPACE}/get-ius-and-siteUrls.xsl
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
EOXSLT

  # for each Central Discover plugin
  for PLUGINJAR in $PLUGINJARS; do 
    curl -s -k ${CENTRAL_URL}/${PLUGINJAR} > ${WORKSPACE}/plugin.jar
    unzip -oq -d ${WORKSPACE} ${WORKSPACE}/plugin.jar plugin.xml

    ${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} \
    transform -Dxslt=${WORKSPACE}/get-ius-and-siteUrls.xsl -Dinput=${WORKSPACE}/plugin.xml -Doutput=${WORKSPACE}/plugin.transformed.xml -q | tee ${WORKSPACE}/installFromCentral_log.3__${PLUGINJAR/\//_}.txt
    checkLogForErrors ${WORKSPACE}/installFromCentral_log.3__${PLUGINJAR/\//_}.txt

    # parse the list of features from plugin.transformed.xml
    FEATURES=`cat ${WORKSPACE}/plugin.transformed.xml | grep "iu id" | sed "s#.\+id=\"\(.\+\)\"\ */>#\1#" | sort | uniq`
    if [[ ${EXCLUDES} ]]; then echo "[INFO] [C] EXCLUDES = $EXCLUDES"; fi
    for f in $FEATURES; do
      include=1
      # only add the found features if they're NOT matched by the EXCLUDE rule
      if [[ ${EXCLUDES} ]]; then 
        for e in ${EXCLUDES//,/ }; do
          if [[ ${e} != ${e/*/} ]] && [[ $(echo ${f} | egrep "${e}") ]]; then # using a * wildcard & matched grep pattern
            echo "[INFO] [C] Exclude ${f} by ${e}"
            include=0
            break
          elif [[ ${f/.feature.group/} == ${e/.feature.group/} ]]; then # matched exact IU (without .feature.group suffix)
            echo "[INFO] [C] Exclude ${f}"
            include=0
            break
          fi
        done
      fi
      if [[ $include == 1 ]]; then CENTRAL_IUs="${CENTRAL_IUs},${f}.feature.group"; fi
    done

    # parse the list of 3rd party siteUrl values from plugin.transformed.xml; exclude jboss.discovery.site.url entries
    EXTRA_URLS=`cat ${WORKSPACE}/plugin.transformed.xml | grep -i siteUrl | egrep -v "jboss.discovery.site.url|jboss.discovery.earlyaccess.site.url" | sed "s#.\+siteUrl=\"\(.\+\)\"\ *>#\1#" | sort | uniq`
    for e in $EXTRA_URLS; do 
      if [[ ${e/http/} != ${e} ]] || [[ ${e/ftp:/} != ${e} ]]; then EXTRA_SITES="${EXTRA_SITES},${e}"; else echo "[WARNING] Skip EXTRA_SITE = $e"; fi
    done
    rm -f ${WORKSPACE}/plugin.jar ${WORKSPACE}/plugin.xml ${WORKSPACE}/plugin.transformed.xml
  done

  CENTRAL_IUs=${CENTRAL_IUs:1}; 
  echo "[DEBUG] [C] CENTRAL_IUs = $CENTRAL_IUs"
  EXTRA_SITES=${EXTRA_SITES:1};
  echo "[DEBUG] [C] EXTRA_SITES = $EXTRA_SITES"

    # run scripted installation via p2.director
  ${ECLIPSE}/eclipse -consolelog -nosplash -data ${WORKSPACE}/data -application org.eclipse.ant.core.antRunner -f ${WORKSPACE}/director.xml ${VM} -DtargetDir=${ECLIPSE} \
  -DsourceSites=${SITES},${EXTRA_SITES} -Dinstall=${CENTRAL_IUs} | tee ${WORKSPACE}/installFromCentral_log.4.txt
  checkLogForErrors ${WORKSPACE}/installFromCentral_log.4.txt

  echo ""
  echo "--------------------------------"
  date
  echo "[INFO] [C] FOR INSTALL_PLAN = ${INSTALL_PLAN}"
  installedFeatures2=$(ls ${ECLIPSE}/features | wc -l)
  echo  $(( installedFeatures2 - installedFeatures1 ))" NEW FEATURES INSTALLED FROM CENTRAL (and/or EARLYACCESS) ["$(cd $ECLIPSE;du -sh)"]"
  echo "[INFO] [C] FROM ${SITES},${EXTRA_SITES}"
  #echo "${CENTRAL_IUs}"
  echo "--------------------------------"
  echo ""
else
  echo ""
  echo "--------------------------------"
  echo "[WARNING] [C] NO CENTRAL DISCOVERY URL FOUND FOR"
  echo "[WARNING] [C] INSTALL_PLAN = ${INSTALL_PLAN}"
  echo "[WARNING] [C] FROM SITES = ${SITES}"
  echo "[WARNING] [C] AND EXTRA_SITES = ${EXTRA_SITES}"
  echo "--------------------------------"
  echo ""
fi

# cleanup
if [[ $CLEAN ]]; then
  rm -f ${WORKSPACE}/installFromCentral_log*.txt ${WORKSPACE}/director.xml ${WORKSPACE}/feature.groups.properties ${WORKSPACE}/directory.xml ${WORKSPACE}/get-ius-and-siteUrls.xsl 
fi