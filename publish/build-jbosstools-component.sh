#!/bin/sh

# script to run in Jenkins for components builds with Maven

ls -la ${NATIVE_TOOLS}${SEP}

#parameters

jbosstools_site_stream=master
TARGET_PLATFORM_VERSION=4.60.0.Alpha1-SNAPSHOT
TARGET_PLATFORM_VERSION_MAXIMUM=4.60.0.Alpha1-SNAPSHOT

MAVEN_FLAGS="-B -U -fae -e -P hudson,unified.target,pack200"

BUILD_FLAGS="-Dmaven.repo.local=$WORKSPACE/.repository -DJOB_NAME=${JOB_NAME} -DBUILD_ID=${BUILD_ID} -DBUILD_NUMBER=${BUILD_NUMBER} \
-DTARGET_PLATFORM_VERSION=${TARGET_PLATFORM_VERSION} -Ddownload.cache.directory=/home/hudson/static_build_env/jbds/download-cache \
-DskipBaselineComparison=false -Dmaven.test.skip=true -DskipITests=true -DskipPrivateRequirements=false \
-Djbosstools.test.jre.5=${NATIVE_TOOLS}${SEP}${JAVA15} -Djbosstools.test.jre.6=${NATIVE_TOOLS}${SEP}${JAVA16} \
-Djbosstools.test.jre.7=${NATIVE_TOOLS}${SEP}${JAVA17} -Djbosstools.test.jre.8=${NATIVE_TOOLS}${SEP}${JAVA18} \
-Djbosstools_site_stream=${jbosstools_site_stream} ${MAVEN_FLAGS}"

TEST_FLAGS="-Dmaven.repo.local=$WORKSPACE/.repository -DJOB_NAME=${JOB_NAME} -DBUILD_ID=${BUILD_ID} -DBUILD_NUMBER=${BUILD_NUMBER} \
-DTARGET_PLATFORM_VERSION=${TARGET_PLATFORM_VERSION_MAXIMUM} -Ddownload.cache.directory=/home/hudson/static_build_env/jbds/download-cache \
-Dmaven.test.failure.ignore=true -Dmaven.test.error.ignore=true -DskipBaselineComparison=true -DskipPrivateRequirements=false \
-Dsurefire.itests.timeout=8000 -Dsurefire.timeout=8000 \
-Djbosstools_site_stream=${jbosstools_site_stream} ${MAVEN_FLAGS}"

WORK=${WORKSPACE}/sources

######################################################

cd ${WORK}

# work around invalid chars in a matrix job's workspace path using symlink magic
tmpdir=$(mktemp -d); pushd $tmpdir >/dev/null; ln -s ${WORKSPACE} ws; popd >/dev/null

M2_HOME=/qa/tools/opt/apache-maven-3.2.5/

# p2diff
p2diff=/home/hudson/static_build_env/jbds/p2diff/x86$(if [[ $(uname -a | grep x86_64) ]]; then echo _64; fi)/p2diff


if [[ ! ${ghprbPullId} ]]; then
  mvnStep1="$M2_HOME/bin/mvn clean install ${BUILD_FLAGS}" # build (no tests)
  mvnStep2="$M2_HOME/bin/mvn deploy -Pdeploy-to-jboss.org ${BUILD_FLAGS}" # deploy if new
  mvnStep3="$M2_HOME/bin/mvn help:effective-pom verify ${TEST_FLAGS}" # run tests & fail if problems found
else
  mvnStep1="$M2_HOME/bin/mvn clean install ${BUILD_FLAGS}" # build (no tests)
  mvnStep2="$M2_HOME/bin/mvn deploy -Pdeploy-pr ${BUILD_FLAGS}" # deploy if new
  mvnStep3="$M2_HOME/bin/mvn help:effective-pom verify ${TEST_FLAGS}" # run tests & fail if problems found
fi

# build and deploy PR in one step
if [[ ${ghprbPullId} ]]; then 
  ${mvnStep1}
  ${mvnStep2}

  echo "Available JREs for testing:"
  echo "jbosstools.test.jre.5=${NATIVE_TOOLS}${SEP}${JAVA15}"
  echo "jbosstools.test.jre.6=${NATIVE_TOOLS}${SEP}${JAVA16}"
  echo "jbosstools.test.jre.7=${NATIVE_TOOLS}${SEP}${JAVA17}"
  echo "jbosstools.test.jre.8=${NATIVE_TOOLS}${SEP}${JAVA18}"
  if [[ -d ${WORKSPACE}/sources/all-tests/ ]] && [[ -f ${WORKSPACE}/sources/all-tests/pom.xml ]]; then
    cd ${WORKSPACE}/sources/all-tests/
  elif [[ -d ${WORKSPACE}/sources/tests/ ]] && [[ -f ${WORKSPACE}/sources/tests/pom.xml ]]; then
    cd ${WORKSPACE}/sources/tests/
  fi
  ${mvnStep3}
else
  ${mvnStep1}
  if [[ ${skipRevisionCheckWhenPublishing} == "true" ]] || [[ $([[ -x $p2diff ]] && ${p2diff} file://${WORK}/target/fullSite/all/repo/ http://download.jboss.org/jbosstools/mars/snapshots/builds/jbosstools-build-sites.aggregate.${projectName}-site_${jbosstools_site_stream}/latest/all/repo/ -vmargs -Dosgi.locking=none | egrep "<|>" | egrep -v "(<|>) (Alpha[0-9]+|Beta[0-9]+|CR[0-9]+|Final|GA).+-B[0-9]+\.") ]] || [[ $(. ${WORKSPACE}/sources/util/checkLatestPublishedSHA.sh -s ${WORKSPACE}/sources/aggregate/${projectName}-site/target/fullSite/all/repo -t http://download.jboss.org/jbosstools/mars/snapshots/builds/jbosstools-build-sites.aggregate.${projectName}-site_${jbosstools_site_stream}/latest/all/repo/ -all) == "true" ]]; then
    ${mvnStep2}

    echo "Available JREs for testing:"
    echo "jbosstools.test.jre.5=${NATIVE_TOOLS}${SEP}${JAVA15}"
    echo "jbosstools.test.jre.6=${NATIVE_TOOLS}${SEP}${JAVA16}"
    echo "jbosstools.test.jre.7=${NATIVE_TOOLS}${SEP}${JAVA17}"
    echo "jbosstools.test.jre.8=${NATIVE_TOOLS}${SEP}${JAVA18}"
    if [[ -d ${WORKSPACE}/sources/all-tests/ ]] && [[ -f ${WORKSPACE}/sources/all-tests/pom.xml ]]; then
      cd ${WORKSPACE}/sources/all-tests/
    elif [[ -d ${WORKSPACE}/sources/tests/ ]] && [[ -f ${WORKSPACE}/sources/tests/pom.xml ]]; then
      cd ${WORKSPACE}/sources/tests/
    fi
    ${mvnStep3}
  else
    echo "Publish cancelled (nothing to do). Will not run tests. Skip this check with skipRevisionCheckWhenPublishing=true to force publishing and running of tests."
    BUILD_DESCRIPTION="NOT PUBLISHED: UNCHANGED"
  fi
fi

# cleanup
rm -fr $tmpdir