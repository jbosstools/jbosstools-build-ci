#!/bin/bash
# Hudson script used to publish Tycho-built p2 update sites
# NOTE: sources MUST be checked out into ${WORKSPACE}/sources 

if [ -z "${WORKSPACE}" ]; then
	echo "WORKSPACE property must be set"
	exit 1
fi
if [ -z "${JOB_NAME}" ]; then
	echo "JOB_NAME property must be set"
	exit 1
fi


# to use timestamp when naming dirs instead of ${BUILD_ID}-B${BUILD_NUMBER}, use:
# BUILD_ID=2010-08-31_19-16-10; timestamp=$(echo $BUILD_ID | tr -d "_-"); timestamp=${timestamp:0:12}; echo $timestamp; # 201008311916

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

# where to create the stuff to publish
STAGINGDIR=${WORKSPACE}/results/${JOB_NAME}

# for trunk, use "trunk" or "trunk/soa" instead of generated path from job name
PUBLISHPATHSUFFIX=""; if [[ $1 ]]; then PUBLISHPATHSUFFIX="$1"; fi

# https://jira.jboss.org/browse/JBIDE-6956 "jbosstools-3.2.0.M2" is too verbose, use "3.2.0.M2" instead
JOBNAMEREDUX=${JOB_NAME/.aggregate}; JOBNAMEREDUX=${JOBNAMEREDUX/jbosstools-}

if [[ ${PUBLISHPATHSUFFIX} ]]; then 
  PUBLISHEDSITE="http://download.jboss.org/jbosstools/updates/nightly/${PUBLISHPATHSUFFIX}"
else
  PUBLISHEDSITE="http://download.jboss.org/jbosstools/updates/nightly/${JOBNAMEREDUX}"
fi

wgetParams="--timeout=900 --wait=10 --random-wait --tries=10 --retry-connrefused --no-check-certificate -q"

getRemoteFile ()
{
  # requires $wgetParams and $tmpdir to be defined (above)
  getRemoteFileReturn=""
  URL="$1"
  output=`mktemp getRemoteFile.XXXXXX`
  if [[ ! `wget ${wgetParams} ${URL} -O ${tmpdir}/${output} 2>&1 | egrep "ERROR 404"` ]]; then # file downloaded
    getRemoteFileReturn=${tmpdir}/${output}
  else
    getRemoteFileReturn=""
    rm -f ${tmpdir}/${output}
  fi
}

# releases get named differently than snapshots
if [[ ${RELEASE} == "Yes" ]]; then
  ZIPSUFFIX="${BUILD_ID}-B${BUILD_NUMBER}"
else
  ZIPSUFFIX="SNAPSHOT"
fi

# define target update zip filename
SNAPNAME="${JOB_NAME}-${ZIPSUFFIX}-updatesite.zip"
# define target sources zip filename
SRCSNAME="${JOB_NAME}-${ZIPSUFFIX}-src.zip"
# define suffix to use for additional update sites
SUFFNAME="${ZIPSUFFIX}-updatesite.zip"

# for JBDS, use DESTINATION=/qa/services/http/binaries/RHDS
if [[ $DESTINATION == "" ]]; then DESTINATION="tools@filemgmt.jboss.org:/downloads_htdocs/tools"; fi

# internal destination mirror, for file:// access (instead of http://)
if [[ $INTRNALDEST == "" ]]; then INTRNALDEST="/home/hudson/static_build_env/jbds"; fi

# cleanup from last time
rm -fr ${WORKSPACE}/results; mkdir -p ${STAGINGDIR}

# check for aggregate zip or overall zip
z=""
if [[ -d   ${WORKSPACE}/sources/aggregate/site/target ]]; then
  if [[ -f ${WORKSPACE}/sources/aggregate/site/target/site_assembly.zip ]]; then
   siteZip=${WORKSPACE}/sources/aggregate/site/target/site_assembly.zip
  else
   siteZip=${WORKSPACE}/sources/aggregate/site/target/repository.zip
  fi
  z=$siteZip
elif [[ -d ${WORKSPACE}/sources/aggregate/site/site/target ]]; then
  if [[ -f ${WORKSPACE}/sources/aggregate/site/site/target/site_assembly.zip ]]; then
   siteZip=${WORKSPACE}/sources/aggregate/site/site/target/site_assembly.zip
  else
   siteZip=${WORKSPACE}/sources/aggregate/site/site/target/repository.zip
  fi
  z=$siteZip
elif [[ -d ${WORKSPACE}/sources/product/site/target ]]; then # product builds ONLY
  if [[ -f ${WORKSPACE}/sources/product/site/target/site_assembly.zip ]]; then
   siteZip=${WORKSPACE}/sources/product/site/target/site_assembly.zip
  fi
  z=$siteZip
elif [[ -d ${WORKSPACE}/sources/site/target ]]; then
  if [[ -f ${WORKSPACE}/sources/site/target/site_assembly.zip ]]; then
   siteZip=${WORKSPACE}/sources/site/target/site_assembly.zip
  else
   siteZip=${WORKSPACE}/sources/site/target/repository.zip
   # JBIDE-10923
   pushd ${WORKSPACE}/sources/site/target/repository >/dev/null
   zip -r $siteZip .
   popd >/dev/null
  fi
  z=$siteZip
fi


# note the job name, build number, SVN rev, and build ID of the latest snapshot zip
mkdir -p ${STAGINGDIR}/logs
bl=${STAGINGDIR}/logs/BUILDLOG.txt
rm -f ${bl}; 
getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/${BUILD_NUMBER}/consoleText"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${bl}; fi

# calculate BUILD_ALIAS from parent pom version as recorded in the build log, eg., from org/jboss/tools/parent/4.0.0.Alpha2-SNAPSHOT get Alpha2
BUILD_ALIAS=$(cat ${bl} | grep "org/jboss/tools/parent/" | head -1 | sed -e "s#.\+org/jboss/tools/parent/\(.\+\)/\(maven-metadata.xml\|parent.\+\)#\1#" | sed -e "s#-SNAPSHOT##" | sed -e "s#[0-9].[0-9].[0-9].##")

# store details about the SVN or Git revision and where the detailed log is located, so we can easily see if this build's different from the previous
REV_LOG_URL=""
REV_LOG_DETAIL=""

# JBDS-1361 - fetch XML and then sed it into plain text
mkdir -p ${STAGINGDIR}/logs
rl=${STAGINGDIR}/logs/REVISION
if [[ $(find ${WORKSPACE} -mindepth 2 -maxdepth 3 -name ".git") ]]; then
  # Track git source revision through hudson api: /job/${JOB_NAME}/${BUILD_NUMBER}/api/xml?xpath=(//lastBuiltRevision)[1]
  rl=${STAGINGDIR}/logs/GIT_REVISION
  rm -f ${rl}.txt ${rl}.xml 
  getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/${BUILD_NUMBER}/api/xml?xpath=%28//lastBuiltRevision%29[1]"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${rl}.xml; fi

  sed -e "s#<lastBuiltRevision><SHA1>\([a-f0-9]\+\)</SHA1><branch><SHA1>\([a-f0-9]\+\)</SHA1><name>\([^<>]\+\)</name></branch></lastBuiltRevision>#\3\@\1#g" ${rl}.xml | sed -e "s#<[^<>]\+>##g" > ${rl}.txt
  REV_LOG_URL="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/GIT_REVISION.txt"
  REV_LOG_DETAIL="`cat ${rl}.txt`"
