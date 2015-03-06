#!/bin/bash
# Script to rsync build artifacts from Jenkins to filemgmt or www.qa
# NOTE: sources MUST be checked out into ${WORKSPACE}/sources 

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

# where to create the stuff to publish
STAGINGDIR=${WORKSPACE}/results/${JOB_NAME}

DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools # or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio or /qa/services/http/binaries/RHDS
URL=http://download.jboss.org/jbosstools # or https://devstudio.redhat.com or http://www.qa.jboss.com/binaries/RHDS

# BUILD_ID=2015-02-17_17-57-54; 
if [[ ! ${BUILD_ID} ]]; then
	BUILD_ID=`date +%Y-%m-%d_%H-%M-%S`
	timestamp=$(echo $BUILD_ID | tr -d "_-"); timestamp=${timestamp:0:12}; 
	echo $timestamp; # 20150217-1757
fi
if [[ ! ${BUILD_NUMBER} ]]; then 
	BUILD_NUMBER=000
fi

# can be used to publish a build (including installers, site zips, MD5s, build log) or just an update site folder
usage ()
{
  echo "Usage  : $0 [-DESTINATION destination] [-URL URL] -s source_path -t target_path"
  echo ""

  echo "To push a project build folder from Jenkins to staging:"
  echo "   $0 -s sources/site/target/fullSite/ -t mars/snapshots/builds/jbosstools-base_4.3.mars/"
  echo ""

  echo "To push JBT build + update site folders:"
  echo "   $0 -s sources/site/target/fullSite      -t mars/snapshots/builds/jbosstools-build-sites.aggregate.site_4.3.mars/B${BUILD_NUMBER}-${BUILD_ID}"
  echo "   $0 -s sources/site/target/fullSite/repo -t mars/snapshots/updates/core/master"
  echo ""

  echo "To push JBDS build + update site folders:"
  echo "   $0 -DESTINATION /qa/services/http/binaries/RHDS -URL http://www.qa.jboss.com/binaries/RHDS           -s sources/results                   -t 9.0/snapshots/builds/devstudio.product_master/"
  echo "   $0 -DESTINATION devstudio@filemgmt.jboss.org:/www_htdocs/devstudio -URL https://devstudio.redhat.com -s sources/site/target/fullSite/repo -t 9.0/snapshots/updates/core/master/"
  echo ""
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

# TODO: create BUILD_DESCRIPTION variable (HTML string) in Jenkins log containing:
# link to log, target platforms used, update site/installers folder, coverage report & jacoco file, buildinfo.json

# build the target_path with sftp to ensure intermediate folders exist
if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
  seg="."; for d in ${TARGET_PATH//\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp $DESTINATION/; done; seg=""
else
  mkdir -p $DESTINATION/${TARGET_PATH}
fi

# copy the source into the target
rsync -arzq --protocol=28 ${SOURCE_PATH}/* $DESTINATION/${TARGET_PATH}/

# for JBT aggregates only: regenerate http://download.jboss.org/jbosstools/builds/nightly/*/*/composite*.xml files for up to 5 builds, cleaning anything older than 5 days old
if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]]; then
  if [[ ! -f jbosstools-cleanup.sh ]]; then 
    wget -q --no-check-certificate -N https://raw.github.com/jbosstools/jbosstools-build-ci/master/util/cleanup/jbosstools-cleanup.sh -O ${tmpdir}/jbosstools-cleanup.sh
  fi
  chmod +x ${tmpdir}/jbosstools-cleanup.sh
  ${tmpdir}/jbosstools-cleanup.sh --keep 5 --age-to-delete 5 --childFolderSuffix /repo/
fi

# store a copy of the build log in the target folder
wget -q --no-check-certificate -N https://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/jbosstools-base_master/lastBuild/consoleText -O ${tmpdir}/BUILDLOG.txt
rsync -arzq --protocol=28 ${tmpdir}/BUILDLOG.txt $DESTINATION/${TARGET_PATH}/

# purge temp folder
rm -fr ${tmpdir}