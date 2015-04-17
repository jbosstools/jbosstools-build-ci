#!/bin/bash
# Script to check last published build to see if the current SHA is the same as the published one
# NOTE: sources should be checked out into ${WORKSPACE}/sources 

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

usage ()
{
  echo "Usage  : $0 -s source_path/to/buildinfo.json -t target_path/to/buildinfo.json"
  echo ""

  echo "To compare the generated json file to its published snapshot location:"
  echo "Usage  : $0 -s \${WORKSPACE}/sources/site/target/repository -t http://download.jboss.org/jbosstools/mars/snapshots/builds/\${JOB_NAME}/latest/all/repo"

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
    '-t') TARGET_PATH="$2"; TARGET_PATH=${TARGET_PATH%/}; shift 1;; # mars/snapshots/builds/<job-name>/<build-number> [trim trailing slash]
  esac
  shift 1
done

# if paths don't already include /buildinfo.json, add it on at the end
if [[ ${SOURCE_PATH%/buildinfo.json} == ${SOURCE_PATH} ]]; then SOURCE_PATH=${SOURCE_PATH}/buildinfo.json; fi
if [[ ${TARGET_PATH%/buildinfo.json} == ${TARGET_PATH} ]]; then TARGET_PATH=${TARGET_PATH}/buildinfo.json; fi

wgetParams="--timeout=900 --wait=10 --random-wait --tries=10 --retry-connrefused --no-check-certificate"
getRemoteFile ()
{
  # requires $wgetParams and $tmpdir to be defined (above)
  getRemoteFileReturn=""
  grfURL="$1"
  output=`mktemp --tmpdir=${tmpdir} getRemoteFile.XXXXXX`
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
		# {
		#  "timestamp" : 1425345819988,
		#  "revision" : {
		#      "HEAD" : "79b3dcd80d3c6f96b3671f5eae6f25d94d5c3801",
		#      "currentBranch" : "HEAD",
		getSHAReturn=$(head -5 "$1" | grep -A1 "revision" | grep -v "revision" | sed -e "s#.\+: \"\(.\+\)\".\+#\1#") # 79b3dcd80d3c6f96b3671f5eae6f25d94d5c3801
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
SHA2=""; getSHA "${SOURCE_PATH}"; if [[ ${getSHAReturn} ]]; then SHA2="${getSHAReturn}"; fi

# purge temp folder
rm -fr ${tmpdir} 

if [[ "${SHA1}" ]] && [[ "${SHA2}" ]] &&  [[ "${SHA1}" == "${SHA2}" ]]; then # SHAs match - return false
	# echo "[INFO] SHAs match: ${SHA1} == ${SHA2}"
	echo "false"
else # SHAs are different (or one is null because no previous SHA) - return true
	# echo "[INFO] SHAs differ: ${SHA1} != ${SHA2}"
	echo "true"
fi
