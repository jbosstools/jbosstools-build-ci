#!/bin/bash
# migrate a job from one Jenkins to another


# where you have https://github.com/jbdevstudio/jbdevstudio-ci checked out`
jbdevstudio_ci_folder=${HOME}/truu/jbdevstudio-ci

# job to copy
SOURCE_JOB_NAME=""
TARGET_JOB_NAME=""

# jenkins variables
# # example one: migate releng jobs from Bos MW to CCI Jenkins
SOURCE_JENKINS="jenkins.hosts.mwqe.eng.bos.redhat.com/hudson"
SOURCE_PATH="view/DevStudio/view/jbosstools-releng"
TARGET_JENKINS="dev-platform-jenkins.rhev-ci-vms.eng.rdu2.redhat.com"
TARGET_PATH="view/Devstudio/view/jbosstools-releng"

# # example one: clone JDK 9 jobs to JDK 11 jobs
SOURCE_JENKINS="dev-platform-jenkins.rhev-ci-vms.eng.rdu2.redhat.com"
SOURCE_PATH="view/Devstudio/view/jdkNext"
TARGET_JENKINS="dev-platform-jenkins.rhev-ci-vms.eng.rdu2.redhat.com"
TARGET_PATH="view/Devstudio/view/jdkNext"

# string replacements to apply to the destination version of the job
assignedNode="rhel7-devstudio-releng" # new node to use
jdk="openjdk-1.8"
mavenName="maven-3.5.4"
groovyName="groovy-2.4.3"
forceOverwriteDestinationJob=0

usage ()
{
  echo "Usage  : $0 -s source_path/ -t target_path/ -js source_job_name [-jt target_job_name]"
  echo ""
  echo "Example: $0 -s view/DevStudio/view/jbosstools-releng/   -t view/Devstudio/view/jbosstools-releng/ \\"
  echo "  -js jbosstools-releng-push-to-staging-01-check-versions-branches-root-poms"
  echo "Example: $0 -s view/DevStudio/view/DevStudio_Master/    -t view/Devstudio/view/devstudio_master/    -js jbosstools-cleanup"
  echo "Example: $0 -s view/DevStudio/view/devstudio_10.0.neon/ -t view/Devstudio/view/devstudio_10.0.neon/ -js jbosstools-build-ci_4.4.neon"
  echo ""
  echo "Matrix example: "
  echo "  First, create a new dummy Multi-configuration project job on the server"
  echo "  Then: "
  echo "    $0 -s view/DevStudio/view/Installation-Tests/ \\"
  echo "      -t view/Devstudio/view/devstudio_installation_tests/ \\"
  echo "      -js jbosstools-install-grinder.install-tests.matrix_4.4.neon -F"
  echo ""
  echo "Job copy example: "
  echo "    $0 -sj dev-platform-jenkins.rhev-ci-vms.eng.rdu2.redhat.com -tj dev-platform-jenkins.rhev-ci-vms.eng.rdu2.redhat.com \\"
  echo "       -s view/Devstudio/view/jdkNext/ -t view/Devstudio/view/jdkNext/ \\"
  echo "       -js jbosstools-javaee-jdk9_master -jt jbosstools-javaee-jdk11_master \\"
  echo "       -jdk jdk11"
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-f') jbdevstudio_ci_folder="$2"; shift 1;;

    '-js') SOURCE_JOB_NAME="$2"; shift 1;;
    '-jt') TARGET_JOB_NAME="$2"; shift 1;;

    '-s') SOURCE_PATH="$2"; shift 1;; # ${WORKSPACE}/sources/site/target/repository/
    '-t') TARGET_PATH="$2"; shift 1;; # neon/snapshots/builds/<job-name>/<build-number>/, neon/snapshots/updates/core/{4.4.0.Final, master}/
    '-sj') SOURCE_JENKINS="$2"; shift 1;;
    '-tj') TARGET_JENKINS="$2"; shift 1;;

    '-assignedNode') assignedNode=="$2"; shift 1;;
    '-mavenName')    mavenName=="$2"; shift 1;;
    '-groovyName')   groovyName=="$2"; shift 1;;
    '-jdk')          jdk=="$2"; shift 1;;
    '-F')            forceOverwriteDestinationJob=1; shift 0;;
  esac
  shift 1
