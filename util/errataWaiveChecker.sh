#!/bin/bash

# errata symlink parser 
# given  the URL of an errata report, parse the HTML for a list of problems and attempt to verify they can be waived
# eg., for https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505, install rh-eclipse47-eclipse-abrt then check the symlinks are resolved.

usage ()
{
    echo "Usage:     $0 -u [username:password] -p [problem] [errataURL1] [errataURL2] [...]"
    echo ""
    echo "Example 1: $0 -u \"nboldt:password\" -p \"dangling symlink\"https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505"
    echo ""
    echo "Example 2: export userpass=username:password; $0 -p \"dangling symlink\" https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

# defaults
errataURLs=""
data=""
quiet=""
waive=0 # if =1, automatically submit a waiver if 0 unresolved problems found
uninstallRPMsBefore=0 # if =1, uninstall installed RPMs before any other installs (to remove extra deps)
uninstallRPMsAfter=0 # if =1, uninstall installed RPMs when done
installAnyVersion=0 # if =1, let yum install ANY version of required RPMs, rather than the specific version of RPMs

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"
blue="\033[1;34m"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-u') userpass="$2"; shift 1;;
    '-p') problem="$2"; shift 1;;
    '-q') quiet="-q"; shift 0;;
    '-waive') waive=1; shift 0;;
    '-UB') uninstallRPMsBefore=1; shift 0;;
    '-UA') uninstallRPMsAfter=1; shift 0;;
    '-I') installAnyVersion=1; shift 0;;
    *) errataURLs="${errataURLs} $1"; shift 0;;
  esac
  shift 1
done

log ()
{
  echo -e "$1"
}
logdebug ()
{
  if [[ ${quiet} == "" ]]; then echo -e "$1"; fi
}

doInstall ()
{
  op=$1
  rpmInstallList=$2
  log "[INFO] RPM(s) to ${op}:${rpmInstallList}"
  if [[ -x /usr/bin/dnf ]]; then
    time sudo dnf ${quiet} -y ${op} ${rpmInstallList}
  else
    time sudo yum ${quiet} -y ${op} ${rpmInstallList}
  fi
}

totErrata=0
for errataURL in ${errataURLs}; do
  let totErrata=totErrata+1
done
numErrata=0
for errataURL in ${errataURLs}; do
  log ""
  # compute data as ?result_id=4852505 from the errataURL
  data=${errataURL##*\?}; if [[ ${data} ]]; then data="--data ${data}"; fi
  # logdebug "${data} ${errataURL} -> ${problem}"

  hadError=0
  tmpdir=`mktemp -d` && mkdir -p ${tmpdir} && pushd ${tmpdir} >/dev/null
    curl -s -S -k -X POST -u ${userpass} ${data} ${errataURL} > ${tmpdir}/page.html
    filesToCheck=$(cat page.html | egrep "${problem}" \
      | sed \
        -e "s#.\+This change is ok because.\+##" \
        -e "s#.\+<pre>File ##" \
        -e "s# is.\+${problem}.\+to #:#" \
        -e "s#) on.\+</pre>##")
    rpmsToInstall=$(cat page.html | egrep "NEEDS INSPECTION" -A4 \
      | sed -e "s#--\|.\+<td>.*\|.\+</td>.*\|.\+NEEDS INSPECTION.*##" | sort | uniq)

    rpm=$(cat page.html | egrep "Results for" | sed -e "s#<h1> Results for \(.\+\) compared to .\+#\1#")
    rpmInstallList=""
    rpmversion2=${rpm##*-}; # echo $rpmversion2; 
    rpmversion1=${rpm%-${rpmversion2}}; rpmversion1=${rpmversion1##*-}; # echo $rpmversion1
    for anrpm in ${rpmsToInstall}; do
      if [[ ${installAnyVersion} -eq 1 ]]; then
        rpmInstallList="${rpmInstallList} ${anrpm}"
      else
        rpmInstallList="${rpmInstallList} ${anrpm}-${rpmversion1}-${rpmversion2}"
      fi
    done

    if [[ $uninstallRPMsBefore -eq 1 ]]; then
      doInstall remove "${rpmInstallList}"
    fi
    doInstall install "${rpmInstallList}"

    if [[ ${filesToCheck} ]]; then
      count=0
      for f in ${filesToCheck}; do # echo f = $f
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
        if [[ ! -f "${afile}" ]] && [[ ! -d "${afile}" ]]; then
          # echo "[WARNING] ${afile} not found - check symlink"
          error=""
          if [[ -L "${afile}" ]]; then
            error=$(file "${afile}" | grep "broken symbolic link")
            if [[ ${error} ]]; then
              status="${red}[ERROR] Can't find ${norm}'${red}${afile}${norm}'"
              let hadError=hadError+1
            fi
          else
            status="${red}[ERROR] Can't find ${norm}'${red}${alink}${norm}' -> '${red}${afile}${norm}'"
            let hadError=hadError+1
          fi
        fi
        if [[ ${status} ]]; then
          log "${status}"
        else
          logdebug "[INFO] ${green}OK${norm}: ${alink} -> ${afile}"
        fi
      done
    fi

  if [[ $uninstallRPMsAfter -eq 1 ]]; then
    doInstall remove "${rpmInstallList}"
  fi

  log ""
  let numErrata=numErrata+1
  if [[ ${hadError} -gt 0 ]]; then
    log "${red}[ERROR]${norm} [${numErrata}/${totErrata}] For ${rpmInstallList}, found ${red}${hadError}${norm} of ${red}${count}${norm} ${problem}s at ${errataURL}"
  else
    log "[INFO] [${numErrata}/${totErrata}] For ${rpmInstallList}, found ${green}${hadError}${norm} of ${green}${count}${norm} ${problem}s at ${errataURL}"

    # submit waive automatically
    if [[ ${waive} -eq 1 ]]; then
      data=""
      #data="${data}&utf8=&#x2713;authenticity_token=QeudVj96QLvlX5PPcs8HTUgzwtCFaueiggPn+S3VAwU="
      #data="${data}&errata_id="
      run_id=${errataURL%\?*}; run_id=${run_id##*/}
      data="${data}&run_id=${run_id}"
      #data="${data}&test_id="
      data="${data}&result_id="${errataURL#*result_id=}
      data="${data}&waive_text=This change is ok because I ran "
      data="${data}https://github.com/jbosstools/jbosstools-build-ci/blob/master/util/errataWaiveChecker.sh and "
      data="${data}after installing ${rpmInstallList}, all ${count} ${problem}s were resolved locally."
      errataWaiveURL=${errataURL%show/*}waive/${errataURL#*result_id=}
      logdebug "[DEBUG] Post waiver to ${errataWaiveURL}"
      logdebug "[DEBUG] ${data}"
      curl -s -S -k -X POST -u ${userpass} --data ${data// /%20} ${errataWaiveURL} > ${tmpdir}/page2.html
      log "[INFO] [${numErrata}/${totErrata}] Waived ${errataURL}"
    else
      log "[INFO] [${numErrata}/${totErrata}] To automatically waive this result, re-run this script with the ${blue}-waive${norm} flag."
    fi
  fi
  logdebug ""

  popd >/dev/null
  rm -fr ${tmpdir}

done