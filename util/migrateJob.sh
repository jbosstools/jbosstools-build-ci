#!/bin/bash
# migrate a job from one Jenkins to another


# where you have https://github.com/jbdevstudio/jbdevstudio-ci checked out`
jbdevstudio_ci_folder=${HOME}/truu/jbdevstudio-ci

# job to copy
JOB_NAME=""

# jenkins variables
SOURCE_JENKINS="jenkins.hosts.mwqe.eng.bos.redhat.com/hudson"
SOURCE_PATH="view/DevStudio/view/jbosstools-releng"
TARGET_JENKINS="dev-platform-jenkins.rhev-ci-vms.eng.rdu2.redhat.com"
TARGET_PATH="view/Devstudio/view/jbosstools-releng"

# string replacements to apply to the destination version of the job
assignedNode="rhel7-devstudio-releng" # new node to use
jdk="jdk1.8"
mavenName="maven-3.3.9"

usage ()
{
	echo "Usage  : $0 -s source_path/ -t target_path/ -j job_name"
	echo ""
	echo "Example: $0 -s view/DevStudio/view/jbosstools-releng/ -t view/Devstudio/view/jbosstools-releng/ \\"
	echo "  -j jbosstools-releng-push-to-staging-01-check-versions-branches-root-poms"
	echo "Example: $0 -s view/DevStudio/view/DevStudio_Master/ -t view/Devstudio/view/devstudio_master/ \\"
	echo "  -j jbosstools-cleanup"
	echo "Example: $0 -s view/DevStudio/view/devstudio_10.0.neon/ -t view/Devstudio/view/devstudio_10.0.neon/ \\"
	echo "  -j jbosstools-build-ci_4.4.neon"
	exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-f') jbdevstudio_ci_folder="$2"; shift 1;;

		'-j') JOB_NAME="$2"; shift 1;;

		'-s') SOURCE_PATH="$2"; shift 1;; # ${WORKSPACE}/sources/site/target/repository/
		'-t') TARGET_PATH="$2"; shift 1;; # neon/snapshots/builds/<job-name>/<build-number>/, neon/snapshots/updates/core/{4.4.0.Final, master}/
		'-sj') SOURCE_JENKINS="$2"; shift 1;;
		'-tj') TARGET_JENKINS="$2"; shift 1;;

		'-assignedNode') 	assignedNode=="$2"; shift 1;;
		'-mavenName') 		mavenName=="$2"; shift 1;;
		'-jdk') 			jdk=="$2"; shift 1;;
	esac
	shift 1
done

if [[ ! ${JOB_NAME} ]]; then usage; fi

i=1
tot=6

# echo "[DEBUG] Copy job ${JOB_NAME} ..."

# TODO: git fetch the sources if not found in jbdevstudio_ci_folder

pushd ${jbdevstudio_ci_folder}

#export "MAVEN_OPTS=$MAVEN_OPTS -Dorg.slf4j.simpleLogger.defaultLogLevel=info"

echo "[INFO] [$i/$tot] Fetch latest OLD job ${JOB_NAME} from Jenkins"
# requires: https://github.com/nickboldt/maven-plugins/tree/master/hudson-job-sync-plugin
~/bin/hudpull.sh -DhudsonURL=https://${SOURCE_JENKINS}/ -DviewFilter=${SOURCE_PATH} -DregexFilter="${JOB_NAME}" \
  | egrep "SUCCESS|FAIL|${JOB_NAME}" 
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Create dummy job on CCI (if not exist)"
# requires: https://github.com/nickboldt/maven-plugins/tree/master/hudson-job-publisher-plugin
createNewJob=$(mvn install -f pom-publisher-internal.xml \
  -DjobTemplateFile=cache/https/${SOURCE_JENKINS}/${SOURCE_PATH}/job/${JOB_NAME}/config.xml \
  -DreplaceExistingJob=false -DJOB_NAME=${JOB_NAME})
  echo $createNewJob | egrep -o "SUCCESS|FAIL|${JOB_NAME}"
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Fetch latest NEW job from Jenkins (after creating it)"
# requires: https://github.com/nickboldt/maven-plugins/tree/master/hudson-job-sync-plugin
~/bin/hudpull-centralCI.sh -DhudsonURL=https://${TARGET_JENKINS}/ -DviewFilter=${TARGET_PATH} -DregexFilter="${JOB_NAME}" \
  | egrep "SUCCESS|FAIL|${JOB_NAME}" 
echo ""; (( i++ ))

if [[ $createNewJob != *"job already exists"* ]]; then 
  let tot=tot+1
  echo "[INFO] [$i/$tot] Copy OLD job to NEW path, instead of dummy job"
  echo "[DEBUG] rsync cache/https/${SOURCE_JENKINS}/${SOURCE_PATH}/job/${JOB_NAME}/config.xml"
  echo "              cache/https/${TARGET_JENKINS}/${TARGET_PATH}job/${JOB_NAME}/config.xml"
   rsync \
     cache/https/${SOURCE_JENKINS}/${SOURCE_PATH}/job/${JOB_NAME}/config.xml \
     cache/https/${TARGET_JENKINS}/${TARGET_PATH}/job/${JOB_NAME}/config.xml
  echo ""; (( i++ ))
fi

echo "[INFO] [$i/$tot] Edit the NEW job locally"
echo "       cache/https/${TARGET_JENKINS}/${TARGET_PATH}job/${JOB_NAME}/config.xml"
sed -i \
    -e "s#<assignedNode>.\+</assignedNode>#<assignedNode>${assignedNode}</assignedNode>#" \
    -e "s#<jdk>.\+</jdk>#<jdk>${jdk}</jdk>#" \
    -e "s#<mavenName>.\+</mavenName>#<mavenName>${mavenName}</mavenName>#" \
    cache/https/${TARGET_JENKINS}/${TARGET_PATH}/job/${JOB_NAME}/config.xml
echo ""; (( i++ ))

let tot=tot+1
hasRentention=$(egrep -i "logRotator|daysToKeep|numToKeep" cache/https/${TARGET_JENKINS}/${TARGET_PATH}job/${JOB_NAME}/config.xml)
if [[ ! $hasRentention ]]; then
  retentionPolicy="
  <logRotator class=\"hudson.tasks.LogRotator\">
    <daysToKeep>-1</daysToKeep>
    <numToKeep>5</numToKeep>
    <artifactDaysToKeep>-1</artifactDaysToKeep>
    <artifactNumToKeep>-1</artifactNumToKeep>
  </logRotator>
  <keepDependencies>false</keepDependencies>
"
  echo "[INFO] Create new retention policy:

${retentionPolicy}

"
	sed -i \
	-e "s#<keepDependencies>false</keepDependencies>#${retentionPolicy}#" \
    cache/https/${TARGET_JENKINS}/${TARGET_PATH}/job/${JOB_NAME}/config.xml
else
  echo "[INFO] Existing retention policy:

${hasRentention}

";
fi
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Push NEW job back to server"
~/bin/hudpush.sh -DhudsonURL=https://${TARGET_JENKINS}/ -DviewFilter=${TARGET_PATH} -DregexFilter="${JOB_NAME}" \
  | egrep "SUCCESS|FAIL|${JOB_NAME}" 
echo ""; (( i++ ))

echo "[INFO] [$i/$tot] Job created: "
echo "       https://${TARGET_JENKINS}/${TARGET_PATH}/job/${JOB_NAME}/"
echo ""
google-chrome https://${TARGET_JENKINS}/${TARGET_PATH}/job/${JOB_NAME}/configure

popd