done

if [[ ! ${SOURCE_JOB_NAME} ]]; then usage; fi

if [[ ! ${TARGET_JOB_NAME} ]]; then TARGET_JOB_NAME=${SOURCE_JOB_NAME}; fi

i=1
tot=6

# build required projects
mkdir -p /tmp/jbt.github
pushd /tmp/jbt.github >/dev/null
	if [[ ! -d maven-plugins ]]; then git clone --depth 1 git@github.com:nickboldt/maven-plugins.git; fi
	pushd maven-plugins >/dev/null
		git checkout master
		mvn clean install -DskipTests -f hudson-job-sync-plugin/pom.xml -q
		mvn clean install -DskipTests -f hudson-job-publisher-plugin/pom.xml -q
	popd >/dev/null
popd >/dev/null

# echo "[DEBUG] Copy job ${SOURCE_JOB_NAME} ..."

# TODO: git fetch the sources if not found in jbdevstudio_ci_folder

pushd ${jbdevstudio_ci_folder}

#export "MAVEN_OPTS=$MAVEN_OPTS -Dorg.slf4j.simpleLogger.defaultLogLevel=info"

echo "[INFO] [$i/$tot] Fetch latest OLD job ${SOURCE_JOB_NAME} from Jenkins"
# requires: https://github.com/nickboldt/maven-plugins/tree/master/hudson-job-sync-plugin
~/bin/hudpull.sh -DhudsonURL=https://${SOURCE_JENKINS}/ -sj ${SOURCE_JENKINS} -DviewFilter=${SOURCE_PATH} -DregexFilter="${SOURCE_JOB_NAME}" \
  | egrep "SUCCESS|FAIL|${SOURCE_JOB_NAME}" 
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Create dummy job on CCI (if not exist)"
if [[ ${forceOverwriteDestinationJob} == 1 ]]; then 
  createNewJobCmdReplace="-DreplaceExistingJob=true"
else
  createNewJobCmdReplace="-DreplaceExistingJob=false"
fi
# requires: https://github.com/nickboldt/maven-plugins/tree/master/hudson-job-publisher-plugin
createNewJobCmd="mvn install -e -fae -f ${jbdevstudio_ci_folder}/pom-publisher-internal.xml \
  -DjobTemplateFile=${jbdevstudio_ci_folder}/cache/https/${SOURCE_JENKINS}/${SOURCE_PATH}/job/${SOURCE_JOB_NAME}/config.xml \
  ${createNewJobCmdReplace} -DJOB_NAME=${TARGET_JOB_NAME}"
echo "[INFO] ${createNewJobCmd}"
createNewJobLog=/tmp/createNewJob.log.txt
${createNewJobCmd} 2>&1 > /tmp/createNewJob.log.txt
if [[ $(cat ${createNewJobLog} | egrep "FAIL") ]]; then 
  cat ${createNewJobLog}
  exit
else
  cat ${createNewJobLog} | egrep -o "SUCCESS|${TARGET_JOB_NAME}"
  rm -f ${createNewJobLog}
fi
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Fetch latest NEW job from Jenkins (after creating it)"
# requires: https://github.com/nickboldt/maven-plugins/tree/master/hudson-job-sync-plugin
~/bin/hudpull.sh -DhudsonURL=https://${TARGET_JENKINS}/ -sj ${TARGET_JENKINS} -DviewFilter=${TARGET_PATH} -DregexFilter="${TARGET_JOB_NAME}" \
  | egrep "SUCCESS|FAIL|${TARGET_JOB_NAME}" 
echo ""; (( i++ ))

