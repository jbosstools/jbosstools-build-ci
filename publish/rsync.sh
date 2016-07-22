#!/bin/bash
# Script to rsync build artifacts from Jenkins to filemgmt or www.qa
# NOTE: sources should be checked out into ${WORKSPACE}/sources 

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools # or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio or /qa/services/http/binaries/RHDS

INCLUDES="*"
EXCLUDES=""

# defaults
numbuildstokeep=2
numbuildstolink=2
threshholdwhendelete=2 # in days
regenMetadataFlag=""; # set to ' -R' to suppress regenerating metadata entirely (no composite site will be produced)

# use this to pass in rsync flags
# eg., use --del -n to PREVIEW what obsolete files might be deleted from target folder while pushing new ones
# eg., use --del to delete from target folder while pushing new ones: USE WITH CAUTION!
RSYNCFLAGS="" 

# can be used to publish a build (including installers, site zips, MD5s, build log) or just an update site folder
usage ()
{
	echo "Usage  : $0 [-DESTINATION destination] -s source_path -t target_path"
	echo ""

	echo "To push a project build folder from Jenkins to staging:"
	echo "   $0 -s \${WORKSPACE}/sources/site/target/repository/ -t neon/snapshots/builds/\${JOB_NAME}/\${BUILD_TIMESTAMP}-B\${BUILD_NUMBER}/all/repo/"  # BUILD_TIMESTAMP=2015-02-17_17-57-54; 
	echo ""

	echo "To push JBT build + update site folders:"
	echo "   $0 -s \${WORKSPACE}/sources/aggregate/site/target/fullSite          -t neon/snapshots/builds/\${JOB_NAME}/\${BUILD_TIMESTAMP}-B\${BUILD_NUMBER}"
	echo "   $0 -s \${WORKSPACE}/sources/aggregate/site/target/fullSite/all/repo -t neon/snapshots/updates/core/\${stream} --del"
	echo ""

	echo "To push JBDS build + update site folders:"
	echo "   $0 -DESTINATION hudson@dev01.mw.lab.eng.bos.redhat.com:/qa/services/http/binaries/RHDS  -s \${WORKSPACE}/sources/results/target      -t 10.0/snapshots/builds/\${JOB_NAME}/all"
	echo "   $0 -DESTINATION devstudio@filemgmt.jboss.org:/www_htdocs/devstudio -e \*eap.jar         -s \${WORKSPACE}/sources/results/target      -t 10.0/snapshots/builds/\${JOB_NAME}/all"
	echo "   $0 -DESTINATION devstudio@filemgmt.jboss.org:/www_htdocs/devstudio                      -s \${WORKSPACE}/sources/results/target/repo -t 10.0/snapshots/updates/core/\${stream} --del"
	echo ""
	exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., /qa/services/http/binaries/RHDS
		'-s') SOURCE_PATH="$2"; shift 1;; # ${WORKSPACE}/sources/site/target/repository/
		'-t') TARGET_PATH="$2"; shift 1;; # neon/snapshots/builds/<job-name>/<build-number>/, neon/snapshots/updates/core/{4.4.0.Final, master}/
		'-i') INCLUDES="$2"; shift 1;;
		'-e') EXCLUDES="$2"; shift 1;;
		'-DBUILD_TIMESTAMP'|'-BUILD_TIMESTAMP') BUILD_TIMESTAMP="$2"; shift 1;; # does this work?
		'-DBUILD_ID'|'-BUILD_ID')         BUILD_ID="$2"; shift 1;;  # deprecated
		'-DBUILD_NUMBER'|'-BUILD_NUMBER') BUILD_NUMBER="$2"; shift 1;;
		'-DJOB_NAME'|'-JOB_NAME')         JOB_NAME="$2"; shift 1;;
		'-DWORKSPACE'|'-WORKSPACE')       WORKSPACE="$2"; shift 1;;
		'-d'|'--del') RSYNCFLAGS="${RSYNCFLAGS} --del"; shift 0;;
		'-k'|'--keep') numbuildstokeep="$2"; shift 1;;
		'-l'|'--link') numbuildstolink="$2"; shift 1;;
		'-a'|'--age-to-delete') threshholdwhendelete="$2"; shift 1;;
		'-R'|'--no-regen-metadata') regenMetadataFlag=" -R"; shift 0;;
		*) RSYNCFLAGS="${RSYNCFLAGS} $1"; shift 0;;
	esac
	shift 1
done
echo "[DEBUG] BUILD_TIMESTAMP = $BUILD_TIMESTAMP"
echo "[DEBUG] RSYNCFLAGS = $RSYNCFLAGS"

