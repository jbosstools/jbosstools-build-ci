#!/bin/bash
# Script to sync build artifacts from Jenkins to filemgmt using sftp
# NOTE: sources should be checked out into ${WORKSPACE}/sources 

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir
logfile=${tmpdir}/${JOB_BASE_NAME}.log.txt

DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools

INCLUDES=""

# defaults
numbuildstokeep=2
numbuildstolink=2
threshholdwhendelete=2 # in days
regenMetadataFlag=""; # set to ' -R' to suppress regenerating metadata entirely (no composite site will be produced)
regenMetadataForce=0

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
	echo "   $0 -s \${WORKSPACE}/sources/aggregate/site/target/fullSite/all/repo -t neon/snapshots/updates/core/\${stream}"
	echo ""

	exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., /home/windup/apache2/www/html/rhd/devstudio
		'-s') SOURCE_PATH="$2"; shift 1;; # ${WORKSPACE}/sources/site/target/repository/
		'-t') TARGET_PATH="$2"; shift 1;; # neon/snapshots/builds/<job-name>/<build-number>/, neon/snapshots/updates/core/{4.4.0.Final, master}/
		'-i') INCLUDES="$2"; shift 1;;
		'-DBUILD_TIMESTAMP'|'-BUILD_TIMESTAMP') BUILD_TIMESTAMP="$2"; shift 1;; # does this work?
		'-DBUILD_NUMBER'|'-BUILD_NUMBER') BUILD_NUMBER="$2"; shift 1;;
		'-DJOB_NAME'|'-JOB_NAME')         JOB_NAME="$2"; shift 1;;
		'-DWORKSPACE'|'-WORKSPACE')       WORKSPACE="$2"; shift 1;;
		'-k'|'--keep') numbuildstokeep="$2"; shift 1;;
		'-l'|'--link') numbuildstolink="$2"; shift 1;;
		'-a'|'--age-to-delete') threshholdwhendelete="$2"; shift 1;;
		'-R'|'--no-regen-metadata') regenMetadataForce=0;  regenMetadataFlag=" -R"; shift 0;;
		'-FR'|'--force-regen-metadata') regenMetadataForce=1; regenMetadataFlag=""; shift 0;;
	esac
	shift 1
done

