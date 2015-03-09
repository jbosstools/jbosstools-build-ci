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
  echo "Usage  : $0 -s \${WORKSPACE}/sources/site/target/repository/ -t http://download.jboss.org/jbosstools/mars/snapshots/builds/\${JOB_NAME}/latest/all/repo/"

  echo ""
  echo "If SHAs match, return FALSE."
	echo "If SHAs do not match, return TRUE."
	exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-s') SOURCE_PATH="$2"; shift 1;; # ${WORKSPACE}/sources/site/target/repository/
    '-t') TARGET_PATH="$2"; shift 1;; # mars/snapshots/builds/<job-name>/<build-number>/, mars/snapshots/updates/core/{4.3.0.Alpha1, master}/
  esac
  shift 1
done

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
	if [[ -f "$1" ]]; then
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
getRemoteFile "${TARGET_PATH}/buildinfo.json"
if [[ ${getRemoteFileReturn} ]]; then 
	mv ${getRemoteFileReturn} ${json}
else 
	echo "[WARNING] Could not fetch ${TARGET_PATH}/buildinfo.json!"; echo 
fi

# get SHAs from the buildinfo.json files
getSHA ${json}; if [[ ${getSHAReturn} ]]; then SHA1="${getSHAReturn}"; fi
getSHA "${SOURCE_PATH}/buildinfo.json"; if [[ ${getSHAReturn} ]]; then SHA2="${getSHAReturn}"; fi

# purge temp folder
rm -fr ${tmpdir} 

if [[ ${SHA1} ]] && [[ ${SHA2} ]] &&  [[ "${SHA1}" == "${SHA2}" ]]; then # SHAs match - return false
	# echo "[INFO] SHAs match: ${SHA1} == ${SHA2}"
	echo "FALSE"
else # SHAs are different - return true
	# echo "[INFO] SHAs differ: ${SHA1} != ${SHA2}"
	echo "TRUE"
fi