if [[ ${forceOverwriteDestinationJob} == 1 ]] || [[ $createNewJob != *"job already exists"* ]]; then 
  let tot=tot+1
  echo "[INFO] [$i/$tot] Copy OLD job to NEW path, instead of dummy job"
  echo "[DEBUG] rsync cache/https/${SOURCE_JENKINS}/${SOURCE_PATH}/job/${SOURCE_JOB_NAME}/config.xml"
  echo "              cache/https/${TARGET_JENKINS}/${TARGET_PATH}job/${TARGET_JOB_NAME}/config.xml"
   rsync \
     cache/https/${SOURCE_JENKINS}/${SOURCE_PATH}/job/${SOURCE_JOB_NAME}/config.xml \
     cache/https/${TARGET_JENKINS}/${TARGET_PATH}/job/${TARGET_JOB_NAME}/config.xml
  echo ""; (( i++ ))
fi

label_exp_find="<hudson.matrix.LabelExpAxis>\n<name>label_exp</name>\n<values>\n<string>\n.\+</string>\n</values>\n</hudson.matrix.LabelExpAxis>\n"
label_exp_replace="<hudson.matrix.LabelExpAxis>\n<name>label_exp</name>\n<values>\n<string>\n${assignedNode}</string>\n</values>\n</hudson.matrix.LabelExpAxis>\n"

echo "[INFO] [$i/$tot] Edit the NEW job locally"
echo "       cache/https/${TARGET_JENKINS}/${TARGET_PATH}job/${TARGET_JOB_NAME}/config.xml"
sed -i \
    -e "s#<assignedNode>.\+</assignedNode>#<assignedNode>${assignedNode}</assignedNode>#" \
    -e "s#${label_exp_find}#${label_exp_replace}#" \
    -e "s#<jdk>.\+</jdk>#<jdk>${jdk}</jdk>#" \
    -e "s#<mavenName>.\+</mavenName>#<mavenName>${mavenName}</mavenName>#" \
    -e "s#<groovyName>.\+</groovyName>#<groovyName>${groovyName}</groovyName>#" \
    -e "s# -gs /home/hudson/.m2/settings.xml##" \
    cache/https/${TARGET_JENKINS}/${TARGET_PATH}/job/${TARGET_JOB_NAME}/config.xml
echo ""; (( i++ ))

let tot=tot+1
hasRentention=$(egrep -i "logRotator|daysToKeep|numToKeep" cache/https/${TARGET_JENKINS}/${TARGET_PATH}job/${TARGET_JOB_NAME}/config.xml)
if [[ ! $hasRentention ]]; then
  retentionPolicy="\n  <logRotator class=\"hudson.tasks.LogRotator\">\n    <daysToKeep>-1</daysToKeep>\n    <numToKeep>5</numToKeep>\n    <artifactDaysToKeep>-1</artifactDaysToKeep>\n    <artifactNumToKeep>-1</artifactNumToKeep>\n  </logRotator>\n  <keepDependencies>false</keepDependencies>\n"
  echo "[INFO] Create new retention policy:

${retentionPolicy}

"
  sed -i \
  -e "s#<keepDependencies>false</keepDependencies>#${retentionPolicy}#" \
    cache/https/${TARGET_JENKINS}/${TARGET_PATH}/job/${TARGET_JOB_NAME}/config.xml
else
  echo "[INFO] Existing retention policy:

${hasRentention}

";
fi
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Push NEW job back to server"
~/bin/hudpush.sh -DhudsonURL=https://${TARGET_JENKINS}/ -DviewFilter=${TARGET_PATH} -DregexFilter="${TARGET_JOB_NAME}" \
  | egrep "SUCCESS|FAIL|${TARGET_JOB_NAME}" 
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Job created: "
echo "       https://${TARGET_JENKINS}/${TARGET_PATH}/job/${TARGET_JOB_NAME}/"
echo ""
google-chrome https://${TARGET_JENKINS}/${TARGET_PATH}/job/${TARGET_JOB_NAME}/configure

popd