# build the target_path with sftp to ensure intermediate folders exist
if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
	seg="."; for d in ${TARGET_PATH//\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp $DESTINATION/; done; seg=""
else
	mkdir -p $DESTINATION/${TARGET_PATH}
fi

# copy the source into the target
if [[ ${EXCLUDES} ]]; then
	echo "[INFO] rsync -arzq --protocol=28 ${RSYNCFLAGS} --exclude=${EXCLUDES} ${SOURCE_PATH}/${INCLUDES} $DESTINATION/${TARGET_PATH}/"
		    rsync -arzq --protocol=28 ${RSYNCFLAGS} --exclude=${EXCLUDES} ${SOURCE_PATH}/${INCLUDES} $DESTINATION/${TARGET_PATH}/
else
	echo "[INFO] rsync -arzq --protocol=28 ${RSYNCFLAGS} ${SOURCE_PATH}/${INCLUDES} $DESTINATION/${TARGET_PATH}/"
		    rsync -arzq --protocol=28 ${RSYNCFLAGS} ${SOURCE_PATH}/${INCLUDES} $DESTINATION/${TARGET_PATH}/
fi

# given  TARGET_PATH=/downloads_htdocs/tools/neon/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master/2015-03-06_17-58-07-B13/all/repo/
# return PARENT_PATH=neon/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master
# given  TARGET_PATH=10.0/snapshots/builds/devstudio.product_master/2015-07-16_00-00-00-B69/all
# return PARENT_PATH=10.0/snapshots/builds/devstudio.product_master
PARENT_PATH=$(echo $TARGET_PATH | sed -e "s#/\?downloads_htdocs/tools/##" -e "s#/\?www_htdocs/devstudio/##" -e "s#/\?qa/services/http/binaries/RHDS/##" -e "s#/\?all/repo/\?##" -e "s#/\?all/\?##" -e "s#/\$##" -e "s#^/##" -e "s#\(.\+\)/[^/]\+#\1#")
# if TARGET_PATH contains a BUILD_TIMESTAMP-B# folder (or, previously / deprecated, a BUILD_ID-B# folder),
# create symlink: jbosstools-build-sites.aggregate.earlyaccess-site_master/latest -> jbosstools-build-sites.aggregate.earlyaccess-site_master/${BUILD_TIMESTAMP}-B${BUILD_NUMBER}
BUILD_DIR=$(echo ${TARGET_PATH#${PARENT_PATH}/} | sed -e "s#/\?all/repo/\?##" -e "s#/\?all/\?##")
if [[ ${BUILD_NUMBER} ]] && [[ ${BUILD_DIR} ]] && [[ ${BUILD_DIR%B${BUILD_NUMBER}} != ${BUILD_DIR} ]]; then 
	echo "[DEBUG] Symlink[0] ${DESTINATION}/${PARENT_PATH}/latest -> ${BUILD_DIR}"
	pushd $tmpdir >/dev/null; ln -s ${BUILD_DIR} latest; rsync --protocol=28 -l latest ${DESTINATION}/${PARENT_PATH}/; rm -f latest; popd >/dev/null
elif [[ ${BUILD_TIMESTAMP} ]] && [[ ${BUILD_NUMBER} ]] && [[ ${TARGET_PATH/${BUILD_TIMESTAMP}-B${BUILD_NUMBER}} != ${TARGET_PATH} ]]; then
	echo "[DEBUG] Symlink[1] ${DESTINATION}/${PARENT_PATH}/latest -> ${BUILD_TIMESTAMP}-B${BUILD_NUMBER}"
	pushd $tmpdir >/dev/null; ln -s ${BUILD_TIMESTAMP}-B${BUILD_NUMBER} latest; rsync --protocol=28 -l latest ${DESTINATION}/${PARENT_PATH}/; rm -f latest; popd >/dev/null
elif [[ ${BUILD_ID} ]] && [[ ${BUILD_NUMBER} ]] && [[ ${TARGET_PATH/${BUILD_ID}-B${BUILD_NUMBER}} != ${TARGET_PATH} ]]; then
	echo "[DEBUG] Symlink[2] ${DESTINATION}/${PARENT_PATH}/latest -> ${BUILD_ID}-B${BUILD_NUMBER}"
	pushd $tmpdir >/dev/null; ln -s ${BUILD_ID}-B${BUILD_NUMBER} latest; rsync --protocol=28 -l latest ${DESTINATION}/${PARENT_PATH}/; rm -f latest; popd >/dev/null
fi

# for published builds on download.jboss.org ONLY!
# regenerate http://download.jboss.org/jbosstools/builds/${TARGET_PATH}/composite*.xml files for up to 5 builds, cleaning anything older than 5 days old
if [[ ${WORKSPACE} ]] && [[ -f ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh ]]; then
	if [[ ${TARGET_PATH/builds\//} != ${TARGET_PATH} ]] || [[ ${TARGET_PATH/pulls\//} != ${TARGET_PATH} ]]; then
		# given neon/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master return neon/snapshots/builds
		PARENT_PARENT_PATH=$(echo $PARENT_PATH | sed -e "s#\(.\+\)/[^/]\+#\1#")
		chmod +x ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh
		# given above, ${PARENT_PATH#${PARENT_PARENT_PATH}/} returns last path segment jbosstools-build-sites.aggregate.earlyaccess-site_master
		${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh -k ${numbuildstokeep} -l ${numbuildstolink} -a ${threshholdwhendelete} -S /all/repo/ -d ${PARENT_PARENT_PATH} -i ${PARENT_PATH#${PARENT_PARENT_PATH}/} -DESTINATION ${DESTINATION} ${regenMetadataFlag}
	fi
fi

wgetParams="--timeout=900 --wait=10 --random-wait --tries=10 --retry-connrefused --no-check-certificate -q"
getRemoteFile ()
{
	# requires $wgetParams and $tmpdir to be defined (above)
	getRemoteFileReturn=""
	grfURL="$1"
	mkdir -p ${tmpdir}
	output=$(mktemp --tmpdir=${tmpdir} getRemoteFile.XXXXXX)
	if [[ ! `wget ${wgetParams} ${grfURL} -O ${output} 2>&1 | egrep "ERROR 404"` ]]; then # file downloaded
		getRemoteFileReturn=${output}
	else
		getRemoteFileReturn=""
		rm -f ${output}
	fi
}

# store a copy of this build's log in the target folder (if JOB_NAME is defined)
if [[ ${JOB_NAME} ]]; then 
	bl=${tmpdir}/BUILDLOG.txt
	getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/${BUILD_NUMBER}/consoleText"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${bl}; fi
	touch ${bl}; chmod 664 ${bl}; rsync -arzq --protocol=28 ${bl} $DESTINATION/${TARGET_PATH/\/all\/repo/}/logs/
fi

# purge temp folder
rm -fr ${tmpdir} 