elif [[ $(find ${WORKSPACE} -mindepth 2 -maxdepth 3 -name ".svn") ]]; then
  # Track svn source revision through hudson api: /job/${JOB_NAME}/api/xml?wrapper=changeSet&depth=1&xpath=//build[1]/changeSet/revision
  rl=${STAGINGDIR}/logs/SVN_REVISION
  rm -f ${rl}.txt ${rl}.xml
  getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/api/xml?wrapper=changeSet&depth=1&xpath=//build[1]/changeSet/revision"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${rl}.xml; fi
  if [[ $? -eq 0 ]]; then
    sed -e "s#<module>\(http[^<>]\+\)</module><revision>\([0-9]\+\)</revision>#\1\@\2\n#g" ${rl}.xml | sed -e "s#<[^<>]\+>##g" > ${rl}.txt 
    REV_LOG_URL="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/SVN_REVISION.txt"
    REV_LOG_DETAIL="`cat ${rl}.txt`"
  else
    echo "UNKNOWN SVN REVISION(S)" > ${rl}.txt
    REV_LOG_URL="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/"
    REV_LOG_DETAIL="Details"
  fi
else
  # not git or svn... unsupported
  echo "UNKNOWN REVISION(S)" > ${rl}.txt
  REV_LOG_URL="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/"
  REV_LOG_DETAIL="Details"
fi

