#!/bin/bash
# Script to copy a CI build to staging for QE review
# From Jenkins, call this script 7 times in parallel (&) then call wait to block until they're all done

# TODO: should this script call rsync.sh (for build copy + symlink gen, and for update site copy w/ --del?) instead of using rsync?
# TODO: add support for JBDS staging steps
#  - see https://github.com/jbdevstudio/jbdevstudio-devdoc/blob/master/release_guide/9.x/JBDS_Staging_for_QE.adoc#push-installers-update-site-and-discovery-site
# TODO: create Jenkins job(s)
# TODO: use sshfs to copy files instead of a pull-to-tmp,push-from-tmp model
# TODO: add verification steps - wget or curl the destination URLs and look for 404s or count of matching child objects
#  - see end of https://github.com/jbdevstudio/jbdevstudio-devdoc/blob/master/release_guide/9.x/JBDS_Staging_for_QE.adoc#push-installers-update-site-and-discovery-site

DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools # or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio or /qa/services/http/binaries/RHDS
DEST_URL="http://download.jboss.org/jbosstools"
whichID=latest
PRODUCT="jbosstools"
ZIPPREFIX="jbosstools-"
SRC_TYPE="snapshots"
DESTTYPE="staging"
rawJOB_NAME="\${PRODUCT}-\${site}_\${stream}"
sites=""
quiet=0

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"

log ()
{
  if [[ $quiet == 0 ]]; then echo -e $1; fi
}

# can be used to publish a build (including installers, site zips, MD5s, build log) or just an update site folder
usage ()
{
  echo "Usage  : $0 -sites \"site1 site2 ...\" -stream STREAM -vr versionWithRespin -sd SRC_DIR [-dd DESTDIR] [-st SRC_TYPE] [-dt DESTTYPE] \\"
  echo "            [-JOB_NAME JOB_NAME] [-DESTINATION user@server:/path] [-DEST_URL http://server.url] [-WORKSPACE WORKSPACE] [-ID ID] [-q]"
  echo ""

  echo "To stage JBT core, coretests, central & earlyaccess (4 builds)"
  echo "   $0 -sites \"site coretests-site central-site earlyaccess-site\" -stream 4.3.mars -vr 4.3.1.CR1a -sd mars -JOB_NAME jbosstools-build-sites.aggregate.\\\${site}_\\\${stream}"
  echo "To stage JBT discovery.* sites & browsersim-standalone (3 builds)"
  echo "   $0 -sites \"discovery.central discovery.earlyaccess browsersim-standalone\" -stream 4.3.mars -vr 4.3.1.CR1a -sd mars -q"
  echo ""

  echo "To stage JBDS product (1 build)"
  echo "   $0 -sites product -stream 9.0.mars -vr 9.1.0.CR1c -sd 9.0 -JOB_NAME devstudio.\\\${site}_\\\${stream} \\"
  echo "      -DESTINATION \${JBDS} -DEST_URL https://devstudio.redhat.com -q &"
  echo "To stage JBDS discovery sites (4 builds)"
  echo "   $0 -sites \"central-site earlyaccess-site discovery.central discovery.earlyaccess\" -stream 4.3.mars -vr 9.1.0.CR1c -sd 9.0 -JOB_NAME jbosstools-\\\${site}_\\\${stream} \\"
  echo "      -DESTINATION \${JBDS} -DEST_URL https://devstudio.redhat.com -q"
  echo "(NOTE: must also publish target platform zips; that step is not yet covered here.)"
  echo ""

  echo "To release a JBT milestone (7 builds)"
  echo "   for site in site coretests-site central-site earlyaccess-site discovery.central discovery.earlyaccess browsersim-standalone; do \\"
  echo "     $0 -sites \$site -stream 4.3.1.CR1c -vr 4.3.1.Final -sd mars -dd static/mars -st staging -dt development -JOB_NAME jbosstools-\\\${stream}-build-\\\${site}; \\"
  echo "   done"
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-sites') sites="${sites} $2"; shift 1;; # site coretests-site central-site earlyaccess-site discovery.central discovery.earlyaccess
  
    '-stream') stream="$2"; shift 1;; # for staging, use 4.3.mars or 9.0.mars; for release, use the versionWithRespin value, eg., 4.3.1.CR1c or 9.1.0.CR1c
    '-versionWithRespin'|'-vr') versionWithRespin="$2"; shift 1;; # for staging, use 4.3.1.CR1c, 9.1.0.CR1c; for release, use 4.3.1.Final or 9.1.0.GA

    '-SRC_DIR'|'-sd') SRC_DIR="$2"; shift 1;; # mars or 9.0 or neon or 10.0 (if not set, default to same value as DESTDIR)
    '-DESTDIR'|'-dd') DESTDIR="$2"; shift 1;; # mars or 9.0 or neon or 10.0, or could be static/mars, static/9.0, etc.

    '-SRC_TYPE'|'-st') SRC_TYPE="$2"; shift 1;; # by default, snapshots but could be staging? (TODO: UNTESTED!)
    '-DESTTYPE'|'-dt') DESTTYPE="$2"; shift 1;; # by default, staging but could be development? (TODO: UNTESTED!)

    '-DJOB_NAME'|'-JOB_NAME') rawJOB_NAME="$2"; shift 1;;

    '-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., devstudio@filemgmt.jboss.org:/www_htdocs/devstudio or /qa/services/http/binaries/RHDS
    '-DEST_URL')    DEST_URL="$2"; shift 1;; # override for JBDS publishing, eg., https://devstudio.redhat.com or http://www.qa.jboss.com/binaries/RHDS

    '-DWORKSPACE'|'-WORKSPACE') WORKSPACE="$2"; shift 1;; # optional
    '-DID'|'-ID') whichID="$2"; shift 1;; # optionally, set a specific build ID such as 2015-10-02_18-28-18-B124; if not set, pull latest
    '-q') quiet=1; shift 0;; # suppress extra console output
    *) OTHERFLAGS="${OTHERFLAGS} $1"; shift 0;;
  esac
  shift 1
