#!/bin/bash
#
# this script is used in jbosstoolstargetplatformrequirements-mirror-matrix and jbosstools-requirements to create a mirror in http://download.jboss.org/jbosstools/updates/requirements/REQ_NAME/VERSION

# allow invoking this job to do nothing (if called from upstream job)
if [[ ${PUBLISH_PATH} != "DO_NOTHING" ]]; then 

  # Jenkins-specific variables
  # where to store downloaded Eclipse zips
  ECLIPSEDIR=/home/hudson/static_build_env/jbds/tools/sources
  # path to JDK8
  JDK8=${NATIVE_TOOLS}${SEP}jdk1.8.0_last
  # shorthand for rsync
  RSYNC="rsync -arzq --protocol=28"

  WORKDIR=${WORKSPACE}/updates/requirements/${REQ_NAME}; mkdir -p ${WORKDIR}/; cd ${WORKDIR}

  # get the build scripts
  ${RSYNC} --delete ${WORKSPACE}/sources/jbosstools/updates/requirements/* ${WORKSPACE}/updates/requirements/

  # if running on 32-bit slave
  if [[ ! `uname -a | grep 64` ]]; then ECLIPSE=${ECLIPSE/-x86_64/}; fi

  # get https://www.eclipse.org/downloads/download.php?r=1&file=/technology/epp/downloads/release/luna/SR1/eclipse-jee-luna-SR1-linux-gtk-x86_64.tar.gz
  # if plugins folder doesn't exist, unpack Eclipse to ${WORKSPACE}/eclipse
  if [[ ! -d ${WORKSPACE}/eclipse/plugins/ ]]; then
    pushd ${WORKSPACE}
      # if we don't have this Eclipse, get it
      if [[ ! -f ${ECLIPSEDIR}/${ECLIPSE##*/} ]]; then wget -nc -q ${ECLIPSE} -O ${ECLIPSEDIR}/${ECLIPSE##*/}; fi
      # then unpack it
      tar xzf ${ECLIPSEDIR}/${ECLIPSE##*/}
    popd
  fi

  # put a copy of ant-contrib.jar in ${WORKDIR}/..
  if [[ $(grep ant-contrib ${SCRIPTNAME}) ]]; then
    M2_HOME=/qa/tools/opt/apache-maven-3.2.5/
    $M2_HOME/bin/mvn dependency:copy -DtrimVersion=true -Dmdep.stripClassifier=true -Dmdep.stripVersion=true -DoutputDirectory=${WORKSPACE}/updates/requirements/ -Dartifact=ant-contrib:ant-contrib:1.0b3:jar
  fi

  # get the mirror
  if [[ ${SOURCE_URL} ]]; then
    date; ${JDK8}/bin/java -cp ${WORKSPACE}/eclipse/plugins/org.eclipse.equinox.launcher_*.jar \
        org.eclipse.equinox.launcher.Main -consoleLog -nosplash -data ${WORKSPACE}/tmp -application org.eclipse.ant.core.antRunner -f ${SCRIPTNAME} -Dversion=${VERSION} -DURL=${SOURCE_URL} ${TASK}
  else
    date; ${JDK8}/bin/java -cp ${WORKSPACE}/eclipse/plugins/org.eclipse.equinox.launcher_*.jar \
        org.eclipse.equinox.launcher.Main -consoleLog -nosplash -data ${WORKSPACE}/tmp -application org.eclipse.ant.core.antRunner -f ${SCRIPTNAME} -Dversion=${VERSION} ${TASK}
  fi

  # publish to /builds/staging/${JOB_NAME}_${REQ_NAME}/${VERSION}
  DESTINATION="tools@filemgmt.jboss.org:/downloads_htdocs/tools"
  date

  # deprecated: only for non-requirements releases 
  # if [[ ${PUBLISH_PATH} != "requirements" ]]; then
  #   ${RSYNC} --delete ${WORKDIR}/${VERSION} ${DESTINATION}/builds/staging/${JOB_NAME}_${REQ_NAME}/
  #   ${RSYNC} ${WORKDIR}/${SCRIPTNAME} ${DESTINATION}/builds/staging/${JOB_NAME}_${REQ_NAME}/
  # fi

  # optionally, publish to updates/requirements/${REQ_NAME}/ too
  if [[ ${VERSION} != "SNAPSHOT" ]]; then
    date
    ${RSYNC} --delete ${WORKDIR}/${VERSION} ${DESTINATION}/updates/requirements/${REQ_NAME}/
  fi

  # optionally, publish to updates/${PUBLISH_PATH}/${REQ_NAME} too
  if [[ ${PUBLISH_PATH} != "SNAPSHOT" ]]; then
    date
    echo "mkdir ${PUBLISH_PATH}" | sftp ${DESTINATION}/updates
    echo "mkdir ${PUBLISH_PATH}/${REQ_NAME}" | sftp ${DESTINATION}/updates
    ${RSYNC} --delete ${WORKDIR}/${VERSION} ${DESTINATION}/updates/${PUBLISH_PATH}/${REQ_NAME}/

    # regen composite metadata 
    chmod +x ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh
    ${WORKSPACE}/sources/util/cleanup/jbosstools-cleanup.sh --dirs-to-scan "updates/${PUBLISH_PATH}/${REQ_NAME}" --regen-metadata-only --no-subdirs
  fi

  date
  # cleanup
  rm -fr ${WORKSPACE}/eclipse
  rm -fr ${WORKSPACE}/tmp

fi

echo "New requirement site: http://download.jboss.org/jbosstools/updates/${PUBLISH_PATH}/${REQ_NAME}/${VERSION}/#new"