# collect ALL_REVISIONS for aggregate build
mkdir -p ${STAGINGDIR}/logs
ALLREVS=${STAGINGDIR}/logs/ALL_REVISIONS.txt
if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]] && [[ -d ${WORKSPACE}/sources/aggregate/site/zips ]]; then
  GITREV_SOURCE="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}"
  echo "  >>> ${GITREV_SOURCE}/components <<<  " > $ALLREVS

  if [[ -f ${WORKSPACE}/sources/aggregate/site/zips/ALL_REVISIONS.txt ]]; then
    echo "" >> $ALLREVS
    cat ${WORKSPACE}/sources/aggregate/site/zips/ALL_REVISIONS.txt >> $ALLREVS
    echo "" >> $ALLREVS
  fi

  # work locally if posible
  if [[ -d ${STAGINGDIR}/components ]]; then
    for f in `cd ${STAGINGDIR}/components; find . -maxdepth 1 -type f -name "*.zip" | sort`; do
      REV=
      g=`echo $f | sed 's#\.\/\([^<>]\+\)(-Update|-updatesite).\+.zip#\1#g'`
      if [[ ! `wget ${wgetParams} http://download.jboss.org/jbosstools/builds/staging/${g}/logs/GIT_REVISION.txt -O $tmpdir/${g}_GIT_REVISION.txt 2>&1 | egrep "ERROR 404"` ]]; then
        REV=`cat $tmpdir/${g}_GIT_REVISION.txt`
      else
        REV="?"
      fi
      rm -fr $tmpdir/${g}_GIT_REVISION.txt
      echo -n "${g} :: $REV" >> $ALLREVS
      componentname=${g/*component--/}
      componentname=${componentname/-1.9.2/}
      componentname=${componentname/central-maven-examples/central}
      echo " :: https://github.com/jbosstools/jbosstools-"${componentname}/commit/${REV##*@} >> $ALLREVS
    done
  elif [[ ! `wget -q -nc ${GITREV_SOURCE}/components/ -O $tmpdir/index.html 2>&1 | egrep "ERROR 404"` ]]; then # else fetch from server
    for f in $(cat $tmpdir/index.html | egrep -v "C=D|title>|h1>|DIR"); do
      if [[ ${f/zip.MD5/} != ${f} ]]; then
        true;
      elif [[ ${f/zip/} != ${f} ]]; then
        REV=
        g=`echo $f | sed 's#href=".\+zip">\([^<>]\+\)(-Update|-updatesite).\+.zip</a>.\+#\1#g'`
        if [[ ! `wget ${wgetParams} http://download.jboss.org/jbosstools/builds/staging/${g}/logs/GIT_REVISION.txt -O $tmpdir/${g}_GIT_REVISION.txt 2>&1 | egrep "ERROR 404"` ]]; then
          REV=`cat $tmpdir/${g}_GIT_REVISION.txt`
        else
          REV="?"
        fi
        rm -fr $tmpdir/${g}_GIT_REVISION.txt
        echo -n "${g} :: $REV" >> $ALLREVS
        componentname=${g/*component--/}
        componentname=${componentname/-1.9.2/}
        componentname=${componentname/central-maven-examples/central}
        echo " :: https://github.com/jbosstools/jbosstools-"${componentname}/commit/${REV##*@} >> $ALLREVS
      fi
    done
    rm -f $tmpdir/index.html
  fi
  echo "" >> $ALLREVS
fi

if [[ ${JOB_NAME/devstudio} != ${JOB_NAME} ]]; then # devstudio build
  echo "  >>> ${JOB_NAME} <<<" >> $ALLREVS
  ## work locally if posible
  if [[ -f ${STAGINGDIR}/logs/GIT_REVISION.txt ]]; then
    cp ${STAGINGDIR}/logs/GIT_REVISION.txt $tmpdir/devstudio_GIT_REVISION.txt
  elif [[ -f ${STAGINGDIR}/logs/SVN_REVISION.txt ]]; then
    cp ${STAGINGDIR}/logs/SVN_REVISION.txt $tmpdir/devstudio_SVN_REVISION.txt
  else
    # else fetch from server - try git then fall back to svn (deprecated)
    getRemoteFile "http://www.qa.jboss.com/binaries/RHDS/builds/staging/${JOB_NAME}/logs/GIT_REVISION.txt"
    if [[ -w ${getRemoteFileReturn} ]]; then 
      mv ${getRemoteFileReturn} $tmpdir/devstudio_GIT_REVISION.txt 
      REV_LOG_URL="http://www.qa.jboss.com/binaries/RHDS/builds/staging/${JOB_NAME}/logs/GIT_REVISION.txt"
      REV_LOG_DETAIL="`cat $tmpdir/devstudio_GIT_REVISION.txt`"
    else
      getRemoteFile "http://www.qa.jboss.com/binaries/RHDS/builds/staging/${JOB_NAME}/logs/SVN_REVISION.txt"
      if [[ -w ${getRemoteFileReturn} ]]; then 
        mv ${getRemoteFileReturn} $tmpdir/devstudio_SVN_REVISION.txt 
        REV_LOG_URL="http://www.qa.jboss.com/binaries/RHDS/builds/staging/${JOB_NAME}/logs/SVN_REVISION.txt"
        REV_LOG_DETAIL="`cat $tmpdir/devstudio_SVN_REVISION.txt`"
      fi
    fi
  fi
  if [[ -f $tmpdir/devstudio_GIT_REVISION.txt ]]; then cat $tmpdir/devstudio_GIT_REVISION.txt >> $ALLREVS; fi
  if [[ -f $tmpdir/devstudio_SVN_REVISION.txt ]]; then cat $tmpdir/devstudio_SVN_REVISION.txt >> $ALLREVS; fi

  # get name of upstream project (eg., for devstudio.product_70 want jbosstools-build-sites.aggregate.site_41)
  getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/api/xml?xpath=%28//upstreamProject/name%29[1]"; 
  if [[ -r ${getRemoteFileReturn} ]] && [[ -w ${getRemoteFileReturn} ]]; then 
    mv ${getRemoteFileReturn} $tmpdir/upstreamProject.name.xml
  else
    echo "<name>UNKNOWN</name>" > $tmpdir/upstreamProject.name.xml
  fi

  UPSTREAM_JOB_NAME=`sed -e "s#<name>\(.\+\)</name>#\1#g" $tmpdir/upstreamProject.name.xml`
  echo "" >> $ALLREVS
  echo "  >>> ${UPSTREAM_JOB_NAME} <<<" >> $ALLREVS
  echo "" >> $ALLREVS
  echo "See also upstream JBoss Tools aggregate job for complete list of git revisions."  >> $ALLREVS
  echo " * http://download.jboss.org/jbosstools/builds/staging/${UPSTREAM_JOB_NAME}/logs/ALL_REVISIONS.txt *" >> $ALLREVS
  echo "" >> $ALLREVS

  # ensure upstream logs/ALL_REVISIONS.txt file actually exists
  if [[ ! `wget ${wgetParams} -O - http://download.jboss.org/jbosstools/builds/staging/${UPSTREAM_JOB_NAME}/logs/ALL_REVISIONS.txt -O $tmpdir/upstream_ALL_REVISIONS.txt 2>&1 | egrep "ERROR 404"` ]]; then
    cat $tmpdir/upstream_ALL_REVISIONS.txt >> $ALLREVS
    echo "" >> $ALLREVS
  fi
  rm -f $tmpdir/devstudio_GIT_REVISION.txt $tmpdir/devstudio_SVN_REVISION.txt $tmpdir/upstreamProject.name.xml $tmpdir/upstream_ALL_REVISIONS.txt
fi

PUBLISH_STATUS=""
showUnchangedMessage ()
{
  echo "======================================================================================================="
  echo ""
  echo "$1 revision(s) UNCHANGED. Publish cancelled (nothing to do). Skip this check with 'EXPORT skipRevisionCheckWhenPublishing=true; ./$0 ...'"
  echo ""
  echo "======================================================================================================="
  PUBLISH_STATUS=" (NOT PUBLISHED: UNCHANGED)"
}

# JBIDE-13672 if current revision log == previous revision log, then we can stop publishing right now (unless skipRevisionCheckWhenPublishing=true)
if [[ ${skipRevisionCheckWhenPublishing} != "true" ]]; then
  PREV_REV_FILE=$tmpdir/PREV_REV.txt
  if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]] && [[ -d ${WORKSPACE}/sources/aggregate/site/zips ]]; then # check previous build's ALL_REVISIONS log
    rm -f ${PREV_REV_FILE}; PREV_REV_CHECK=`wget ${wgetParams} -O ${PREV_REV_FILE} http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/ALL_REVISIONS.txt 2>/dev/null && echo "found" || echo "not found"`
      REV_LOG_DETAIL="Details"
      REV_LOG_URL="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/ALL_REVISIONS.txt"
    if [[ ! ${PREV_REV_CHECK%%*not found*} ]]; then 
      echo "No previous log in http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/ALL_REVISIONS.txt"
    elif [[ `cat ${ALLREVS}` == `cat ${PREV_REV_FILE}` ]]; then 
      showUnchangedMessage GIT
    fi
  elif [[ $(find ${WORKSPACE} -mindepth 2 -maxdepth 3 -name ".git") ]]; then # check previous build's GIT_REVISION log
    REV_LOG_DETAIL="`cat ${rl}.txt`"
    if [[ ${REV_LOG_DETAIL} ]]; then # file has contents
      REV_LOG_URL="http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/GIT_REVISION.txt"
      rm -f ${PREV_REV_FILE}; PREV_REV_CHECK=`wget ${wgetParams} -O ${PREV_REV_FILE} http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/GIT_REVISION.txt 2>/dev/null && echo "found" || echo "not found"`
      if [[ ! ${PREV_REV_CHECK%%*not found*} ]]; then 
        echo "No previous log in http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/GIT_REVISION.txt"
      elif [[ `cat ${rl}.txt` == `cat ${PREV_REV_FILE}` ]]; then 
        showUnchangedMessage GIT 
      fi
    else
      # should never see this
      echo "WARNING: no GIT_REVISION found in ${rl}.txt"
      PUBLISH_STATUS=" (PUBLISHED: NO GIT_REVISION)"
    fi
  elif [[ $(find ${WORKSPACE} -mindepth 2 -maxdepth 3 -name ".svn") ]]; then # check previous build's SVN_REVISION log
    if [[ ${JOB_NAME/devstudio} != ${JOB_NAME} ]]; then # devstudio build
      SVN_REVISION_URL=http://www.qa.jboss.com/binaries/RHDS/builds/staging/${JOB_NAME}/logs/SVN_REVISION.txt
    else
      SVN_REVISION_URL=http://download.jboss.org/jbosstools/builds/staging/${JOB_NAME}/logs/SVN_REVISION.txt
    fi
    REV_LOG_DETAIL="`cat ${rl}.txt`"
    REV_LOG_URL="${SVN_REVISION_URL}"
    rm -f ${PREV_REV_FILE}; PREV_REV_CHECK=`wget ${wgetParams} -O ${PREV_REV_FILE} ${SVN_REVISION_URL} 2>/dev/null && echo "found" || echo "not found"`
    if [[ ! ${PREV_REV_CHECK%%*not found*} ]]; then 
      echo "No previous log in ${SVN_REVISION_URL}"
    elif [[ `cat ${rl}.txt` == `cat ${PREV_REV_FILE}` ]]; then 
      showUnchangedMessage SVN 
    fi
  fi
  PREV_REV_CHECK=""

  if [[ ${PUBLISH_STATUS} ]]; then 
    if [[ ${JOB_NAME/.product} == ${JOB_NAME} ]]; then
      # set a BUILD_DESCRIPTION we can later parse from Jenkins
      BUILD_DESCRIPTION='<li>Rev: <a href="'${REV_LOG_URL}'">'${REV_LOG_DETAIL}'</a>'${PUBLISH_STATUS}'</li> <li>Target: <a href="http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/'${TARGET_PLATFORM_VERSION}'">'${TARGET_PLATFORM_VERSION}'</a> / <a href="http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/'${TARGET_PLATFORM_VERSION_MAXIMUM}'">'${TARGET_PLATFORM_VERSION_MAXIMUM}'</a></li> <li><a href="http://download.jboss.org/jbosstools/builds/staging/'${JOB_NAME}'/all/repo/">Update Site</a></li> <li><a href="/hudson/job/'${JOB_NAME}'/'${BUILD_NUMBER}'/artifact/sources/target/coverage-report/html/JBoss_Tools_chunk/index.html">Coverage report</a> &amp; <a href="/hudson/job/'${JOB_NAME}'/'${BUILD_NUMBER}'/artifact/sources/*/target/jacoco.exec" style="color: purple; font-weight:bold">jacoco.exec</a> (EclEmma)</li>'
    else
      # set a build description for JBDS product builds
      REV_LOG_SHORT=`echo $REV_LOG_DETAIL | sed "s#.*repos/devstudio/##g" | sed "s/[\n\r\ \t]\+//g"`
      BUILD_DESCRIPTION='<li>Rev: <a href="'${REV_LOG_URL}'">'${REV_LOG_SHORT}'</a>'${PUBLISH_STATUS}'</li> <li>Target: <a href="http://www.qa.jboss.com/binaries/RHDS/targetplatforms/jbdevstudiotarget/'${TARGET_PLATFORM_VERSION}'">'${TARGET_PLATFORM_VERSION}'</a> / <a href="http://www.qa.jboss.com/binaries/RHDS/targetplatforms/jbdevstudiotarget/'${TARGET_PLATFORM_VERSION_MAXIMUM}'">'${TARGET_PLATFORM_VERSION_MAXIMUM}'</a></li> <li><a href="http://www.qa.jboss.com/binaries/RHDS/builds/staging/'${JOB_NAME}'/all/repo/">Update Site</a></li> <li><a href="http://www.qa.jboss.com/binaries/RHDS/builds/staging/'${JOB_NAME}'/installer/">Installers & Zips</a></li> <li>Upstream: <a href="http://download.jboss.org/jbosstools/builds/staging/'${UPSTREAM_JOB_NAME}'/all/repo/">Update Site</a>'
    fi
    if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]]; then echo ">> ${PUBLISHEDSITE} <<"; fi
    exit 0
  else
    # checked but did not show Unchanged Message, so we have changes; will therefore publish
     PUBLISH_STATUS=" (PUBLISHED: CHANGED)"
  fi