done

if [[ $quiet == 1 ]]; then consoleDest=/dev/null; else
  if [[ -w $(tty) ]]; then consoleDest=$(tty);
  elif [[ -w /dev/tty ]]; then consoleDest=/dev/tty;
  elif [[ -w /dev/tty0 ]]; then consoleDest=/dev/tty0;
  elif [[ -w /dev/console ]]; then consoleDest=/dev/console; fi
fi

# set mars, 9.0, etc.
if [[ ! ${DESTDIR} ]] && [[ ! ${SRC_DIR} ]]; then echo "ERROR: DESTDIR and SRC_DIR not set. Please set at least one."; echo ""; usage; fi

# if one set and not the other, set DESTDIR and SRC_DIR equal to each other
if [[ ! ${DESTDIR} ]] && [[ ${SRC_DIR} ]]; then DESTDIR="${SRC_DIR}"; fi
if [[ ! ${SRC_DIR} ]] && [[ ${DESTDIR} ]]; then SRC_DIR="${DESTDIR}"; fi

if [[ ${DESTINATION/devstudio/} != ${DESTINATION} ]] || [[ ${DESTINATION/RHDS/} != ${DESTINATION} ]]; then
  PRODUCT="devstudio"
  ZIPPREFIX="devstudio-"
fi

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=${tmpdir}; fi

RSYNC="time rsync -arz --rsh=ssh --protocol=28"
EXCLUDESTRING="--exclude=\"repo\"" # exclude mirroring the update site repo/ folder for all builds
SSHFS=$(which sshfs 2>/dev/null)

# mount an sshfs drive for the destination path
mount_sshfs ()
{
  log "[DEBUG] Use SSHFS in ${SSHFS} instead of RSYNC to stage files"
  if [[ ! -d ${HOME}/DEST-ssh/${SRC_DIR} ]]; then
    fusermount -u ${HOME}/DEST-ssh
    /bin/mkdir -p ${HOME}/DEST-ssh
    sshfs ${DESTINATION} ${HOME}/DEST-ssh
  fi
  if [[ ! -d ${HOME}/DEST-ssh/${SRC_DIR} ]]; then
    echo "[WARN] Could not mount ${DESTINATION}/${SRC_DIR} at ${HOME}/DEST-ssh/${SRC_DIR} - fall back to '${RSYNC}'"; SSHFS=""
  fi
}

