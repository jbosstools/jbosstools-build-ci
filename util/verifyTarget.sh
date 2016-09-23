#!/bin/bash

# commandline args:

# point BASEDIR to where you have jbosstools-discovery, jbosstools-target-platforms, or jbosstools-integration-stack sources checked out
# ideally, you would run this script from that folder, or set 
# -b /path/to/jbosstools-discovery
# If running in the current directory, use 
# -b `pwd`

# comma-separated list of projects to build
# -p jbtcentral,jbtearlyaccess
# -p jbosstools,jbdevstudio

# OPTIONAL if you want to perform an install test, rather than just ensure that your TP can be validated and resolved locally
# set path to where you have the latest compatible Eclipse bundle stored locally
# -z /path/to/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz

# OPTIONAL if you're testing a TP that's downstream from the jbosstoolstarget or jbdevstudiotarget, eg., Central, Early Access, or Integration Stack
# set URL(s) for JBT / JBT Target so that all Central deps can be resolved; for more than one, separate w/ commas
# -u file://$HOME/tru/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/,http://download.jboss.org/jbosstools/updates/nightly/core/master/
# for JBDS Central tests, use:
# -u file://$HOME/tru/jbosstools-target-platforms/jbdevstudio/multiple/target/jbdevstudio-multiple.target.repo/,http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.product_master/all/repo/

# OPTIONAL if you want to perform a p2diff between your last version of the TP and the one you're about to build
# set path to where you have the latest p2diff executable installed
# -d ${HOME}/tmp/p2diff/p2diff

usage ()
{
  echo "Usage: $0 -b BASEDIR -p PROJECT1,PROJECT2,... [-z ECLIPSEZIP] [-u UPSTREAM_SITES] [-d P2DIFF] [-x]"
  echo ""
  echo "Example (JBT/JBDS - include sources): $0 \\"
  echo "  -b /path/to/jbosstools-target-platforms -p jbosstools,jbdevstudio \\"
  echo "  -z /path/to/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz -d /path/to/executable/p2diff"
  echo ""
  echo "Example (JBoss Central - eXclude sources): $0 \\"
  echo "  -b /path/to/jbosstools-discovery -p jbtcentral -x \\"
  echo "  -z /path/to/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz  -d /path/to/executable/p2diff \\"
  echo "  -u http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/4.61.0.AM1-SNAPSHOT/"
  echo "          or, use locally built sites"
  echo "  -u file:///path/to/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/"
  echo ""
  echo "Example (JBoss Central Early Access - eXclude sources): $0 \\"
  echo "  -b /path/to/jbosstools-discovery -p jbtearlyaccess -x \\"
  echo "  -z /path/to/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz -d /path/to/executable/p2diff \\"
  echo "  -u http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/4.61.0.AM1-SNAPSHOT/,\\
http://download.jboss.org/jbosstools/targetplatforms/jbtcentraltarget/4.61.0.AM1-SNAPSHOT/"
  echo "          or, use locally built sites"
  echo "  -u file:///path/to/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/,\\
file:///path/to/jbosstools-discovery/jbtcentraltarget/multiple/target/jbtcentral-multiple.target.repo/"
  echo ""
  echo "Example (JBoss Tools Integration Stack - include sources): $0 \\"
  echo "  -b /path/to/jbosstools-integration-stack/target-platform -p target-platform \\"
  echo "  -z /path/to/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz -d /path/to/executable/p2diff"
  echo ""
  exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

# defaults
MVN="mvn"
MRL="" # placeholder for -Dmaven.repo.local, if used
Dflags="" # placeholer for additional -D flags to pass to maven, eg., -DTARGET_PLATFORM_VERSION_MAXIMUM=4.61.0.AM1-SNAPSHOT
includeSources="-Dmirror-target-to-repo.includeSources=true" # by default, include sources
INSTALLSCRIPT=/tmp/installFromTarget.sh
LOG_GREP_INCLUDES="BUILD FAILURE|Only one of the following|Missing requirement|Unresolved requirement|IllegalArgumentException|Could not resolve|could not be found|being installed|Cannot satisfy dependency|FAILED"
LOG_GREP_INCLUDES2="TargetDefinitionResolutionException|Could not find"
LOG_GREP_EXCLUDES="Could not find metadata|Failed to execute goal org.jboss.tools.tycho-plugins:target-platform-utils|Checksum validation failed, no checksums available from the repository"
#BASEDIR=`pwd`
#ECLIPSEZIP=${HOME}/tmp/Eclipse_Bundles/eclipse-jee-neon-R-linux-gtk-x86_64.tar.gz
#UPSTREAM_SITES=file://$HOME/tru/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/,http://download.jboss.org/jbosstools/updates/nightly/core/master/
# for JBDS tests, use UPSTREAM_SITES=file://$HOME/tru/jbosstools-target-platforms/jbdevstudio/multiple/target/jbdevstudio-multiple.target.repo/,http://www.qa.jboss.com/binaries/RHDS/builds/staging/devstudio.product_master/all/repo/
#P2DIFF=${HOME}/tmp/p2diff/p2diff

# use Eclipse VM from JAVA_HOME if available
if [[ -x ${JAVA_HOME}/bin/java ]]; then VM="-vm ${JAVA_HOME}/bin/java"; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') BASEDIR="$2"; shift 1;;
    '-z') ECLIPSEZIP="$2"; shift 1;;
    '-u') UPSTREAM_SITES="$2"; shift 1;;
    '-d') P2DIFF="$2"; shift 1;;
    '-p') PROJECTS="$PROJECTS $2"; shift 1;;
    '-m') MVN="$2"; shift 1;;
    '-x') includeSources=""; shift 0;;
    '-V') targetplatformutilsversion="$2"; shift 1;;
    '-vm') VM="-vm $2"; shift 1;;
    '-mrl') MRL="-Dmaven.repo.local=$2"; shift 1;;
    '-D'*) Dflags="${Dflags} $1"; shift 1;;
  esac
  shift 1