else
    # did not check, so may or may not have changes; will publish regardless
  PUBLISH_STATUS=" (PUBLISHED: SKIP REV CHECK)"
fi

if [[ ${JOB_NAME/.product} == ${JOB_NAME} ]]; then
  # set a BUILD_DESCRIPTION we can later parse from Jenkins
  BUILD_DESCRIPTION='<li>Rev: <a href="'${REV_LOG_URL}'">'${REV_LOG_DETAIL}'</a>'${PUBLISH_STATUS}'</li> <li>Target: <a href="http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/'${TARGET_PLATFORM_VERSION}'">'${TARGET_PLATFORM_VERSION}'</a> / <a href="http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/'${TARGET_PLATFORM_VERSION_MAXIMUM}'">'${TARGET_PLATFORM_VERSION_MAXIMUM}'</a></li> <li><a href="http://download.jboss.org/jbosstools/builds/staging/'${JOB_NAME}'/all/repo/">Update Site</a></li> <li><a href="/hudson/job/'${JOB_NAME}'/'${BUILD_NUMBER}'/artifact/sources/target/coverage-report/html/JBoss_Tools_chunk/index.html">Coverage report</a> &amp; <a href="/hudson/job/'${JOB_NAME}'/'${BUILD_NUMBER}'/artifact/sources/*/target/jacoco.exec" style="color: purple; font-weight:bold">jacoco.exec</a> (EclEmma)</li>'
else
  # set a build description for JBDS product builds
  REV_LOG_SHORT=`echo $REV_LOG_DETAIL | sed "s#.*repos/devstudio/##g" | sed "s/[\n\r\ \t]\+//g"`
  BUILD_DESCRIPTION='<li>Rev: <a href="'${REV_LOG_URL}'">'${REV_LOG_SHORT}'</a>'${PUBLISH_STATUS}'</li> <li>Target: <a href="http://www.qa.jboss.com/binaries/RHDS/targetplatforms/jbdevstudiotarget/'${TARGET_PLATFORM_VERSION}'">'${TARGET_PLATFORM_VERSION}'</a> / <a href="http://www.qa.jboss.com/binaries/RHDS/targetplatforms/jbdevstudiotarget/'${TARGET_PLATFORM_VERSION_MAXIMUM}'">'${TARGET_PLATFORM_VERSION_MAXIMUM}'</a></li> <li><a href="http://www.qa.jboss.com/binaries/RHDS/builds/staging/'${JOB_NAME}'/all/repo/">Update Site</a></li> <li><a href="http://www.qa.jboss.com/binaries/RHDS/builds/staging/'${JOB_NAME}'/installer/">Installers & Zips</a></li> <li>Upstream: <a href="http://download.jboss.org/jbosstools/builds/staging/'${UPSTREAM_JOB_NAME}'/all/repo/">Update Site</a>'
fi

METAFILE="${BUILD_ID}-B${BUILD_NUMBER}.txt"
mkdir -p ${STAGINGDIR}/logs
touch ${STAGINGDIR}/logs/${METAFILE}
METAFILE=build.properties

echo "BUILD_ALIAS = ${BUILD_ALIAS}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "JOB_NAME = ${JOB_NAME}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "BUILD_NUMBER = ${BUILD_NUMBER}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "BUILD_ID = ${BUILD_ID}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "WORKSPACE = ${WORKSPACE}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "HUDSON_SLAVE = $(uname -a)" >> ${STAGINGDIR}/logs/${METAFILE}
echo "RELEASE = ${RELEASE}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "ZIPSUFFIX = ${ZIPSUFFIX}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "" >> ${STAGINGDIR}/logs/${METAFILE}
echo "TARGET_PLATFORM_VERSION=${TARGET_PLATFORM_VERSION}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "TARGET_PLATFORM_VERSION_MAXIMUM=${TARGET_PLATFORM_VERSION_MAXIMUM}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "" >> ${STAGINGDIR}/logs/${METAFILE}
echo "REV_LOG_URL=${REV_LOG_URL}" >> ${STAGINGDIR}/logs/${METAFILE}
echo "REV_LOG_DETAIL=\"${REV_LOG_DETAIL}\"" >> ${STAGINGDIR}/logs/${METAFILE}

