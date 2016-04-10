  #!/bin/bash
# Script to copy a CI build to staging for QE review
# From Jenkins, call this script 7 times in parallel (&) then call wait to block until they're all done

# TODO: should this script call rsync.sh (for build copy + symlink gen, and for update site copy w/ --del?) instead of using rsync?
# TODO: add support for JBDS staging steps
#  - see https://github.com/jbdevstudio/jbdevstudio-devdoc/blob/master/release_guide/9.x/JBDS_Staging_for_QE.adoc#push-installers-update-site-and-discovery-site
# TODO: create Jenkins job(s)
# TODO: test this !!
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

# can be used to publish a build (including installers, site zips, MD5s, build log) or just an update site folder
usage ()
{
  echo "Usage  : $0 [-DESTINATION destination] -s source_path -t target_path"
  echo ""

  echo "To stage JBT core, coretests, central & earlyaccess"
  echo "   $0 -sites \"site coretests-site central-site earlyaccess-site\" -dd mars -stream 4.3.mars -vr 4.3.1.CR1a -JOB_NAME jbosstools-build-sites.aggregate.\\\${site}_\\\${stream}"
  echo "To stage JBT discovery.* sites & browsersim-standalone"
  echo "   $0 -sites \"discovery.central discovery.earlyaccess browsersim-standalone\" -dd mars -stream 4.3.mars -vr 4.3.1.CR1a"
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-sites') sites="${sites} $2"; shift 1;; # site coretests-site central-site earlyaccess-site discovery.central discovery.earlyaccess
  
    '-eclipseReleaseName') DESTDIR="$2"; shift 1;; # mars or neon
    '-devstudioReleaseVersion') DESTDIR="$2"; shift 1;; # 9.0 or 10.0
    '-DESTDIR'|'-dd') DESTDIR="$2"; shift 1;; # mars or 9.0 or neon or 10.0

    '-SRC_TYPE') SRC_TYPE="$2"; shift 1;; # by default, snapshots but could be staging? (TODO: UNTESTED!)
    '-DESTTYPE') DESTTYPE="$2"; shift 1;; # by default, staging but could be development? (TODO: UNTESTED!)
    '-stream') stream="$2"; shift 1;; # 4.3.mars (TODO: could be 9.0.mars?)
    '-versionWithRespin'|'-vr') versionWithRespin="$2"; shift 1;; # 4.3.0.CR2b, 9.1.0.CR2b
    '-DJOB_NAME'|'-JOB_NAME') rawJOB_NAME="$2"; shift 1;;

    '-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., devstudio@filemgmt.jboss.org:/www_htdocs/devstudio or /qa/services/http/binaries/RHDS
    '-DEST_URL')    DEST_URL="$2"; shift 1;; # override for JBDS publishing, eg., https://devstudio.redhat.com or http://www.qa.jboss.com/binaries/RHDS

    '-DWORKSPACE'|'-WORKSPACE') WORKSPACE="$2"; shift 1;; # optional
    '-DID'|'-ID') whichID="$2"; shift 1;; # optionally, set a specific build ID such as 2015-10-02_18-28-18-B124; if not set, pull latest
    *) OTHERFLAGS="${OTHERFLAGS} $1"; shift 0;;
  esac
  shift 1
done

# set mars/staging, 9.0/staging, etc.
if [[ ! ${DESTDIR} ]]; then echo "ERROR: DESTDIR not set. Please define eclipseReleaseName or devstudioReleaseVersion"; echo ""; usage; fi

if [[ ${DESTINATION/devstudio/} != ${DESTINATION} ]] || [[ ${DESTINATION/RHDS/} != ${DESTINATION} ]]; then
  PRODUCT="devstudio"
  ZIPPREFIX="jboss-devstudio-"
fi

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=${tmpdir}; fi

