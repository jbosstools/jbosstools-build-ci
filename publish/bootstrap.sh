#!/bin/bash
#
#  bootstrap sites using previous release's content

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=/tmp; fi

eclipseReleaseName_PREV=neon
devstudioReleaseVersion_PREV=10.0
eclipseReleaseName=oxygen
devstudioReleaseVersion=11

TOOLS=tools@10.5.105.197:/downloads_htdocs/tools
JBDS=devstudio@10.5.105.197:/www_htdocs/devstudio

RSYNC="rsync -aPrz --rsh=ssh --protocol=28"

cloneSite () {
    url_check=${url_prefix}/${qual}/updates/${site}/${stream_jbt}/
    doesNotExist="$(curl -s -I ${url_check}/index.html | egrep "404 Not Found")"
    if [[ ${doesNotExist} != "" ]]; then 
      echo "[INFO]  404'd: ${url_check}"
      if [[ ${url_prefix} == "https://devstudio.redhat.com/"* ]]; then
        DESTINATION=${JBDS}
        SOURCE_PATH=${devstudioReleaseVersion_PREV}/${qual}/updates/${site}/${stream_jbt}
        TARGET_PATH=${devstudioReleaseVersion}/${qual}/updates/${site}/${stream_jbt}
      elif [[ ${url_prefix} == "https://download.jboss.org/jbosstools/"* ]]; then
        DESTINATION=${TOOLS}
        SOURCE_PATH=${eclipseReleaseName_PREV}/${qual}/updates/${site}/${stream_jbt}
        TARGET_PATH=${eclipseReleaseName}/${qual}/updates/${site}/${stream_jbt}
      else 
        echo "[ERROR] No DESTINATION defined. Cannot create ${url_check}"
        exit 1
      fi
      SOURCE_DIR=${WORKSPACE}/${SOURCE_PATH}; mkdir -p ${SOURCE_DIR}
      seg="."; for d in ${TARGET_PATH//\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp $DESTINATION/; done; seg=""
      ${RSYNC} ${DESTINATION}/${SOURCE_PATH}/* ${SOURCE_DIR}/
      # build the target_path with sftp to ensure intermediate folders exist
      ${RSYNC} ${SOURCE_DIR}/* ${DESTINATION}/${TARGET_PATH}/
      
      echo "${RSYNC} -DESTINATION ${DESTINATION} -s ${SOURCE_PATH} -t ${TARGET_PATH} --no-regen-metadata"
      echo "[INFO] Created: ${url_check}"
    else
      echo "[INFO]   Found: ${url_check}"
    fi
}

for url_prefix in https://devstudio.redhat.com/${devstudioReleaseVersion}; do
  for qual in snapshots; do
    for site in core central earlyaccess; do
      for stream_jbt in master; do
      	cloneSite &
      done
    done
  done
done

for url_prefix in https://download.jboss.org/jbosstools/${eclipseReleaseName}; do
  for qual in snapshots; do
    for site in core central earlyaccess coretests integration-tests; do
      for stream_jbt in master; do
      	cloneSite &
      done
    done
  done
done

wait