y=${STAGINGDIR}/logs/${METAFILE}; for m in $(md5sum ${y}); do if [[ $m != ${y} ]]; then echo $m > ${y}.MD5; fi; done

# for product, just use the target repository (no need to unpack the zip, which contains different content)
if [[ ${JOB_NAME/.product} != ${JOB_NAME} ]] && [[ -d ${WORKSPACE}/sources/product/site/target/repository ]]; then
  rm -fr ${STAGINGDIR}/all/repo
  mkdir -p ${STAGINGDIR}/all/repo
  #echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
  #echo "1. In ${WORKSPACE}/sources/product/site/target/repository/ ... "
  #echo -n "Packed jars found: "; find ${WORKSPACE}/sources/product/site/target/repository/* -name "*.pack.gz" | wc -l
  #echo -n "Jars found: "; find ${WORKSPACE}/sources/product/site/target/repository/* -name "*.jar" | wc -l
  #echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
  rsync -aq ${WORKSPACE}/sources/product/site/target/repository/* ${STAGINGDIR}/all/repo/
  #echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
  #echo "2. In ${STAGINGDIR}/all/repo/ ... "
  #echo -n "Packed jars found: "; find ${STAGINGDIR}/all/repo/* -name "*.pack.gz" | wc -l
  #echo -n "Jars found: "; find ${STAGINGDIR}/all/repo/* -name "*.jar" | wc -l
  #echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
else
  #echo "$z ..."
  if [[ $z != "" ]] && [[ -f $z ]] ; then
    # unzip into workspace for publishing as unpacked site
    mkdir -p ${STAGINGDIR}/all/repo
    unzip -u -o -q -d ${STAGINGDIR}/all/repo $z

    # generate MD5 sum for zip (file contains only the hash, not the hash + filename)
    for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done

    # unless this is a product build, copy into workspace for access by bucky aggregator (same name every time)
    # TODO: is this still needed?
    if [[ ${JOB_NAME/.product} == ${JOB_NAME} ]]; then
      rsync -aq $z ${STAGINGDIR}/all/${SNAPNAME}
      rsync -aq ${z}.MD5 ${STAGINGDIR}/all/${SNAPNAME}.MD5
    fi
  fi
  z=""
fi

# if component zips exist, copy repository.zip (or site_assembly.zip) too
for z in $(find ${WORKSPACE}/sources/*/site/target -type f -name "repository.zip" -o -name "site_assembly.zip"); do 
  y=${z%%/site/target/*}; y=${y##*/}
  if [[ $y != "aggregate" ]] && [[ $y != "product" ]]; then # prevent duplicate nested sites for aggregate (JBT) and product (JBDS) builds
    #echo "[$y] $z ..."
    # unzip into workspace for publishing as unpacked site
    mkdir -p ${STAGINGDIR}/$y
    unzip -u -o -q -d ${STAGINGDIR}/$y $z
    # copy into workspace for access by bucky aggregator (same name every time)

    # generate MD5 sum for zip (file contains only the hash, not the hash + filename)
    for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done
        
    rsync -aq $z ${STAGINGDIR}/${y}${SUFFNAME}
    rsync -aq ${z}.MD5 ${STAGINGDIR}/${y}${SUFFNAME}.MD5
  fi
done

# if installer jars exist (should be 2 installers, 2 md5sums)
for z in $(find ${WORKSPACE}/sources/product/installer/target -type f -name "jboss-devstudio*-installer*.jar*"); do 
  mkdir -p ${STAGINGDIR}/installer/
  rsync -aq $z ${STAGINGDIR}/installer/
done

# unless this is a product build, if zips exist produced & renamed by ant script, copy them too
if [[ ${JOB_NAME/.product} == ${JOB_NAME} ]] && [[ ! -f ${STAGINGDIR}/all/${SNAPNAME} ]]; then
  for z in $(find ${WORKSPACE} -maxdepth 5 -mindepth 3 -name "*updatesite-*.zip" | sort | tail -1); do 
    #echo "$z ..."
    if [[ -f $z ]]; then
      mkdir -p ${STAGINGDIR}/all
      unzip -u -o -q -d ${STAGINGDIR}/all/ $z

      # generate MD5 sum for zip (file contains only the hash, not the hash + filename)
      for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done

      rsync -aq $z ${STAGINGDIR}/all/${SNAPNAME}
      rsync -aq ${z}.MD5 ${STAGINGDIR}/all/${SNAPNAME}.MD5
    fi
  done
fi

foundSourcesZip=0
# put the JBDS sources into the /installer/ folder
for z in $(find ${WORKSPACE}/sources/product/sources/target -type f -name "jbdevstudio-product-sources-*.zip"); do
  for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done
  mkdir -p ${STAGINGDIR}/installer/
  rsync -aq $z ${z}.MD5 ${STAGINGDIR}/installer/
  foundSourcesZip=1
done
if [[ $foundSourcesZip -eq 0 ]]; then
  # create sources zip
  pushd ${WORKSPACE}/sources
  mkdir -p ${STAGINGDIR}/all
  if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]] && [[ -d ${WORKSPACE}/sources/aggregate/site/zips ]]; then
    srczipname=${SRCSNAME/-Sources-/-Additional-Sources-}
  else
    srczipname=${SRCSNAME}
  fi
  zip ${STAGINGDIR}/all/${srczipname} -q -r * -x hudson_workspace\* -x documentation\* -x download.jboss.org\* -x requirements\* \
    -x workingset\* -x labs\* -x build\* -x \*test\* -x \*target\* -x \*.class -x \*.svn\* -x \*classes\* -x \*bin\* -x \*.zip \
    -x \*docs\* -x \*reference\* -x \*releng\* -x \*.git\* -x \*/lib/\*.jar -x \*getRemoteFile\*
  popd
  z=${STAGINGDIR}/all/${srczipname}; for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done
fi

