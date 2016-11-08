#!/bin/bash
# Script to merge downstream JBT/JBDS IS discovery plugins into an existing staging or development JBT/JBDS discovery site (plugins + xml)

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

TOOLS=tools@filemgmt.jboss.org:/downloads_htdocs/tools
JBDS=devstudio@filemgmt.jboss.org:/www_htdocs/devstudio

# by default, push to TOOLS, not JBDS
DESTINATION="${TOOLS}" # or "${JBDS}"
quiet="" # or -q

usage ()
{
  echo "Usage  : $0 [-DESTINATION destination] -v version -vr version-with-respin -is integration-stack-discovery-site"
  echo ""
  echo "Example 1: $0 -v 4.4.0.Final -vr 4.4.0.Final -is http://download.jboss.org/jbosstools/neon/staging/updates/integration-stack/discovery/4.4.0.Alpha2/"
  echo "Example 2: $0 -v 10.0.0.GA -vr 10.0.0.GA -is https://devstudio.redhat.com/10.0/staging/updates/integration-stack/discovery/10.0.0.Alpha2/ -JBDS"

  echo ""
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., /qa/services/http/binaries/RHDS
    '-JBDS') DESTINATION="${JBDS}"; shift 0;; # shortcut
    '-v'|'-version') version="$2"; shift 1;;
    '-vr'|'-versionWithRespin') versionWithRespin="$2"; shift 1;;
    '-is') ISsite="$2"; shift 1;;
    '-qual') qualities="$qualities $2"; shift 1;;
    '-r'|'-rootFolder') rootFolder="$2"; shift 1;;
    '-q') quiet="-q"; shift 0;;
    *) OTHERFLAGS="${OTHERFLAGS} $1"; shift 0;;
  esac
  shift 1
done

# by default, only affect the staging site; use '-q development -q stable' to change LIVE development and stable site (use with caution!)
if [[ ! ${qualities} ]]; then qualities=staging; fi

if [[ $DESTINATION = $TOOLS ]]; then
  directoryXML=jbosstools-directory.xml
  if [[ ! $rootFolder ]]; then rootFolder=neon; fi
  destinationURL=http://download.jboss.org/jbosstools/${rootFolder}
else
  directoryXML=devstudio-directory.xml
  if [[ ! $rootFolder ]]; then rootFolder=10.0; fi
  destinationURL=https://devstudio.redhat.com/${rootFolder}
fi  
for quality in ${qualities}; do
  tmpdir=/tmp/merge_${quality}_IS_plugins_to_${directoryXML}; mkdir -p $tmpdir; pushd $tmpdir >/dev/null
    # get plugin jar xml
    wget ${ISsite}/${directoryXML} --no-check-certificate ${quiet} -O - | grep integration-stack > $tmpdir/pluginXML.fragment.txt
    # if [[ -f $tmpdir/pluginXML.fragment.txt ]]; then cat $tmpdir/pluginXML.fragment.txt; fi # debugging
    # echo "" # debugging
    # echo "[INFO] versionWithRespin = ${versionWithRespin}" # debugging
    mkdir -p ${rootFolder}/${quality}/updates/discovery.central/${versionWithRespin}/plugins/
    pushd ${rootFolder}/${quality}/updates/discovery.central/${versionWithRespin}/plugins/ >/dev/null
      # get plugin jars names/paths
      plugins=$(cat $tmpdir/pluginXML.fragment.txt | sed "s#.\+url=\"\(.\+\.jar\)\".\+#\1#")
      # get plugin jars into discovery.central
      for plugin in $plugins; do wget ${ISsite}/${plugin} --no-check-certificate ${quiet} && echo "[INFO] $plugin"; done
    popd >/dev/null
    # copy into discovery.earlyaccess
    mkdir -p ${rootFolder}/${quality}/updates/discovery.earlyaccess/${versionWithRespin}/plugins/
    rsync -aq ${rootFolder}/${quality}/updates/discovery.central/${versionWithRespin}/plugins/*.jar ${rootFolder}/${quality}/updates/discovery.earlyaccess/${versionWithRespin}/plugins/
    echo ""
    # get JBDS discovery site XML - both discovery.central and discovery.earlyaccess
    echo "[INFO] Verify changes here:"
    for disco in discovery.central discovery.earlyaccess; do
      pushd ${rootFolder}/${quality}/updates/${disco}/${versionWithRespin}/ >/dev/null
        rsync -aqrz --rsh=ssh --protocol=28 ${DESTINATION}/${rootFolder}/${quality}/updates/${disco}/${versionWithRespin}/${directoryXML} ./
        # merge pluginXML fragment into ${directoryXML}
        sed -i "/<\/directory>/d" ${directoryXML} # remove closing tag
        sed -i "/.\+integration-stack.\+/d" ${directoryXML} # remove any existing plugins
        cat $tmpdir/pluginXML.fragment.txt | sed -e "s#earlyaccess/plugins/#plugins/#">> ${directoryXML}
        echo "</directory>" >> ${directoryXML} # add closing tag back on
        # echo ""; echo "`pwd` / ${directoryXML} :"; cat ${directoryXML}; echo "" # debugging
        #ls -l `pwd`/${directoryXML} `pwd`/plugins # debugging

        # push new plugins and updated xml to DESTINATION 
        rsync -aqrz --rsh=ssh --protocol=28 ./* ${DESTINATION}/${rootFolder}/${quality}/updates/${disco}/${versionWithRespin}/

        echo " >> ${destinationURL}/${quality}/updates/${disco}/${versionWithRespin}/${directoryXML}"
        echo " >> ${destinationURL}/${quality}/updates/${disco}/${versionWithRespin}/plugins/"
      popd >/dev/null
    done

  popd >/dev/null
  rm -fr $tmpdir
done

