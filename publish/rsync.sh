#!/bin/bash
# Script to rsync build artifacts from Jenkins to filemgmt or www.qa
# NOTE: sources should be checked out into ${WORKSPACE}/sources 

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools # or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio or /qa/services/http/binaries/RHDS
URL=http://download.jboss.org/jbosstools # or https://devstudio.redhat.com or http://www.qa.jboss.com/binaries/RHDS

# can be used to publish a build (including installers, site zips, MD5s, build log) or just an update site folder
usage ()
{
  echo "Usage  : $0 [-DESTINATION destination] [-URL URL] -s source_path -t target_path"
  echo ""

  echo "To push a project build folder from Jenkins to staging:"
  echo "   $0 -s \${WORKSPACE}/sources/site/target/repository/ -t mars/snapshots/builds/\${JOB_NAME}/\${BUILD_ID}-B\${BUILD_NUMBER}/all/repo/"  # BUILD_ID=2015-02-17_17-57-54; 
  echo ""

  echo "To push JBT build + update site folders:"
  echo "   $0 -s \${WORKSPACE}/sources/aggregate/site/target/fullSite          -t mars/snapshots/builds/\${JOB_NAME}/\${BUILD_ID}-B\${BUILD_NUMBER}"
  echo "   $0 -s \${WORKSPACE}/sources/aggregate/site/target/fullSite/all/repo -t mars/snapshots/updates/core/\${stream}"
  echo ""

  echo "To push JBDS build + update site folders:"
  echo "   $0 -DESTINATION /qa/services/http/binaries/RHDS -URL http://www.qa.jboss.com/binaries/RHDS           -s \${WORKSPACE}/sources/results                   -t 9.0/snapshots/builds/devstudio.product_master/"
  echo "   $0 -DESTINATION devstudio@filemgmt.jboss.org:/www_htdocs/devstudio -URL https://devstudio.redhat.com -s \${WORKSPACE}/sources/site/target/fullSite/repo -t 9.0/snapshots/updates/core/master/"
  echo ""
  exit 1;
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., /qa/services/http/binaries/RHDS
    '-URL') URL="$2"; shift 1;; # override for JBDS publishing, eg., http://www.qa.jboss.com/binaries/RHDS
    '-s') SOURCE_PATH="$2"; shift 1;; # ${WORKSPACE}/sources/site/target/repository/
    '-t') TARGET_PATH="$2"; shift 1;; # mars/snapshots/builds/<job-name>/<build-number>/, mars/snapshots/updates/core/{4.3.0.Alpha1, master}/
  esac
  shift 1
done

# TODO: make sure we have source zips for all aggregates and JBDS

# TODO: make sure we have MD5 sums for all zip/jar artifacts

# build the target_path with sftp to ensure intermediate folders exist
if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
  seg="."; for d in ${TARGET_PATH//\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp $DESTINATION/; done; seg=""
else
  mkdir -p $DESTINATION/${TARGET_PATH}
fi

# copy the source into the target
rsync -arzq --protocol=28 ${SOURCE_PATH}/* $DESTINATION/${TARGET_PATH}/

# given /downloads_htdocs/tools/mars/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master/B13-2015-03-06_17-58-07/all/repo/
# return mars/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master
PARENT_PATH=$(echo $TARGET_PATH | sed -e "s#/\?downloads_htdocs/tools/##" -e "s#/\?all/repo/\?##" -e "s#/\$##" -e "s#^/##" -e "s#\(.\+\)/[^/]\+#\1#")

# for published builds on download.jboss.org ONLY!
# regenerate http://download.jboss.org/jbosstools/builds/${TARGET_PATH}/composite*.xml files for up to 5 builds, cleaning anything older than 5 days old
if [[ ${TARGET_PATH/builds/} != ${TARGET_PATH} ]] && [[ ${DESTINATION} = "tools@filemgmt.jboss.org:/downloads_htdocs/tools" ]] && [[ -f ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh ]]; then
  PARENT_PARENT_PATH=$(echo $PARENT_PATH | sed -e "s#\(.\+\)/[^/]\+#\1#")
  . ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh -d ${PARENT_PARENT_PATH} --no-subdirs --childFolderSuffix /all/repo/ --keep 5 --age-to-delete 5
fi

wgetParams="--timeout=900 --wait=10 --random-wait --tries=10 --retry-connrefused --no-check-certificate -q"
getRemoteFile ()
{
  # requires $wgetParams and $tmpdir to be defined (above)
  getRemoteFileReturn=""
  grfURL="$1"
  output=`mktemp --tmpdir ${tmpdir} getRemoteFile.XXXXXX`
  if [[ ! `wget ${wgetParams} ${grfURL} -O ${tmpdir}/${output} 2>&1 | egrep "ERROR 404"` ]]; then # file downloaded
    getRemoteFileReturn=${tmpdir}/${output}
  else
    getRemoteFileReturn=""
    rm -f ${tmpdir}/${output}
  fi
}

# store a copy of this build's log in the target folder (if JOB_NAME is defined)
if [[ ${JOB_NAME} ]]; then 
  bl=${tmpdir}/BUILDLOG.txt
  getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/${BUILD_NUMBER}/consoleText"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${bl}; fi
  touch ${bl}; rsync -arzq --protocol=28 ${bl} $DESTINATION/${TARGET_PATH}/logs/
fi

# TODO: create BUILD_DESCRIPTION variable (HTML string) in Jenkins log containing:
# link to log, target platforms used, update site/installers folder, coverage report & jacoco file, buildinfo.json
LAST_SEGMENT=$(echo $TARGET_PATH | sed -e "s#/\?downloads_htdocs/tools/##" -e "s#/\?all/repo/\?##" -e "s#/\$##" -e "s#^/##" -e "s#\(.\+\)/\([^/]\+\)#\2#")
BUILD_DESCRIPTION='<li><a href='${URL}'/'${PARENT_PATH}'/'${LAST_SEGMENT}'>'${LAST_SEGMENT}'</a></li>'

# purge temp folder
rm -fr ${tmpdir} 