for site in ${sites}; do
  # evaluate site or stream variables embedded in JOB_NAME
  if [[ ${rawJOB_NAME/\$\{site\}} != ${rawJOB_NAME} ]] || [[ ${rawJOB_NAME/\$\{stream\}} != ${rawJOB_NAME} ]]; then JOB_NAME=$(eval echo ${rawJOB_NAME}); fi

  if [[ ${whichID} == "latest" ]]; then
    ID=""
    echo "+ Check ${DEST_URL}/${DESTDIR}/${SRC_TYPE}/builds/${JOB_NAME}" | egrep "${grepstring}"
    if [[ ${DESTINATION/@/} == ${DESTINATION} ]]; then # local 
      ID=$(ls ${DESTINATION}/${DESTDIR}/${SRC_TYPE}/builds/${JOB_NAME} | grep "20.\+" | grep -v sftp | sort | tail -1)
    else # remote
      ID=$(echo "ls 20*" | sftp ${DESTINATION}/${DESTDIR}/${SRC_TYPE}/builds/${JOB_NAME} 2>&1 | grep "20.\+" | grep -v sftp | sort | tail -1)
    fi
    ID=${ID%%/*}
    echo "+ ${DESTINATION}/${DESTDIR}/${SRC_TYPE}/builds/${JOB_NAME} :: ID = $ID" | egrep "${JOB_NAME}|${site}|${ID}|ERROR"
  fi
  grepstring="${JOB_NAME}|${site}|${ID}|ERROR|${versionWithRespin}|${DESTDIR}|${DESTTYPE}"
  DEST_URLs=""

  RSYNC="rsync -arz --rsh=ssh --protocol=28"
  if [[ ${ID} ]]; then
    if [[ ${site} == "site" || ${site} == "product" ]]; then sitename="core"; else sitename=${site/-site/}; fi
    echo "Latest build for ${sitename} (${site}): ${ID}" | egrep "${grepstring}"
    tmpdir=`mktemp -d` && mkdir -p $tmpdir && pushd $tmpdir >/dev/null
      # echo "+ ${RSYNC} ${DESTINATION}/${DESTDIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/* ${tmpdir}/" | egrep "${grepstring}"
      ${RSYNC} ${DESTINATION}/${DESTDIR}/${SRC_TYPE}/builds/${JOB_NAME}/${ID}/* ${tmpdir}/
      # copy build folder
      echo "+ mkdir ${PRODUCT}-${versionWithRespin}-build-${sitename} | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/" | egrep "${grepstring}"
      echo "mkdir ${PRODUCT}-${versionWithRespin}-build-${sitename}" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/
      echo "+ ${RSYNC} ${tmpdir}/* ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${sitename}/${ID}/" | egrep "${grepstring}"
      ${RSYNC} ${tmpdir}/* ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${sitename}/${ID}/ --exclude="repo"
      DEST_URLs="${DEST_URLs} ${DEST_URL}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${sitename}/"
      # symlink latest build
      ln -s ${ID} latest; rsync -aPrz --rsh=ssh --protocol=28 ${tmpdir}/latest ${DESTINATION}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${sitename}/
      DEST_URLs="${DEST_URLs} ${DEST_URL}/${DESTDIR}/${DESTTYPE}/builds/${PRODUCT}-${versionWithRespin}-build-${sitename}/latest/"
      # copy update site
      if [[ -d ${tmpdir}/all/repo/ ]]; then
        echo "+ mkdir ${sitename} | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/" | egrep "${grepstring}"
        echo "mkdir ${sitename}" | sftp ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/
        echo "+ ${RSYNC} ${tmpdir}/all/repo/* ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/" | egrep "${grepstring}"
        ${RSYNC} ${tmpdir}/all/repo/* ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/
        DEST_URLs="${DEST_URLs} ${DEST_URL}/${DESTDIR}/${DESTTYPE}/updates/${sitename}/${versionWithRespin}/"
      else
        echo "[WARN] No update site found to publish in ${tmpdir}/all/repo/"
      fi
      # copy update site zip
      suffix=-updatesite-${sitename}
      y=${tmpdir}/all/repository.zip
      if [[ ! -f $y ]]; then
        y=$(find ${tmpdir}/all/ -name "${ZIPPREFIX}*${suffix}.zip" -a -not -name "*latest*")
      fi
      if [[ -f $y ]]; then
        ${RSYNC} ${y} ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/core/${ZIPPREFIX}${versionWithRespin}${suffix}.zip
        ${RSYNC} ${y}.sha256 ${DESTINATION}/${DESTDIR}/${DESTTYPE}/updates/core/${ZIPPREFIX}${versionWithRespin}${suffix}.zip.sha256
      else
        echo "[WARN] No update site zip (repository.zip or ${ZIPPREFIX}*${suffix}.zip) found to publish in ${tmpdir}/all/" 
      fi
    popd >/dev/null
    rm -fr $tmpdir
    echo "DONE: ${JOB_NAME} :: ${site} :: ${ID}" | egrep "${grepstring}"
    for du in ${DEST_URLs}; do echo "${du}" | egrep "${grepstring}"; done
    echo ""
  else
    echo "ERROR: no latest build found for ${JOB_NAME} :: ${site} :: ${ID}" | egrep "${grepstring}"
  fi
done
