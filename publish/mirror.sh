#!/bin/bash
#
# this script is used in jbosstoolstargetplatformrequirements-mirror-matrix and jbosstools-requirements to create a mirror in http://download.jboss.org/jbosstools/updates/requirements/REQ_NAME/VERSION

# allow invoking this job to do nothing (if called from upstream job)
if [[ ${PUBLISH_PATH} != "DO_NOTHING" ]]; then 

  # path to JDK
  JDK_HOME=${NATIVE_TOOLS}${SEP}${JAVA11}
  # shorthand for rsync
  RSYNC="rsync -arzq --protocol=28"

  WORKDIR=${WORKSPACE}/updates/requirements/${REQ_NAME}; mkdir -p ${WORKDIR}/; cd ${WORKDIR}

  mkdir -p ${WORKSPACE}/tmp
  logFile=${WORKSPACE}/tmp/mirror.log.txt
  errFile=${WORKSPACE}/tmp/mirror.err.txt
  rm -f ${logFile} ${errFile}

  # get the mirror
  if [[ ${SOURCE_URL} ]]; then SOURCE_URL_PARAM="-DSRC_URL=${SOURCE_URL}"; else SOURCE_URL_PARAM=""; fi
  $M2_HOME/bin/mvn clean package -B -f ${WORKSPACE}/sources/mirror/pom.xml ${SOURCE_URL_PARAM} -DTARGET=${WORKDIR}/${VERSION} | tee ${logFile}

  if [[ -f ${logFile} ]]; then 
    echo "[INFO] Log file: ${logFile}"

    # check mirror log for failures
    errorMsgs="java.lang.reflect.InvocationTargetException"
    errorMsgs="${errorMsgs}/p;/Failed to transfer artifact canonical"
    errorMsgs="${errorMsgs}/p;/Validation found errors"
    errorMsgs="${errorMsgs}/p;/Cannot satisfy dependency"
    errorMsgs="${errorMsgs}/p;/Could not resolve content"
    errorMsgs="${errorMsgs}/p;/Connection refused"
    errorMsgs="${errorMsgs}/p;/Missing requirement"
    errorMsgs="${errorMsgs}/p;/No repository found"
    errorMsgs="${errorMsgs}/p;/No such file or directory"
    errorMsgs="${errorMsgs}/p;/Unable to read repository"
    errorMsgs="${errorMsgs}/p;/The following error occurred"
    errorMsgs="${errorMsgs}/p;/BUILD FAILURE"
    
    sed -n "{/${errorMsgs}/p}" ${logFile} > ${errFile}

    if [[ $(cat ${errFile}) ]]; then
      echo "[ERROR] The following errors have occurred while mirroring - must exit!"
      echo ""
      echo "========================================================================"
      echo ""
      cat ${errFile}
      echo ""
      echo "========================================================================"
      exit 1
    fi
  fi

  # publish to /builds/staging/${JOB_NAME}_${REQ_NAME}/${VERSION}
  DESTINATION="tools@filemgmt.jboss.org:/downloads_htdocs/tools"

  # optionally, publish to updates/requirements/${REQ_NAME}/ too
  if [[ ${VERSION} != "SNAPSHOT" ]]; then
    echo "${RSYNC} --rsh=ssh -e 'ssh -p 2222' --delete ${WORKDIR}/${VERSION} tools@filemgmt-prod-sync.jboss.org:/downloads_htdocs/tools/updates/requirements/${REQ_NAME}/"
    ${RSYNC} --rsh=ssh -e 'ssh -p 2222' --delete ${WORKDIR}/${VERSION} tools@filemgmt-prod-sync.jboss.org:/downloads_htdocs/tools/updates/requirements/${REQ_NAME}/
  fi

  # optionally, publish to updates/${PUBLISH_PATH}/${REQ_NAME} too
  if [[ ${PUBLISH_PATH} != "SNAPSHOT" ]]; then
    echo "mkdir ${PUBLISH_PATH}" | sftp ${DESTINATION}/updates
    echo "mkdir ${PUBLISH_PATH}/${REQ_NAME}" | sftp ${DESTINATION}/updates
    ${RSYNC} --rsh=ssh -e 'ssh -p 2222' --delete ${WORKDIR}/${VERSION} tools@filemgmt-prod-sync.jboss.org:/downloads_htdocs/tools/updates/${PUBLISH_PATH}/${REQ_NAME}/

    # regen composite metadata 
    chmod +x ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh
    ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh --dirs-to-scan "updates/${PUBLISH_PATH}/${REQ_NAME}" --regen-metadata-only --no-subdirs -DESTINATION tools@filemgmt-prod-sync.jboss.org:/downloads_htdocs/tools
  fi

  # cleanup
  rm -fr ${WORKSPACE}/tmp

fi

echo "New requirement site: http://download.jboss.org/jbosstools/updates/${PUBLISH_PATH}/${REQ_NAME}/${VERSION}/#new"
