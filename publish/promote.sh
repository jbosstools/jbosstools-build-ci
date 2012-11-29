#!/bin/bash
# Hudson script used to promote a nightly snapshot build to development milestone or stable release.

# defaults
OPERATION=COPY # or MOVE
DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools # or /qa/services/http/binaries/RHDS
URL=http://download.jboss.org/jbosstools # or http://www.qa.jboss.com/binaries/RHDS
RELEASE_TYPE=updates # or discovery
BUILD_TYPE=nightly
TARGET_PLATFORM=
PARENT_FOLDER=core # or soa-tooling
PROJECT_NAME=
TARGET_FOLDER=
SOURCE_PATH=

if [[ $# -lt 1 ]]; then
  echo "Usage  : $0 [-DESTINATION destination] [-RELEASE_TYPE release_type] -BUILD_TYPE build_type -TARGET_PLATFORM target_platform -PROJECT_NAME project_name -TARGET_FOLDER target_folder -SOURCE_PATH source_path"
  # push to http://download.jboss.org/jbosstools/updates/integration/kepler/base/as_4.1.kepler/
  echo "Example: $0 -BUILD_TYPE integration -TARGET_PLATFORM kepler -PROJECT_NAME base -TARGET_FOLDER as_4.1.kepler -SOURCE_PATH jbosstools-4.1_stable_branch.component--as/all/repo"
  # push to http://download.jboss.org/jbosstools/updates/integration/kepler/base/archives_4.1.kepler/
  echo "Example: $0 -BUILD_TYPE integration -TARGET_PLATFORM kepler -PROJECT_NAME base -TARGET_FOLDER archives_4.1.kepler -SOURCE_PATH jbosstools-4.1_stable_branch.component--archives/all/repo"
  # push to http://download.jboss.org/jbosstools/updates/integration/kepler/base/jmx_4.1.kepler/
  echo "Example: $0 -BUILD_TYPE integration -TARGET_PLATFORM kepler -PROJECT_NAME base -TARGET_FOLDER jmx_4.1.kepler -SOURCE_PATH jbosstools-4.1_stable_branch.component--jmx/all/repo"
  echo ""
  # push to http://download.jboss.org/jbosstools/updates/development/juno/soa-tooling/modeshape/3.0.0.CR1/
  echo "Example: $0 -BUILD_TYPE development -TARGET_PLATFORM juno -PARENT_FOLDER soa-tooling -PROJECT_NAME modeshape -TARGET_FOLDER 3.3.0.CR1 -SOURCE_PATH modeshape-tools-continuous/all/repo"
  # push to http://download.jboss.org/jbosstools/updates/stable/indigo/soa-tooling/switchyard/0.6.0.Final/
  echo "Example: $0 -BUILD_TYPE stable -TARGET_PLATFORM indigo -PARENT_FOLDER soa-tooling -PROJECT_NAME switchyard -TARGET_FOLDER 0.6.0.Final -SOURCE_PATH SwitchYard-Tools/eclipse"
  echo ""
  # push to http://download.jboss.org/jbosstools/discovery/nightly/core/trunk/jbosstools-directory.xml
  echo "Example: $0 -RELEASE_TYPE discovery -PARENT_FOLDER core -TARGET_FOLDER trunk -SOURCE_PATH ${WORKSPACE}/sources/discovery/core/org.jboss.tools.central.discovery/target/discovery-site/"
  # push to http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/4.1.kepler/devstudio-directory.xml
  echo "Example: $0 -DESTINATION /qa/services/http/binaries/RHDS -URL http://www.qa.jboss.com/binaries/RHDS -RELEASE_TYPE discovery -PARENT_FOLDER core -TARGET_FOLDER 4.1.kepler -SOURCE_PATH ${WORKSPACE}/sources/discovery/core/com.jboss.jbds.central.discovery/target/discovery-site/"
  exit 1
fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., /qa/services/http/binaries/RHDS
    '-URL') URL="$2"; shift 1;; # override for JBDS publishing, eg., http://www.qa.jboss.com/binaries/RHDS
    '-RELEASE_TYPE') RELEASE_TYPE="$2"; shift 1;; # updates, discovery
    '-BUILD_TYPE') BUILD_TYPE="$2"; shift 1;; # nightly, integration, development or stable
    '-TARGET_PLATFORM') TARGET_PLATFORM="$2"; shift 1;; # indigo, juno, kepler, ...
    '-PARENT_FOLDER') PARENT_FOLDER="$2"; shift 1;; # soa-tooling, core
    '-PROJECT_NAME') PROJECT_NAME="$2"; shift 1;; # switchyard, modeshape, droolsjbpm, ...
    '-TARGET_FOLDER') TARGET_FOLDER="$2"; shift 1;; # 0.5.0.Beta3, 0.6.0.Final, ...
    '-SOURCE_PATH') SOURCE_PATH="$2"; shift 1;; # jbosstools-4.0_stable_branch.component--as/all/repo, modeshape-tools-continuous/all/repo, SwitchYard-Tools/eclipse
  esac
  shift 1