# compute BUILD_TIMESTAMP from TARGET_PATH if not set, or if set but contains spaces or colons (an invalid date)
# if set, must be in this format: date -u +%Y-%m-%d_%H-%M-%S
if [[ ${TARGET_PATH} ]]; then
	if [[ ! ${BUILD_TIMESTAMP} ]] || [[ ${BUILD_TIMESTAMP// /} != ${BUILD_TIMESTAMP} ]] || [[ ${BUILD_TIMESTAMP//:/} != ${BUILD_TIMESTAMP} ]]; then
		BUILD_TIMESTAMP=${TARGET_PATH}
		BUILD_TIMESTAMP=${BUILD_TIMESTAMP%/all*}; # trim trailing slash if any
		BUILD_TIMESTAMP=${BUILD_TIMESTAMP%/repo*}; # trim trailing slash if any
		BUILD_TIMESTAMP=${BUILD_TIMESTAMP%/}; # trim trailing slash if any
		BUILD_TIMESTAMP=${BUILD_TIMESTAMP##*/}; # trim up to and including prefix slashes
		BUILD_TIMESTAMP=${BUILD_TIMESTAMP%-B*}; # trim off the -B### build number
	fi
fi

echo "[DEBUG] BUILD_TIMESTAMP = $BUILD_TIMESTAMP"

# build the target_path with sftp to ensure intermediate folders exist
if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
	seg="."; for d in ${TARGET_PATH//\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp -q $DESTINATION/; done; seg=""
else
	mkdir -p $DESTINATION/${TARGET_PATH}
fi

# copy the source into the target
echo "[INFO] sftp ${SOURCE_PATH}/${INCLUDES} into $DESTINATION/${TARGET_PATH}..."
mkdir -p ${tmpdir}/${BUILD_TIMESTAMP}/${TARGET_PATH}
pushd $tmpdir >/dev/null; cd ${SOURCE_PATH}; cp -r ./ ${tmpdir}/${BUILD_TIMESTAMP}/${TARGET_PATH}; cd ${tmpdir}/${BUILD_TIMESTAMP}/${TARGET_PATH}; (echo "put -rp ./${INCLUDES}"; echo quit)|sftp -Cqrp $DESTINATION/${TARGET_PATH}; popd >/dev/null

# given  TARGET_PATH=/downloads_htdocs/tools/neon/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master/2015-03-06_17-58-07-B13/all/repo/
# return PARENT_PATH=neon/snapshots/builds/jbosstools-build-sites.aggregate.earlyaccess-site_master
# given  TARGET_PATH=10.0/snapshots/builds/devstudio.product_master/2015-07-16_00-00-00-B69/all
# return PARENT_PATH=10.0/snapshots/builds/devstudio.product_master
# given  TARGET_PATH=10.0/snapshots/builds/devstudio.rpm_10.0.neon/2016-09-21_05-50-B28/x86_64
# return PARENT_PATH=10.0/snapshots/builds/devstudio.rpm_10.0.neon
PARENT_PATH=$(echo $TARGET_PATH | sed -e "s#/\?downloads_htdocs/tools/##" -e "s#/\?www_htdocs/devstudio/##" \
-e "s#/\?qa/services/http/binaries/RHDS/##" \
-e "s#/\?qa/services/http/binaries/devstudio/##" \
-e "s#/\?home/windup/apache2/www/html/rhd/devstudio/##" \
-e "s#/\?all/repo/\?##" -e "s#/\?all/\?##" -e "s#/\$##" -e "s#^/##" -e "s#\(.\+\)/[^/]\+#\1#" -e "s#/\?${BUILD_TIMESTAMP}-B${BUILD_NUMBER}/\?##")
# if TARGET_PATH contains a BUILD_TIMESTAMP-B# folder,
# create symlink: jbosstools-build-sites.aggregate.earlyaccess-site_master/latest -> jbosstools-build-sites.aggregate.earlyaccess-site_master/${BUILD_TIMESTAMP}-B${BUILD_NUMBER}
if [[ ${BUILD_NUMBER} ]]; then
	if [[ ${BUILD_TIMESTAMP} ]] && [[ ${TARGET_PATH/${BUILD_TIMESTAMP}-B${BUILD_NUMBER}} != ${TARGET_PATH} ]]; then
		echo "[DEBUG] Symlink[BT] ${DESTINATION}/${PARENT_PATH}/latest -> ${BUILD_TIMESTAMP}-B${BUILD_NUMBER}"
		pushd $tmpdir >/dev/null
		echo "chdir latest" | sftp -q $DESTINATION/${PARENT_PATH}/ &>${logfile} | tee ${logfile}
  		if ! grep -q "No such file or directory" ${logfile}; then
  			echo -e "rm latest" | sftp -Cpq $DESTINATION/${PARENT_PATH}/
  		fi
		(echo "cd ${PARENT_PATH}/"; echo ln -s ${BUILD_TIMESTAMP}-B${BUILD_NUMBER}/ latest)|sftp -Cp $DESTINATION
		rm ${logfile}
		popd >/dev/null
	else
		BUILD_DIR=$(echo ${TARGET_PATH#${PARENT_PATH}/} | sed -e "s#/\?all/repo/\?##" -e "s#/\?all/\?##")
		if [[ ${BUILD_DIR} ]] && [[ ${BUILD_DIR%B${BUILD_NUMBER}} != ${BUILD_DIR} ]] && [[ ${TARGET_PATH/${BUILD_DIR}} != ${TARGET_PATH} ]]; then
			echo "[DEBUG] Symlink[BD] ${DESTINATION}/${PARENT_PATH}/latest -> ${BUILD_DIR}"
			pushd $tmpdir >/dev/null
			echo "chdir latest" | sftp -q $DESTINATION/${PARENT_PATH}/ &>${logfile} | tee ${logfile} 
  			if ! grep -q "No such file or directory" ${logfile}; then
  				echo -e "rm latest" | sftp -Cpq $DESTINATION/${PARENT_PATH}/
  			fi
			(echo "cd ${PARENT_PATH}/"; echo ln -s ${BUILD_DIR}/ latest)|sftp -Cp $DESTINATION
			rm ${logfile}
			popd >/dev/null
		fi	
	fi
else
	echo "[DEBUG] Symlink[BN] ${DESTINATION}/${PARENT_PATH}/latest not updated; BUILD_NUMBER not set."
fi

# for published builds on download.jboss.org ONLY!
# regenerate https://download.jboss.org/jbosstools/builds/${TARGET_PATH}/composite*.xml files for up to 5 builds, cleaning anything older than 5 days old
if [[ ${WORKSPACE} ]] && [[ -f ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh ]]; then
	if [[ ${regenMetadataForce} -eq 1 ]] || [[ ${TARGET_PATH/builds\//} != ${TARGET_PATH} ]] || [[ ${TARGET_PATH/pulls\//} != ${TARGET_PATH} ]]; then
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
	output=$(mktemp -p ${tmpdir} getRemoteFile.XXXXXX)
	if [[ ! `wget ${wgetParams} ${grfURL} -O ${output} 2>&1 | egrep "ERROR 404"` ]]; then # file downloaded
		getRemoteFileReturn=${output}
	else
		getRemoteFileReturn=""
		rm -f ${output}
	fi
}

# store a copy of this build's log in the target folder (if JOB_NAME is defined)
if [[ ${JOB_NAME} ]] && [[ ${JOB_URL} ]]; then
	bl=${tmpdir}/BUILDLOG.txt
	getRemoteFile "${JOB_URL}/${BUILD_NUMBER}/consoleText"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${bl}; fi
	pushd $tmpdir >/dev/null; echo -e "mkdir logs" | sftp -Cpq $DESTINATION/${TARGET_PATH}; popd >/dev/null
	pushd $tmpdir >/dev/null; touch ${bl}; chmod 664 ${bl}; (echo "put ${bl}"; echo quit)|sftp -Cpq $DESTINATION/${TARGET_PATH}/logs/; popd >/dev/null
fi

# purge temp folder
rm -fr ${tmpdir} 
