#!/bin/bash

# util script for gercan@ to use to publish something like yaml-language-server-*.tar.gz bits from staging -> stable and generate a latest symlink
# must define DESTINATION="user@SERVER_IP:/sftp/path" to define destination (on download.jboss.org server or elsewhere)
# 
# assumes you have content in http://download.jboss.org/jbosstools/oxygen/staging/builds/${filePrefix}/
# and want to copy it over to http://download.jboss.org/jbosstools/static/oxygen/stable/builds/${filePrefix}/
# then create a symlink from  http://download.jboss.org/jbosstools/oxygen/stable/builds/${filePrefix}/ to the /static/ path

eclipseReleaseName=oxygen
filePrefix=yaml-language-server
fileSuffix=tar.gz
DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools

usage ()
{
  log "Usage  : $0 -ern [eclipseReleaseName] -prefix [filePrefix] -suffix [fileSuffix] [-q (quiet)] [-DESTINATION [user@SERVER_IP:/sftp/path]]"
  log "Example: $0 -ern oxygen -prefix yaml-language-server -suffix tar.gz -q"
  log ""
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

quiet=""
# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
	'-DESTINATION') DESTINATION="$2"; shift 1;;
    '-ern') eclipseReleaseName="$2"; shift 1;;
    '-prefix') filePrefix="$2"; shift 1;;
    '-suffix') fileSuffix="$2"; shift 1;;
    '-q') quiet="-q"; shift 0;;
  esac
  shift 1
done

tmpdir=`mktemp -d`
mkdir -p ${tmpdir}
pushd ${tmpdir} >/dev/null

RSYNC="rsync -zrlt --rsh=ssh --protocol=28 ${quiet}"

STATIC=static/${eclipseReleaseName}/stable/builds/${filePrefix}
STABLE=${eclipseReleaseName}/stable/builds/${filePrefix}
STAGING=${eclipseReleaseName}/staging/builds/${filePrefix}

# create temporary dir trees
mkdir -p ${tmpdir}/${STATIC}/ ${tmpdir}/${STABLE}/ 

# fetch file from staging -> static
${RSYNC} ${TOOLS}/${STAGING}/${filePrefix}-*.${fileSuffix} ${tmpdir}/${STATIC}/

# find latest file, then extract just the filename (no path)
latestBuild=$(find ${tmpdir}/${STATIC}/ -name "${filePrefix}-*.${fileSuffix}" | sort | tail -1); latestBuild=${latestBuild##*/}
# delete any other old builds
for d in $(find ${tmpdir}/${STATIC}/ -name "${filePrefix}-*.${fileSuffix}"); do if [[ ${d##*/} != ${latestBuild} ]]; then rm -f ${d}; fi; done

# push file to akamai static, and purge any old files from previous builds
${RSYNC} --delete ${tmpdir}/${STATIC}/ ${TOOLS}/${STATIC}/

pushd ${tmpdir}/${STABLE}/ >/dev/null

# remove old symlink if exist
if [[ -L ${filePrefix}-latest.${fileSuffix} ]]; then rm -f ${filePrefix}-latest.${fileSuffix}; fi
# create new symlink from stable to static latest build
ln -s ../../../../${STATIC}/${latestBuild} ${filePrefix}-latest.${fileSuffix}
${RSYNC} ${filePrefix}-latest.${fileSuffix} ${TOOLS}/${STABLE}/

popd >/dev/null

# cleanup tmp dirs
rm -fr ${tmpdir}

popd >/dev/null