done

if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
  echo "mkdir ${BUILD_TYPE}" | sftp ${DESTINATION}/${RELEASE_TYPE}/
  if [[ ${TARGET_PLATFORM} ]]; then
    echo "mkdir ${BUILD_TYPE}/${TARGET_PLATFORM}" | sftp ${DESTINATION}/${RELEASE_TYPE}/
  fi
  if [[ ${PARENT_FOLDER} ]]; then
    echo "mkdir ${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}" | sftp ${DESTINATION}/${RELEASE_TYPE}/
  fi
  if [[ ${PROJECT_NAME} ]]; then
    echo "mkdir ${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME}" | sftp ${DESTINATION}/${RELEASE_TYPE}/
  fi
else
  mkdir -p ${DESTINATION}/${RELEASE_TYPE}/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME}
fi

if [[ ${TARGET_FOLDER} ]]; then
  if [[ ${OPERATION} ==  "MOVE" ]]; then
    if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
      echo -e "rename builds/staging/${SOURCE_PATH} updates/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME}/${TARGET_FOLDER}" | sftp ${DESTINATION}/
    else
      if [[ -d builds/staging/${SOURCE_PATH} ]]; then
        pushd ${DESTINATION} >/dev/null
        mv builds/staging/${SOURCE_PATH} updates/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME}/${TARGET_FOLDER}
        popd >/dev/null
      else
        echo "Cannot move builds/staging/${SOURCE_PATH} - dir does not exist!"; exit 1;
      fi
    fi
  else
    # purge existing workspace folder to ensure we're not combining releases
    if [[ ${WORKSPACE} ]] && [[ -d ${WORKSPACE}/${JOB_NAME} ]]; then rm -fr ${WORKSPACE}/${JOB_NAME}/; fi
    if [[ -d ${SOURCE_PATH} ]]; then # use local source path in workspace
      rsync -arzq ${SOURCE_PATH}/* ${WORKSPACE}/${JOB_NAME}/
    else
      rsync -arzq --protocol=28 ${DESTINATION}/builds/staging/${SOURCE_PATH}/* ${WORKSPACE}/${JOB_NAME}/
    fi
    rsync -arzq --protocol=28 --delete ${WORKSPACE}/${JOB_NAME}/* ${DESTINATION}/${RELEASE_TYPE}/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME}/${TARGET_FOLDER}/
  fi
  echo "Site promoted by ${OPERATION} to: ${URL}/${RELEASE_TYPE}/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME}/${TARGET_FOLDER}/"
fi
if [[ ${RELEASE_TYPE} == "updates" ]]; then
  # JBIDE-12662: regenerate composite metadata in updates/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}/${PROJECT_NAME} folder for all children
  wget -q --no-check-certificate -N https://raw.github.com/jbosstools/jbosstools-build-ci/master/util/cleanup/jbosstools-cleanup.sh
  chmod +x jbosstools-cleanup.sh
  ./jbosstools-cleanup.sh --dirs-to-scan "updates/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}" --regen-metadata-only
  rm -f jbosstools-cleanup.sh
fi
