#!/bin/bash

# errata symlink parser 
# given  the URL of an errata report, parse the HTML for a list of problems and attempt to verify they can be waived
# eg., for https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505, install rh-eclipse47-eclipse-abrt then check the symlinks are resolved.

usage ()
{
    echo "Usage:     $0 -u [username:password] -e [errataURL] -p [problem]"
    echo ""
    echo "Example 1: $0 -u \"nboldt:password\" -e https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505 -p \"dangling symlink\""
    echo ""
    echo "Example 2: export userpass=username:password; $0 -e https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505 -p \"dangling symlink\" -q"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

# defaults
errataURL=""
data=""
quiet=""
waive=0

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-u') userpass="$2"; shift 1;;
    '-e') errataURL="$2"; shift 1;;
    '-p') problem="$2"; shift 1;;
    '-q') quiet="-q"; shift 0;;

    '-waive') waive=1; shift 0;;
  esac
  shift 1
done

log ()
{
  echo "$1"
}
logdebug ()
{
  if [[ ${quiet} == "" ]]; then echo "$1"; fi
}

# compute data as ?result_id=4852505 from the errataURL
data=${errataURL##*\?}; if [[ ${data} ]]; then data="--data ${data}"; fi
# logdebug "${data} ${errataURL} -> ${problem}"

hadError=0
tmpdir=`mktemp -d` && mkdir -p ${tmpdir} && pushd ${tmpdir} >/dev/null
  curl -s -S -k -X POST -u ${userpass} ${data} ${errataURL} > ${tmpdir}/page.html
  filesToCheck=$(cat page.html | egrep "${problem}|Results for" \
    | sed \
      -e "s#<h1> Results for \(.\+\) compared to .\+#\1#" \
      -e "s#.\+<pre>File ##" \
      -e "s# is.\+${problem}.\+to #:#" \
      -e "s#) on.\+</pre>##")
  if [[ ${filesToCheck} ]]; then
    rpm=""
    count=0
    for f in ${filesToCheck}; do # echo f = $f
      # first item is the rpm we're checking
      if [[ ! ${rpm} ]]; then 
        rpm=$f
        logdebug "[INFO] Install rpm: ${rpm}"
        if [[ -x /usr/bin/dnf ]]; then
          sudo dnf ${quiet} -y install $rpm
        else
          sudo yum ${quiet} -y install $rpm
        fi
      else # split the rest into pairs
        let count=count+1
        logdebug ""
        logdebug "[DEBUG] pair = $f"
        alink=/${f%:*}
        if [[ ${f#*:} = "/"* ]]; then
          afile=${f#*:}
        else
          afile=${alink%/*}/${f#*:}
        fi
        status=""
        logdebug "[DEBUG] alink = $alink"
        logdebug "[DEBUG] afile = $afile"
        if [[ ! -f "${afile}" ]]; then
          # echo "[WARNING] ${afile} not found - check symlink"
          error=""
          if [[ -L "${afile}" ]]; then
            error=$(file "${afile}" | grep "broken symbolic link")
            if [[ ${error} ]]; then
              status="[ERROR] Can't find '${afile}'"
              let hadError=hadError+1
            fi
          else
            status="[ERROR] Can't find '${alink}' -> '${afile}'"
            let hadError=hadError+1
          fi
        fi
        if [[ ${status} ]]; then
          log "${status}"
        else
          logdebug "[INFO] OK: ${alink} -> ${afile}"
        fi
      fi
    done
  fi
popd >/dev/null
rm -fr ${tmpdir}

log ""
if [[ ${hadError} -gt 0 ]]; then
  log "[ERROR] For ${rpm}, found ${hadError} of ${count} ${problem}s at ${errataURL}"
else
  log "[INFO] For ${rpm}, found ${hadError} of ${count} ${problem}s at ${errataURL}"

  # submit waive automatically
  if [[ ${waive} -gt 0 ]]; then
    data=""
    #data="${data}&utf8=&#x2713;authenticity_token=QeudVj96QLvlX5PPcs8HTUgzwtCFaueiggPn+S3VAwU="
    #data="${data}&errata_id="
    run_id=${errataURL%\?*}; run_id=${run_id##*/}
    data="${data}&run_id=${run_id}"
    #data="${data}&test_id="
    data="${data}&result_id="${errataURL#*result_id=}
    data="${data}&waive_text=This change is ok because I ran "
    data="${data}https://github.com/jbosstools/jbosstools-build-ci/blob/master/util/errataWaiveChecker.sh and "
    data="${data}after installing ${rpm}, all ${count} ${problem}s were resolved locally."
    errataWaiveURL=${errataURL%show/*}waive/${errataURL#*result_id=}
    logdebug "[DEBUG] Post waiver to ${errataWaiveURL}"
    logdebug "[DEBUG] ${data}"
    curl -s -S -k -X POST -u ${userpass} --data ${data// /%20} ${errataWaiveURL}
  else
    log "[INFO] to automatically waive this result, re-run this script with the -waive flag."
  fi
fi
logdebug ""