# if sshfs is installed and executable, mount an sshfs drive for $DESTINATION
# but don't mount for DESTINATION=/qa/services/http/binaries/RHDS (local copy)
if [[ ${SSHFS} ]] && [[ -x ${SSHFS} ]] && [[ ${DESTINATION##*@*} == "" ]]; then mount_sshfs; fi

for site in ${sites}; do
  # evaluate site or stream variables embedded in JOB_NAME
  if [[ ${rawJOB_NAME/\$\{site\}} != ${rawJOB_NAME} ]] || [[ ${rawJOB_NAME/\$\{stream\}} != ${rawJOB_NAME} ]]; then JOB_NAME=$(eval echo ${rawJOB_NAME}); fi

  if [[ ${whichID} == "latest" ]]; then
    ID=""
    log "[DEBUG] [$site] + Check ${DEST_URL}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}" | egrep "${grepstring}"
    if [[ ${DESTINATION/@/} == ${DESTINATION} ]]; then # local
      ID=$(ls ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME} | grep "20.\+" | grep -v sftp | sort | tail -1)
    else # remote
      ID=$(echo "ls 20*" | sftp ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME} 2>&1 | grep "20.\+" | grep -v sftp | sort | tail -1)
    fi
    ID=${ID%%/*}
    if [[ ${ID} ]]; then
      echo -e "[INFO] [$site] In ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME} found ID = ${green}${ID}${norm}" | egrep "${JOB_NAME}|${site}|${ID}|ERROR"
    else
      log "[ERROR] [$site] No latest build found for ${red}${JOB_NAME}${norm} :: ${red}${site}${norm} :: ${red}${ID}${norm}" | egrep "${grepstring}"
      log "[DEBUG] echo \"ls 20*\" | sftp ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME} 2>&1 ... "
      log "[DEBUG] $(echo "ls 20*" | sftp ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME} 2>&1)"
    fi
  fi
  grepstring="${JOB_NAME}|${site}|${ID}|ERROR|${versionWithRespin}|${SRC_DIR}|${DESTDIR}|${SRC_TYPE}|${DESTTYPE}|exclude"
  DEST_URLs=""

  if [[ "${site/discovery}" == "${site}" ]]; then # don't exclude the repo folder when publishing a discovery site build
    EXCLUDESTRING=""
  fi
  if [[ ${ID} ]]; then
    if [[ ${site} == "site" || ${site} == "product" ]]; then sitename="core"; else sitename=${site/-site/}; fi
    if [[ ${site} == "site" ]]; then buildname="core"; else buildname=${site/-site/}; fi
    log "[DEBUG] [$site] Latest build for ${sitename} (${site}): ${ID}" | egrep "${grepstring}"
    # use ${HOME}/temp-stage/ instead of /tmp because insufficient space
    tmpdir=`mkdir -p ${HOME}/temp-stage/ && mktemp -d -t -p ${HOME}/temp-stage/` && mkdir -p $tmpdir && pushd $tmpdir >/dev/null
      # echo "+ ${RSYNC} ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/* ${tmpdir}/" | egrep "${grepstring}"
      if [[ ! -d ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/ ]]; then
        echo "[WARN] Could not read ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID} - fall back to '${RSYNC}'"; SSHFS="";
      fi
      if [[ ! ${SSHFS} ]]; then
        ${RSYNC} ${DESTINATION}/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/* ${tmpdir}/
      fi
      # copy build folder
      if [[ ${DESTINATION/@/} == ${DESTINATION} ]]; then # local 
        log "[DEBUG] [$site] + mkdir -p ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}" | egrep "${grepstring}"
        mkdir -p ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname} &>${consoleDest}
      else # remote
        log "[DEBUG] [$site] + mkdir ${PRODUCT}-${versionWithRespin}-build-${buildname} | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/" | egrep "${grepstring}"
        echo "mkdir ${DESTDIR}" | sftp ${DESTINATION}/ &>${consoleDest}
        echo "mkdir ${DESTTYPE}" | sftp ${DESTINATION}/${DESTDIR}/ &>${consoleDest}
        echo "mkdir builds" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/ &>${consoleDest}
        echo "mkdir ${PRODUCT}-${versionWithRespin}-build-${buildname}" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/ &>${consoleDest}
      fi
      if [[ ${SSHFS} ]] && [[ -d ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/ ]]; then
        log "[DEBUG] [$site] + ${RSYNC} ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/* \\" | egrep "${grepstring}"
        log "                  ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/${ID}/ ${EXCLUDESTRING}" | egrep "${grepstring}"
        ${RSYNC} ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/* \
          ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/${ID}/ ${EXCLUDESTRING}
      else
        log "[DEBUG] [$site] + ${RSYNC} ${tmpdir}/* \\" | egrep "${grepstring}"
        log "                  ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/${ID}/ ${EXCLUDESTRING}" | egrep "${grepstring}"
        ${RSYNC} ${tmpdir}/* \
          ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/${ID}/ ${EXCLUDESTRING}
      fi
      DEST_URLs="${DEST_URLs} ${DEST_URL}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/"
      # symlink latest build
      ln -s ${ID} latest; ${RSYNC} ${tmpdir}/latest ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/ &>${consoleDest}
      DEST_URLs="${DEST_URLs} ${DEST_URL}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${buildname}/latest/"
      # copy update site zip
      suffix=-updatesite-${sitename}

      if [[ ${SSHFS} ]]; then
        y=${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/all/repository.zip
        if [[ ! -f $y ]]; then
          y=$(find ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/all/ -name "${ZIPPREFIX}*${suffix}.zip" -a -not -name "*latest*")
        fi
      else
        y=${tmpdir}/all/repository.zip
        if [[ ! -f $y ]]; then
          y=$(find ${tmpdir}/all/ -name "${ZIPPREFIX}*${suffix}.zip" -a -not -name "*latest*")
        fi
      fi
      if [[ -f $y ]]; then
        echo "mkdir ${DESTDIR}" | sftp ${DESTINATION}/ &>${consoleDest}
        echo "mkdir ${DESTTYPE}" | sftp ${DESTINATION}/${DESTDIR}/ &>${consoleDest}
        echo "mkdir updates" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/ &>${consoleDest}
        echo "mkdir ${sitename}" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/ &>${consoleDest}
        ${RSYNC} ${y} ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${ZIPPREFIX}${versionWithRespin}${suffix}.zip &>${consoleDest}
        ${RSYNC} ${y}.sha256 ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${ZIPPREFIX}${versionWithRespin}${suffix}.zip.sha256 &>${consoleDest}
      elif [[ "${site/discovery}" == "${site}" ]]; then
        # don't warn for discovery sites since they don't have update sites
        echo "[WARN] [$site] No update site zip (repository.zip or ${ZIPPREFIX}*${suffix}.zip) found to publish in ${tmpdir}/all/ to ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}" | egrep "${grepstring}"
      fi
      # if we have a zip but no repo folder, unpack the zip into update site folder
      if [[ -f $y ]] && [[ ! -d ${tmpdir}/all/repo/ ]]; then mkdir -p ${tmpdir}/all/repo; unzip -q $y -d ${tmpdir}/all/repo/; fi
      # copy update site
      if [[ -d ${tmpdir}/all/repo/ ]]; then
        if [[ ${DESTINATION/@/} == ${DESTINATION} ]]; then # local 
          log "[DEBUG] [$site] + mkdir -p ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}" | egrep "${grepstring}"
          mkdir -p ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename} &>${consoleDest}
        else # remote
          log "[DEBUG] [$site] + mkdir ${sitename} | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/" | egrep "${grepstring}"
          echo "mkdir ${DESTDIR}" | sftp ${DESTINATION}/ &>${consoleDest}
          echo "mkdir ${DESTTYPE}" | sftp ${DESTINATION}/${DESTDIR}/ &>${consoleDest}
          echo "mkdir updates" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/ &>${consoleDest}
          echo "mkdir ${sitename}" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/ &>${consoleDest}
        fi

        if [[ ${SSHFS} ]] && [[ -d ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/all/repo/ ]]; then
          log "[DEBUG] [$site] + ${RSYNC} ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/all/repo/* \\" | egrep "${grepstring}"
          log "                  ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/" | egrep "${grepstring}"
          ${RSYNC} ${HOME}/DEST-ssh/${SRC_DIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/all/repo/* \
            ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/ &>${consoleDest}
        else
          log "[DEBUG] [$site] + ${RSYNC} ${tmpdir}/all/repo/* \\" | egrep "${grepstring}"
          log "                  ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/" | egrep "${grepstring}"
          ${RSYNC} ${tmpdir}/all/repo/* \
            ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/ &>${consoleDest}
        fi
        DEST_URLs="${DEST_URLs} ${DEST_URL}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/"
      else
        # don't warn for discovery sites since they don't have update sites
        if [[ "${site/discovery}" == "${site}" ]]; then
          echo "[WARN] [$site] No update site found to publish in ${tmpdir}/all/repo/ to ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}" | egrep "${grepstring}"
        fi
      fi
    popd >/dev/null
    rm -fr $tmpdir
    for du in ${DEST_URLs}; do echo -e "[INFO] [$site] ${green}${du}${norm}" | egrep "${grepstring}"; done
    echo -e "[INFO] [$site] ${green}DONE${norm}: ${green}${JOB_NAME}${norm} :: ${green}${site}${norm} :: ${green}${ID}${norm}" | egrep "${grepstring}"
    echo ""
  else
    echo -e "[ERROR] [$site] No latest build found for ${red}${JOB_NAME}${norm} :: ${red}${site}${norm} :: ${red}${ID}${norm}" | egrep "${grepstring}"
  fi
done