done

if [[ ! $BASEDIR ]]; then
  echo ""; echo "Error: BASEDIR not set; to run in current directory, use -p "'`pwd`'; echo ""; usage;
fi
if [[ ! -d $BASEDIR ]]; then
  echo ""; echo "Error: BASEDIR is not a directory; to run in current directory, use -p "'`pwd`'; echo ""; usage;
fi
if [[ ! $PROJECTS ]]; then
  echo ""; echo "Error: PROJECTS not set!"; echo ""; usage;
fi

# replace commas for spaces so we can for-loop through the projects
PROJECTS=${PROJECTS//,/ }
NOW=`date +%F_%H-%M`

if [[ ! $targetplatformutilsversion ]]; then
  # eg., 0.22.1-SNAPSHOT
  targetplatformutilsversion=`cat ${BASEDIR}/pom.xml | egrep "jbossTychoPluginsVersion|util" -B2 -A2 | egrep "version|jbossTychoPluginsVersion" | sed -e "s#.\+<version>\(.\+\)</version>.*#\1#" -e "s#.\+<jbossTychoPluginsVersion>\(.\+\)</jbossTychoPluginsVersion>.*#\1#" | head -1`
fi

for PROJECT in $PROJECTS; do echo "Process $PROJECT ..."

  if [[ -d ${BASEDIR}/${PROJECT}target ]]; then 
    WORKSPACE=${BASEDIR}/${PROJECT}target
  elif [[ -d ${BASEDIR}/${PROJECT} ]]; then 
    WORKSPACE=${BASEDIR}/${PROJECT}
  else 
    WORKSPACE=${BASEDIR}
  fi

  # JBoss Tools uses /multiple/ folders and multiple2repo profile
  # Integration Stack uses /target-platform/ folder and isbtp2repo profile
  # so check which convention to use
  if [[ -d ${WORKSPACE}/target-platform ]]; then
    WORKDIR=${WORKSPACE}/target-platform
    REPODIR=target-platform.target.repo
    PROFILE=isbtp2repo
  elif [[ -d ${WORKSPACE}/../target-platform ]]; then
    WORKDIR=${WORKSPACE}
    REPODIR=target-platform.target.repo
    PROFILE=isbtp2repo
  elif [[ -d ${WORKSPACE}/multiple ]]; then
    WORKDIR=${WORKSPACE}/multiple
    REPODIR=${PROJECT}-multiple.target.repo
    PROFILE=multiple2repo
  fi

  if [[ ! -d ${WORKDIR} ]]; then
    echo "Error: cannot find WORKDIR = ${WORKDIR} - must exit!"
    exit 1
  fi

  # TODO: remember to clean these out from /tmp
  if [[ -d ${WORKDIR}/target/${REPODIR}/ ]] && [[ ${P2DIFF} ]] && [[ -x ${P2DIFF} ]]; then
    echo ""
    echo "Step 0: To prepare to p2diff your last target platform against the one you're about to build,"
    echo "        backup (move) the existing target platform folder to /tmp/${REPODIR}_${NOW} ..."
    echo ""
    mv ${WORKDIR}/target/${REPODIR}/ /tmp/${REPODIR}_${NOW} && touch /tmp/${REPODIR}_${NOW}
  fi

  echo ""
  echo "Step 1: Merge changes in new target file produce corrected/updated target file,"
  echo "        replacing any 0.0.0 or obsolete versions with latest versions ..."
  echo ""
  pushd ${WORKDIR}

  for tf in *.target; do
    if [[ ${tf/_fixedVersion.target} == ${tf} ]]; then 
      logfile=/tmp/fix-versions_${tf}_log_${PROJECT}_${NOW}.txt
      echo "${MVN} ${MRL} ${Dflags} -U org.jboss.tools.tycho-plugins:target-platform-utils:${targetplatformutilsversion}:fix-versions -DtargetFile=${tf}" | tee $logfile
      ${MVN} ${MRL} ${Dflags} -U -c org.jboss.tools.tycho-plugins:target-platform-utils:${targetplatformutilsversion}:fix-versions -DtargetFile=${tf} | tee -a $logfile
      egrep -i -v "$LOG_GREP_EXCLUDES" $logfile | egrep -i -A2 "$LOG_GREP_INCLUDES"; if [[ "$?" == "0" ]]; then break 2; fi
      if [[ -f ${tf}_fixedVersion.target ]]; then rm -f ${tf} *_update_hints.txt; mv -f ${tf}{_fixedVersion.target,}; fi
    fi
  done
  popd

  echo ""
  if [[ ${includeSources} ]]; then
    echo "Step 2: Resolve target platform (including sources). This may take"
  else
    echo "Step 2: Resolve target platform (EXCLUDING sources). This may take"
  fi
  echo "        more than an hour depending on network performance ... "
  echo ""

  # TODO: if you removed IUs, be sure to do a `mvn clean install`, rather than just a `mvn install`; process will be much longer but will guarantee metadata is correct
  pushd ${WORKSPACE}
  logfile=/tmp/resolve_log_${PROJECT}_${NOW}.txt
  echo "${MVN} ${MRL} ${Dflags} -U install -P${PROFILE} -DtargetRepositoryUrl=file://${WORKDIR}/target/${REPODIR}/ ${includeSources} -X" | tee $logfile
  ${MVN} ${MRL} ${Dflags} install -P${PROFILE} -DtargetRepositoryUrl=file://${WORKDIR}/target/${REPODIR}/ ${includeSources} -X | tee -a $logfile
  egrep -i -v "$LOG_GREP_EXCLUDES" $logfile | egrep -i -A2 "$LOG_GREP_INCLUDES|$LOG_GREP_INCLUDES2"; if [[ "$?" == "0" ]]; then break 2; fi

  popd

  # check for duplicate IUs in the TP
  echo ""
  for pf in plugins features; do
    if [[ -d ${WORKDIR}/target/${REPODIR}/${pf} ]]; then
      allIUs=$(cd ${WORKDIR}/target/${REPODIR}/${pf};ls *.jar|sort)
      rm -f /tmp/resolve_log_dupeIUs_${PROJECT}_${NOW}.txt /tmp/resolve_log_allIUs_${PROJECT}_${NOW}.txt
      for iu in $allIUs; do
        echo  ${iu%_*.jar} >> /tmp/resolve_log_allIUs_${PROJECT}_${NOW}.txt
      done
      cat /tmp/resolve_log_allIUs_${PROJECT}_${NOW}.txt | uniq -d | sort > /tmp/resolve_log_dupeIUs_${PROJECT}_${NOW}.txt
      numFound=$(cat /tmp/resolve_log_dupeIUs_${PROJECT}_${NOW}.txt | wc -l)
      if [[ $numFound != 0 ]]; then
        # dupe features = error; dupe plugins = warning
        if [[ $pf == "features" ]]; then prefix="[ERROR] "; else prefix="[WARNING] "; fi
        echo "$prefix Found ${numFound} duplicate ${PROJECT} ${pf}:"
        c=0
        for i in $(cat /tmp/resolve_log_dupeIUs_${PROJECT}_${NOW}.txt); do
          (( c++ ));
          pushd ${WORKDIR} >/dev/null
            find target/${REPODIR}/${pf} -name "${i}_*.jar" | sed "s#target/#${prefix} [${c}] #" | tee -a /tmp/resolve_log_dupeIUs_${PROJECT}_${NOW}.txt
          popd >/dev/null
          echo ""
        done
        # dupe features = error; dupe plugins = warning
        if [[ $pf == "features" ]]; then exit 1; fi
      else
        rm -f /tmp/resolve_log_dupeIUs_${PROJECT}_${NOW}.txt /tmp/resolve_log_allIUs_${PROJECT}_${NOW}.txt
      fi
    else
      echo "[WARNING] No directory ${WORKDIR}/target/${REPODIR}/${pf} - cannot check for duplicate IUs!"
    fi
  done

  if [[ -f ${ECLIPSEZIP} ]]; then 
    echo ""
    echo "Step 3: Install the new target platform into a clean Eclipse JEE bundle"
    echo "        to verify that everything can be installed ..."
    echo ""
    INSTALLDIR=/tmp/${PROJECT}target-install-test
    rm -fr ${INSTALLDIR} && mkdir -p ${INSTALLDIR}
    pushd ${INSTALLDIR}
      echo "  Unpack ${ECLIPSEZIP} into ${INSTALLDIR} ..."
      tar xzf ${ECLIPSEZIP}
      # this file should already be in the workspace if you're running with Jenkins using
      # https://repository.jboss.org/nexus/content/repositories/snapshots/org/jboss/tools/releng/jbosstools-releng-publish/
      # but just in case fall back to github
      if [[ ! -f ${WORKSPACE}/sources/util/installFromTarget.sh ]]; then
        echo "  Fetch target install script to ${INSTALLSCRIPT} ..." 
        wget -q --no-check-certificate -N https://raw.githubusercontent.com/jbosstools/jbosstools-build-ci/jbosstools-4.4.x/util/installFromTarget.sh -O ${INSTALLSCRIPT}
      else
        cp -f ${WORKSPACE}/sources/util/installFromTarget.sh ${INSTALLSCRIPT}
      fi
      chmod +x ${INSTALLSCRIPT}
      echo "  Install..."
      logfile=${INSTALLSCRIPT}_log_${PROJECT}_${NOW}.txt
      if [[ ${UPSTREAM_SITES} ]]; then
        ${INSTALLSCRIPT} -ECLIPSE ${INSTALLDIR}/eclipse ${VM} -INSTALL_PLAN ${UPSTREAM_SITES},file://${WORKDIR}/target/${REPODIR}/ | tee $logfile
      else
        echo ""
        echo "  No UPSTREAM_SITES specified. If installation fails, try adding more upstream sites to help resolving dependencies."
        echo ""
        ${INSTALLSCRIPT} -ECLIPSE ${INSTALLDIR}/eclipse ${VM} -INSTALL_PLAN file://${WORKDIR}/target/${REPODIR}/ | tee $logfile
      fi
      echo ""
      echo "  Scan log ( ${INSTALLSCRIPT}_log_${PROJECT}_${NOW}.txt ) for errors ..."
      echo ""
      egrep -i -v "$LOG_GREP_EXCLUDES" $logfile | egrep -i -A2 "$LOG_GREP_INCLUDES"; if [[ "$?" == "0" ]]; then break 2; fi
    popd
  else
    echo ""
    echo "Step 3: no ECLIPSEZIP specified, so cannot perform installation test."
    echo ""
  fi

  if [[ ${P2DIFF} ]] && [[ -x ${P2DIFF} ]] && [[ -d /tmp/${REPODIR}_${NOW} ]]; then
    echo ""
    echo "Step 4: produce p2diff report ..."
    echo ""
    ${P2DIFF} /tmp/${REPODIR}_${NOW} file://${WORKDIR}/target/${REPODIR}/ | tee /tmp/p2diff_log_${PROJECT}_${NOW}.txt
  elif [[ ! -d /tmp/${REPODIR}_${NOW} ]]; then
    echo ""
    echo "Step 4: previous target platform does not exist in /tmp/${REPODIR}_${NOW} - nothing to diff."
  elif [[ ${P2DIFF} ]]; then
    echo ""
    echo "Step 4: cannot execute p2diff from ${P2DIFF} - nothing to do."
  else
    echo ""
    echo "Step 4: no P2DIFF specified, so cannot perform p2diff."
  fi

done

echo ""
echo "Logs & temporary files ($NOW)"
echo "-----------------------------------------"
echo ""
for d in /tmp/${REPODIR}_${NOW} /tmp/fix-versions_*_log_${PROJECT}_${NOW}.txt /tmp/resolve_log_${PROJECT}_${NOW}.txt ${INSTALLSCRIPT}_log_${PROJECT}_${NOW}.txt ${INSTALLDIR} /tmp/p2diff_log_${PROJECT}_${NOW}.txt; do
  if [[ -f $d ]] || [[ -d $d ]]; then
    echo "* $d"
  fi
done
