#!/bin/bash
# Script to check last published build to see if the current SHA is the same as the published one
# NOTE: sources should be checked out into ${WORKSPACE}/sources 

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

# by default we only want the top-most SHA, but for aggregate builds we can compare ALL the SHAs for a more accurate picture
compareAllSHAs=0
debug=0

usage ()
{
  echo "Usage  : $0 -s source_path/to/buildinfo.json -t target_path/to/buildinfo.json"
  echo ""

  echo "To compare the generated json file to its published snapshot location:"
  echo "Usage 1: $0 -s \${WORKSPACE}/sources/site/target/repository -t https://download.jboss.org/jbosstools/neon/snapshots/builds/\${JOB_NAME}/latest/all/repo"

  echo "To compare the workspace's .git/HEAD against published snapshot location:"
  echo "Usage 2: $0 -s \${WORKSPACE}/sources -t https://download.jboss.org/jbosstools/neon/snapshots/builds/\${JOB_NAME}/latest/all/repo"

  echo ""
  echo "If SHAs match, return FALSE."
  echo "If SHAs do not match, return TRUE."
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-s') SOURCE_PATH="$2"; SOURCE_PATH=${SOURCE_PATH%/}; shift 1;; # ${WORKSPACE}/sources/site/target/repository [trim trailing slash]
    '-t') TARGET_PATH="$2"; TARGET_PATH=${TARGET_PATH%/}; shift 1;; # neon/snapshots/builds/<job-name>/<build-number> [trim trailing slash]
    '-all') compareAllSHAs="1"; shift 0;;
    '-debug') debug="$2"; shift 1;;
  esac
  shift 1
done

# SHA from local build; compare to SHA1 from remote
SHA2=""

# if paths don't already include /buildinfo.json, add it on at the end
if [[ -f ${SOURCE_PATH}/buildinfo.json ]]; then 
  if [[ ${SOURCE_PATH%/buildinfo.json} == ${SOURCE_PATH} ]]; then SOURCE_PATH=${SOURCE_PATH}/buildinfo.json; fi
else
  # or check for a check ${WORKSPACE}/sources/.git/HEAD to get latest SHA
  for d in ${SOURCE_PATH} ${WORKSPACE}/sources ${WORKSPACE}; do
    if [[ ! ${SHA2} ]] && [[ -f ${d}/.git/HEAD ]]; then
      SHA2=$(cat ${d}/.git/HEAD)
    fi
  done
fi

if [[ ${TARGET_PATH%/buildinfo.json} == ${TARGET_PATH} ]]; then TARGET_PATH=${TARGET_PATH}/buildinfo.json; fi

wgetParams="--timeout=900 --wait=10 --random-wait --tries=10 --retry-connrefused --no-check-certificate"
getRemoteFile ()
{
  # requires $wgetParams and $tmpdir to be defined (above)
  getRemoteFileReturn=""
  grfURL="$1"
  output=`mktemp -p ${tmpdir} getRemoteFile.XXXXXX`
  if [[ ! `wget ${wgetParams} ${grfURL} -O ${output} 2>&1 | egrep "ERROR 404"` ]]; then # file downloaded
    getRemoteFileReturn=${output}
    # cat ${getRemoteFileReturn}
  else
    getRemoteFileReturn=""
    rm -f ${output}
  fi
}

getSHA ()
{
  getSHAReturn=""
  if [[ "$1" ]] && [[ -f "$1" ]]; then
    if [[ ${compareAllSHAs} == 0 ]]; then # compare one SHA
      # {
      #  "timestamp" : 1425345819988,
      #  "revision" : {
      #      "HEAD" : "79b3dcd80d3c6f96b3671f5eae6f25d94d5c3801",
      #      "currentBranch" : "HEAD",
      getSHAReturn=$(head -5 "$1" | grep -A1 "revision" | grep -v "revision" | sed -e "s#.\+: \"\(.\+\)\".\+#\1#") # 79b3dcd80d3c6f96b3671f5eae6f25d94d5c3801
    else # compare ALL SHAs
      getSHAReturn="$(cat "$1" | grep -A1 "revision" | grep -v "revision" | sed -e "s#.\+: \"\(.\+\)\".\+#\1#" | grep -v -- "--" | sort)"
    fi
  fi
}

# get remote buildinfo.json
json=${tmpdir}/target.json
getRemoteFile "${TARGET_PATH}"
if [[ ${getRemoteFileReturn} ]]; then 
  mv ${getRemoteFileReturn} ${json}
else
  json=""
fi
# if ${TARGET_PATH} not found, no old version to compare so this is the first build; therefore return true below

# get SHAs from the buildinfo.json files
SHA1=""; getSHA "${json}";        if [[ ${getSHAReturn} ]]; then SHA1="${getSHAReturn}"; fi
if [[ ! ${SHA2} ]]; then 
  getSHA "${SOURCE_PATH}"; if [[ ${getSHAReturn} ]]; then SHA2="${getSHAReturn}"; fi
fi

if [[ ${compareAllSHAs} == 1 ]]; then # compare multiple SHAs, but filter out the lines that are the same so we're only comparing the differences
  for SH in $SHA1; do echo $SH >> $tmpdir/SHA1; done
  for SH in $SHA2; do echo $SH >> $tmpdir/SHA2; done
  SHA1uniq=$(grep -v -x -f $tmpdir/SHA2 $tmpdir/SHA1)
  SHA2uniq=$(grep -v -x -f $tmpdir/SHA1 $tmpdir/SHA2)
fi

# purge temp folder
rm -fr ${tmpdir} 

if [[ "${SHA1}" ]] && [[ "${SHA2}" ]] &&  [[ "${SHA1}" == "${SHA2}" ]]; then # SHAs match - return false
  if [[ $debug != 0 ]]; then 
    echo "[INFO] SHAs match: 
${SHA1} (target = ${TARGET_PATH}) 
  == 
${SHA2} (source = ${SOURCE_PATH})"
  fi
  echo "false"
else # SHAs are different (or one is null because no previous SHA) - return true
  if [[ $debug != 0 ]]; then 
    if [[ ${compareAllSHAs} == 1 ]]; then 
      echo "[INFO] SHAs differ:"
      echo "${SHA1}" | egrep "${SHA1uniq}"
      echo "  (target = ${TARGET_PATH})"
      echo "  !="
      echo "${SHA2}" | egrep "${SHA2uniq}"
      echo "  (source = ${SOURCE_PATH})"
    else
      echo "[INFO] SHAs differ:
${SHA1} (target = ${TARGET_PATH})
  != 
${SHA2} (source = ${SOURCE_PATH})"
    fi
  fi
  echo "true"
fi