# JBDS-1992 create results page in installer/ folder, including update site zip, sources zip, and installers
if [[ -d ${WORKSPACE}/sources/product/results/target ]]; then
  mkdir -p ${STAGINGDIR}/installer/
  rsync -aq ${WORKSPACE}/sources/product/results/target/* ${STAGINGDIR}/installer/
fi

# collect component zips from upstream aggregated build jobs
if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]] && [[ -d ${WORKSPACE}/sources/aggregate/site/zips ]]; then
  mkdir -p ${STAGINGDIR}/components
  for z in $(find ${WORKSPACE}/sources/aggregate/site/zips -name "*updatesite-*.zip"); do
    # generate MD5 sum for zip (file contains only the hash, not the hash + filename)
    for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done
    mv $z ${z}.MD5 ${STAGINGDIR}/components
  done

  # TODO :: JBIDE-9870 When we have a -Update-Sources- zip, this can be removed
  mkdir -p ${STAGINGDIR}/all/sources  
  # OLD: unpack component source zips like jbosstools-pi4soa-3.1_trunk-Sources-SNAPSHOT.zip or jbosstools-3.2_trunk.component--ws-Sources-SNAPSHOT.zip
  # NEW: JBIDE-16632: unpack component source zips like jbosstools-base_Alpha2-v20140221-1555-B437_184e18cc3ac7c339ce406974b6a4917f73909cc4_sources.zip
  for z in $(find ${WORKSPACE}/sources/aggregate/site/zips -name "*Sources*.zip" -o -name "*_sources.zip" -o -name "*-src.zip"); do
    zn=${z%*-Sources*.zip}; zn=${zn%*_sources.zip}; zn=${zn%*-src.zip}; zn=${zn#*--}; zn=${zn##*/}; zn=${zn#jbosstools-}; 
    # zn=${zn%_trunk}; zn=${zn%_stable_branch};
    mkdir -p ${STAGINGDIR}/all/sources/${zn}/
    # remove one level of folder nesting - don't want an extra jbosstools-base-184e18cc3ac7c339ce406974b6a4917f73909cc4 folder under jbosstools-base_Alpha2-v20140221-1555-B437_184e18cc3ac7c339ce406974b6a4917f73909cc4
    unzip -qq -o -d ${tmpdir}/${zn}/ $z
    mkdir -p ${STAGINGDIR}/all/sources/${zn}/
    mv ${tmpdir}/${zn}/jbosstools-*/* ${STAGINGDIR}/all/sources/${zn}/
    rm -fr ${tmpdir}/${zn}/
  done
  # add component sources into sources zip
  pushd ${STAGINGDIR}/all/sources
  zip ${STAGINGDIR}/all/${SRCSNAME} -q -r * -x hudson_workspace\* -x documentation\* -x download.jboss.org\* -x requirements\* \
    -x workingset\* -x labs\* -x build\* -x \*test\* -x \*target\* -x \*.class -x \*.svn\* -x \*classes\* -x \*bin\* -x \*.zip \
    -x \*docs\* -x \*reference\* -x \*releng\* -x \*.git\* -x \*/lib/\*.jar -x \*getRemoteFile\*
  popd
  rm -fr ${STAGINGDIR}/all/sources
  z=${STAGINGDIR}/all/${SRCSNAME}; for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done

  # JBIDE-7444 get aggregate metadata xml properties file
  if [[ -f ${WORKSPACE}/sources/aggregate/site/zips/build.properties.all.xml ]]; then
    rsync -aq ${WORKSPACE}/sources/aggregate/site/zips/build.properties.all.xml ${STAGINGDIR}/logs/
  fi
fi


# JBIDE-9870 check if there's a sources update site and rename it if found (note, bottests-site/site/sources won't work; use bottests-site/souces)
for z in $(find ${WORKSPACE}/sources/aggregate/*/sources/target/ -name "repository.zip" -o -name "site_assembly.zip"); do
  echo "Collect sources from update site in $z"
  mv $z ${STAGINGDIR}/all/${SRCSNAME/-src/-updatesite-src}
  for m in $(md5sum ${z}); do if [[ $m != ${z} ]]; then echo $m > ${z}.MD5; fi; done 
done

# generate list of zips in this job
METAFILE=zip.list.txt
echo "ALL_ZIPS = \\" >> ${STAGINGDIR}/logs/${METAFILE}
for z in $(find ${STAGINGDIR} -name "*updatesite-*.zip") $(find ${STAGINGDIR} -name "*Sources*.zip"); do
  # list zips in staging dir
  echo "${z##${STAGINGDIR}/},\\"  >> ${STAGINGDIR}/logs/${METAFILE}
done
echo ""  >> ${STAGINGDIR}/logs/${METAFILE}

# generate md5sums in a single file 
pushd ${STAGINGDIR} >/dev/null
md5sumsFile=${STAGINGDIR}/logs/md5sums.txt
echo "# Update Site Zips" > ${md5sumsFile}
echo "# ----------------" >> ${md5sumsFile}
md5sum $(find . -name "*updatesite-*.zip" | egrep -v -i "aggregate-Sources|src|nightly-update") >> ${md5sumsFile}
echo "  " >> ${md5sumsFile}
echo "# Source Zips" >> ${md5sumsFile}
echo "# -----------" >> ${md5sumsFile}
md5sum $(find . -iname "*src*.zip" | egrep -v -i "aggregate-Sources|src|nightly-update") >> ${md5sumsFile}
echo " " >> ${md5sumsFile}
popd >/dev/null

mkdir -p ${STAGINGDIR}/logs

# copy generated aggregate build results page into root of staging dir
if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]] && [[ -f ${WORKSPACE}/sources/aggregate/site/target/results.html ]]; then
  cp -f ${WORKSPACE}/sources/aggregate/site/target/results.html ${STAGINGDIR}/index.html
fi

# purge duplicate zip files in logs/zips/all/*.zip
if [[ -d ${STAGINGDIR}/logs/zips ]]; then rm -f $(find ${STAGINGDIR}/logs/zips -type f -name "*.zip"); fi

# ${bl} is full build log; see above
mkdir -p ${STAGINGDIR}/logs
# filter out Maven test failures
fl=${STAGINGDIR}/logs/FAIL_LOG.txt
# ignore warning lines and checksum failures
sed -ne "/\[WARNING\]\|CHECKSUM FAILED/ ! p" ${bl} | sed -ne "/<<< FAI/,+9 p" | sed -e "/AILURE/,+9 s/\(.\+AILURE.\+\)/\n----------\n\n\1/g" > ${fl}
sed -ne "/\[WARNING\]\|CHECKSUM FAILED/ ! p" ${bl} | sed -ne "/ FAI/ p" | sed -e "/AILURE \[/ s/\(.\+AILURE \[.\+\)/\n----------\n\n\1/g" >> ${fl}
sed -ne "/\[WARNING\]\|CHECKSUM FAILED/ ! p" ${bl} | sed -ne "/ SKI/ p" | sed -e "/KIPPED \[/ s/\(.\+KIPPED \[.\+\)/\n----------\n\n\1/g" >> ${fl}
fc=$(sed -ne "/FAI\|LURE/ p" ${fl} | wc -l)
if [[ $fc != "0" ]]; then
  echo "" >> ${fl}; echo -n "FAI" >> ${fl}; echo -n "LURES FOUND: "$fc >> ${fl};
fi 
fc=$(sed -ne "/KIPPED/ p" ${fl} | wc -l)
if [[ $fc != "0" ]]; then
  echo "" >> ${fl}; echo -n "SKI" >> ${fl}; echo -n "PS FOUND: "$fc >> ${fl};
fi 
el=${STAGINGDIR}/logs/ERRORLOG.txt
# ignore warning lines and checksum failures
sed -ne "/\[WARNING\]\|CHECKSUM FAILED/ ! p" ${bl} | sed -ne "/<<< ERR/,+9 p" | sed -e "/RROR/,+9 s/\(.\+RROR.\+\)/\n----------\n\n\1/g" > ${el}
sed -ne "/\[WARNING\]\|CHECKSUM FAILED/ ! p" ${bl} | sed -ne "/\[ERR/,+2 p"   | sed -e "/ROR\] Fai/,+2 s/\(.\+ROR\] Fai.\+\)/\n----------\n\n\1/g" >> ${el}
ec=$(sed -ne "/ERR\|RROR/ p" ${el} | wc -l) 
if [[ $ec != "0" ]]; then
  echo "" >> ${el}; echo -n "ERR" >> ${el}; echo "ORS FOUND: "$ec >> ${el};
fi

# publish to download.jboss.org, unless errors found - avoid destroying last-good update site
if [[ $ec == "0" ]] && [[ $fc == "0" ]]; then
  # publish build dir (including update sites/zips/logs/metadata
  if [[ -d ${STAGINGDIR} ]]; then
    
    # if an aggregate build, put output elsewhere on disk
    if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]]; then
      # JBIDE-18102 # echo "<meta http-equiv=\"refresh\" content=\"0;url=${BUILD_ID}-B${BUILD_NUMBER}/\">" > $tmpdir/latestBuild.html
      if [[ ${PUBLISHPATHSUFFIX} ]]; then
        date
        # create folders if not already there
        if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
          seg="."; for d in ${PUBLISHPATHSUFFIX/\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp $DESTINATION/builds/nightly/; done; seg=""
        else
          mkdir -p $DESTINATION/builds/nightly/${PUBLISHPATHSUFFIX}
        fi
        date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/* $DESTINATION/builds/nightly/${PUBLISHPATHSUFFIX}/${BUILD_ID}-B${BUILD_NUMBER}/
        # sftp only works with user@server, not with local $DESTINATIONS, so use rsync to push symlink instead
        # echo -e "rm latest\nln ${BUILD_ID}-B${BUILD_NUMBER} latest" | sftp ${DESTINATIONREDUX}/builds/nightly/${PUBLISHPATHSUFFIX}/ 
        pushd $tmpdir >/dev/null; ln -s ${BUILD_ID}-B${BUILD_NUMBER} latest; rsync --protocol=28 -l latest ${DESTINATION}/builds/nightly/${PUBLISHPATHSUFFIX}/; rm -f latest; popd >/dev/null
        # JBIDE-18102 # date; rsync -arzq --protocol=28 --delete $tmpdir/latestBuild.html $DESTINATION/builds/nightly/${PUBLISHPATHSUFFIX}/
      else
        # JBIDE-18102 # date; rsync -arzq --protocol=28 --delete $tmpdir/latestBuild.html $DESTINATION/builds/nightly/${JOBNAMEREDUX}/ 
        # sftp only works with user@server, not with local $DESTINATIONS, so use rsync to push symlink instead
        # echo -e "rm latest\nln ${BUILD_ID}-B${BUILD_NUMBER} latest" | sftp ${DESTINATIONREDUX}/builds/nightly/${JOBNAMEREDUX}/
        pushd $tmpdir >/dev/null; ln -s ${BUILD_ID}-B${BUILD_NUMBER} latest; rsync --protocol=28 -l latest ${DESTINATION}/builds/nightly/${JOBNAMEREDUX}/; rm -f latest; popd >/dev/null
        date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/* $DESTINATION/builds/nightly/${JOBNAMEREDUX}/${BUILD_ID}-B${BUILD_NUMBER}/
      fi
      # JBIDE-18102 # rm -f $tmpdir/latestBuild.html
    #else
      # COMMENTED OUT as this uses too much disk space
      # if a release build, create a named dir
      #if [[ ${RELEASE} == "Yes" ]]; then
      #  date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/* $DESTINATION/builds/staging/${JOB_NAME}-${ZIPSUFFIX}/
      #fi
    fi

    # and create/replace a snapshot dir w/ static URL
    date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/* $DESTINATION/builds/staging/${JOB_NAME}.next

    # 1. To recursively purge contents of .../staging.previous/foobar/ folder: 
    #  mkdir -p $tmpdir/foobar; 
    #  rsync -aPrz --delete $tmpdir/foobar tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging.previous/ 
    # 2. To then remove entire .../staging.previous/foobar/ folder: 
    #  echo -e "rmdir foobar" | sftp tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging.previous/
    #  rmdir $tmpdir/foobar

    # JBIDE-8667 move current to previous; move next to current
    if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
      # create folders if not already there (could be empty)
      echo -e "mkdir ${JOB_NAME}" | sftp $DESTINATION/builds/staging/
      echo -e "mkdir ${JOB_NAME}" | sftp $DESTINATION/builds/staging.previous/
      #echo -e "mkdir ${JOB_NAME}.2" | sftp $DESTINATION/builds/staging.previous/

      # IF using .2 folders, purge contents of /builds/staging.previous/${JOB_NAME}.2 and remove empty dir
      # NOTE: comment out next section - should only purge one staging.previous/* folder
      #mkdir -p $tmpdir/${JOB_NAME}.2
      #rsync -arzq --delete --protocol=28 $tmpdir/${JOB_NAME}.2 $DESTINATION/builds/staging.previous/
      #echo -e "rmdir ${JOB_NAME}.2" | sftp $DESTINATION/builds/staging.previous/
      #rmdir $tmpdir/${JOB_NAME}.2

      # OR, purge contents of /builds/staging.previous/${JOB_NAME} and remove empty dir
      mkdir -p $tmpdir/${JOB_NAME}
      rsync -arzq --protocol=28 --delete $tmpdir/${JOB_NAME} $DESTINATION/builds/staging.previous/
      echo -e "rmdir ${JOB_NAME}" | sftp $DESTINATION/builds/staging.previous/
      rmdir $tmpdir/${JOB_NAME}

      # move contents of /builds/staging.previous/${JOB_NAME} into /builds/staging.previous/${JOB_NAME}.2
      #echo -e "rename ${JOB_NAME} ${JOB_NAME}.2" | sftp $DESTINATION/builds/staging.previous/

      # move contents of /builds/staging/${JOB_NAME} into /builds/staging.previous/${JOB_NAME}
      echo -e "rename ${JOB_NAME} ../staging.previous/${JOB_NAME}" | sftp $DESTINATION/builds/staging/

      # move contents of /builds/staging/${JOB_NAME}.next into /builds/staging/${JOB_NAME}
      echo -e "rename ${JOB_NAME}.next ${JOB_NAME}" | sftp $DESTINATION/builds/staging/
    else # work locally
      # create folders if not already there (could be empty)
      mkdir -p $DESTINATION/builds/staging/${JOB_NAME}
      mkdir -p $DESTINATION/builds/staging.previous/${JOB_NAME}
      #mkdir -p $DESTINATION/builds/staging.previous/${JOB_NAME}.2

      # purge contents of /builds/staging.previous/${JOB_NAME}.2 and remove empty dir
      # NOTE: comment out next section - should only purge one staging.previous/* folder
      #rm -fr $DESTINATION/builds/staging.previous/${JOB_NAME}.2/
      
      # OR, purge contents of /builds/staging.previous/${JOB_NAME} and remove empty dir
      rm -fr $DESTINATION/builds/staging.previous/${JOB_NAME}/

      # move contents of /builds/staging.previous/${JOB_NAME} into /builds/staging.previous/${JOB_NAME}.2
      #mv $DESTINATION/builds/staging.previous/${JOB_NAME} $DESTINATION/builds/staging.previous/${JOB_NAME}.2

      # move contents of /builds/staging/${JOB_NAME} into /builds/staging.previous/${JOB_NAME}
      mv $DESTINATION/builds/staging/${JOB_NAME} $DESTINATION/builds/staging.previous/${JOB_NAME}

      # move contents of /builds/staging/${JOB_NAME}.next into /builds/staging/${JOB_NAME}
      mv $DESTINATION/builds/staging/${JOB_NAME}.next $DESTINATION/builds/staging/${JOB_NAME}
    fi

    # generate 2 ${STAGINGDIR}/all/composite*.xml files which will point at:
      # /builds/staging/${JOB_NAME}/all/repo/
      # /builds/staging.previous/${JOB_NAME}/all/repo/
      # /builds/staging.previous/${JOB_NAME}.2/all/repo/
    now=$(date +%s000)
    mkdir -p ${STAGINGDIR}/all
    echo "<?xml version='1.0' encoding='UTF-8'?>
<?compositeMetadataRepository version='1.0.0'?>
<repository name='JBoss Tools Staging - ${JOB_NAME} Composite' type='org.eclipse.equinox.internal.p2.metadata.repository.CompositeMetadataRepository' version='1.0.0'>
" > ${STAGINGDIR}/all/compositeContent.xml
    echo "<?xml version='1.0' encoding='UTF-8'?>
<?compositeArtifactRepository version='1.0.0'?>
<repository name='JBoss Tools Staging - ${JOB_NAME} Composite' type='org.eclipse.equinox.internal.p2.artifact.repository.CompositeArtifactRepository' version='1.0.0'> " > ${STAGINGDIR}/all/compositeArtifacts.xml
    metadata="<properties size='2'><property name='p2.compressed' value='true'/><property name='p2.timestamp' value='"${now}"'/></properties>
<children size='2'>
<child location='../../../staging/${JOB_NAME}/all/repo/'/>
<child location='../../../staging.previous/${JOB_NAME}/all/repo/'/>
</children>
</repository>
"
    echo $metadata >> ${STAGINGDIR}/all/compositeContent.xml
    echo $metadata >> ${STAGINGDIR}/all/compositeArtifacts.xml
    date; rsync -arzq --protocol=28 ${STAGINGDIR}/all/composite*.xml $DESTINATION/builds/staging/${JOB_NAME}/all/

    # create a snapshot dir outside Hudson which is file:// accessible
    mkdir -p $INTRNALDEST/builds/staging/${JOB_NAME}.next/
    date; rsync -arzq --delete ${STAGINGDIR}/* $INTRNALDEST/builds/staging/${JOB_NAME}.next/

    # cycle internal copy of ${JOB_NAME} in staging and staging.previous
    mkdir -p $INTRNALDEST/builds/staging/${JOB_NAME}/
    # purge contents of /builds/staging.previous/${JOB_NAME} and remove empty dir
    rm -fr $INTRNALDEST/builds/staging.previous/${JOB_NAME}/
    # move contents of /builds/staging/${JOB_NAME} into /builds/staging.previous/${JOB_NAME}
    mv $INTRNALDEST/builds/staging/${JOB_NAME} $INTRNALDEST/builds/staging.previous/${JOB_NAME}
    # move contents of /builds/staging/${JOB_NAME}.next into /builds/staging/${JOB_NAME}
    mv $INTRNALDEST/builds/staging/${JOB_NAME}.next $INTRNALDEST/builds/staging/${JOB_NAME}
  fi

  # extra publish step for aggregate update sites ONLY
  if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]]; then
    if [[ ${PUBLISHPATHSUFFIX} ]]; then 
      # create folders if not already there
      if [[ ${DESTINATION##*@*:*} == "" ]]; then # user@server, do remote op
        seg="."; for d in ${PUBLISHPATHSUFFIX/\// }; do seg=$seg/$d; echo -e "mkdir ${seg:2}" | sftp $DESTINATION/updates/nightly/; done; seg=""
      else
        mkdir -p $DESTINATION/updates/nightly/${PUBLISHPATHSUFFIX}
      fi
      date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/all/repo/* $DESTINATION/updates/nightly/${PUBLISHPATHSUFFIX}/
    else
      date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/all/repo/* $DESTINATION/updates/nightly/${JOBNAMEREDUX}/
    fi
    echo ">> ${PUBLISHEDSITE} <<"
  fi
fi
date

# purge org.jboss.tools metadata from local m2 repo (assumes job is configured with -Dmaven.repo.local=${WORKSPACE}/m2-repo)
if [[ -d ${WORKSPACE}/m2-repo/org/jboss/tools ]]; then
  rm -rf ${WORKSPACE}/m2-repo/org/jboss/tools
fi

# publish updated log
bl=${STAGINGDIR}/logs/BUILDLOG.txt

rm -f ${bl}
getRemoteFile "http://jenkins.mw.lab.eng.bos.redhat.com/hudson/job/${JOB_NAME}/${BUILD_NUMBER}/consoleText"; if [[ -w ${getRemoteFileReturn} ]]; then mv ${getRemoteFileReturn} ${bl}; fi
date; rsync -arzq --protocol=28 --delete ${STAGINGDIR}/logs $DESTINATION/builds/staging/${JOB_NAME}/
date; rsync -arzq --delete ${STAGINGDIR}/logs $INTRNALDEST/builds/staging/${JOB_NAME}/

# purge tmpdir
rm -fr $tmpdir

# purge getRemoteFile tmpfiles
find ${WORKSPACE} -maxdepth 2 -name "getRemoteFile*" -type f -exec rm -f {} \;

if [[ ${JOB_NAME/.aggregate} != ${JOB_NAME} ]]; then
  	# regenerate http://download.jboss.org/jbosstools/builds/nightly/*/*/composite*.xml files for up to 5 builds, cleaning anything older than 5 days old
	pushd ../util/cleanup
	chmod +x jbosstools-cleanup.sh
	./jbosstools-cleanup.sh --keep 5 --age-to-delete 5 --childFolderSuffix /all/repo/
	popd
fi

# to avoid looking for files that are still being synched/nfs-copied, wait a bit before trying to run tests (the next step usually)
sleep 15s
