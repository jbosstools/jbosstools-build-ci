#!/bin/bash

# errata symlink parser 
# given  the URL of an errata report, parse the HTML for a list of problems and attempt to verify they can be waived
# eg., for https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505, install rh-eclipse47-eclipse-abrt then check the symlinks are resolved.

usage ()
{
    echo "Usage:     $0 -u [username:password] -p [problem] [errataURL1] [errataURL2] [...]"
    echo ""
    echo "Example 1: $0 -u \"nboldt:password\" -p \"dangling symlink\" https://errata.devel.redhat.com/advisory/30618/rpmdiff_runs"
    echo ""
    echo "Example 1: export userpass=username:password; $0 -p \"dangling_symlink malformed_XML\" https://errata.devel.redhat.com/advisory/30618/rpmdiff_runs"
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
problems=""

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"
blue="\033[1;34m"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-u') userpass="$2"; shift 1;;
    '-p') problems="${problems}"; shift 1;;
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

tmpdir=`mktemp -d` && mkdir -p ${tmpdir}

declare -A problemMap
# map problem name (substring in the Content field to Results Summary label (and link labels) 
problemMap["dangling symlink"]="Symlinks" # eg., https://errata.devel.redhat.com/rpmdiff/show/182132?result_id=5028531
problemMap["malformed XML"]="XML validity" # eg., https://errata.devel.redhat.com/rpmdiff/show/182113?result_id=5027897
# process errataURLs to pull up child pages to process 
# 0. https://errata.devel.redhat.com/advisory/30618/rpmdiff_runs -> search for <a href="/rpmdiff/show/182115">Needs inspection</a>
# 1. load that page and look for matching result_id= URLs -> 
#   <a href="/rpmdiff/show/182115?result_id=5027953">Symlinks</a>
#   <a href="/rpmdiff/show/182113?result_id=5027897">XML validity</a>
#   ...
# 2. replace discovered ?result_id= URLs in the list of errataURLs to process if the label is what we're looking for
maxNumErrataURLs=0 # use -1 to collect all

declare -A errataURLsMap
for errataURL in ${errataURLs}; do
  protocol=${errataURL%%//*}//
  domain=${errataURL##${protocol}}; domain=${domain%%/*}
  curl -s -S -k -X POST -u ${userpass} ${errataURL} | egrep "rpmdiff/show" > ${tmpdir}/page1.html
  childURLs=$(cat ${tmpdir}/page1.html | egrep "Needs inspection" | sed -e "s#.\+href=\"\(.\+\)\">Needs inspection</a>.\+#\1#")
  for childURL in ${childURLs}; do
    # logdebug "[DEBUG] Parse ${protocol}${domain}${childURL}"
    curl -s -S -k -X POST -u ${userpass} ${protocol}${domain}${childURL} | egrep -B1 "rpmdiff/show" > ${tmpdir}/page2.html
    # check for valid URLs to process from the problemMap
    # assumes only ONE hit per matching problem - if more than one found may end up with missing ${protocol}${domain} prefix on a URL
    for problem in "${!problemMap[@]}"; do
      # logdebug "[DEBUG] $problem -> ${problemMap[$problem]}"
      childURLGood=$(cat ${tmpdir}/page2.html | egrep "${problemMap[$problem]}" | sed -e "s#.\+href=\"\(.\+\)\">${problemMap[$problem]}</a>.*#\1#")
      if [[ ${childURLGood} ]]; then 
        logdebug "[DEBUG] Found ${protocol}${domain}${childURLGood} - ${problemMap[$problem]}"
        errataURLsMap["${protocol}${domain}${childURLGood}"]="${problemMap[$problem]}"
        # remove the lines we've processed
        sed -i -e "s/.\+href=\"\(.\+\)\">${problemMap[$problem]}<\/a>//" ${tmpdir}/page2.html
      fi
      # to only process a few items, use this breakpoint with maxNumErrataURLs >= 1
      if [[ ${#errataURLsMap[@]} -ge ${maxNumErrataURLs} ]] && [[ ${maxNumErrataURLs} -gt 0 ]]; then
        break 2
      fi
    done
    if [[ $(cat ${tmpdir}/page2.html) ]]; then
      # strip out waived items and info items by colour
      sed -i "/<td bgcolor=\"#00a37f\">/,/.\+href=\"\(.\+\)\">File list<\/a>/d" ${tmpdir}/page2.html #info
      #sed -i "/<td bgcolor=\"#00DD00\">/,/.\+href=\"\(.\+\)\">.\+<\/a>/d" ${tmpdir}/page2.html #waived
      sed -i -e "s/--\|<td bgcolor=\"#00a37f\">\|<td bgcolor=\"#FFFF00\">\|<td bgcolor=\"#00DD00\">//" ${tmpdir}/page2.html #other lines
      sed -i '/^$/d' ${tmpdir}/page2.html #empty lines
    fi      
    if [[ $(cat ${tmpdir}/page2.html | tr -d '[:space:]') ]]; then
      # echo -n "["; cat ${tmpdir}/page2.html; echo "]"
      logdebug "[WARNING] Unwaived problem(s):"
      logdebug "$(cat ${tmpdir}/page2.html | sed -e "s#.\+href=\"\(.\+\)\">\(.\+\)</a>.*#  ! \2: ${protocol}${domain}\1#")"
    fi
  done
  rm -f ${tmpdir}/page*.html
done

totErrata=0
for errataURL in "${!errataURLsMap[@]}"; do
  let totErrata=totErrata+1
  # logdebug "[DEBUG] [${totErrata}] ${errataURL}"
done

#######

numErrata=0
for errataURL in "${!errataURLsMap[@]}"; do
  problemValue=${errataURLsMap[$errataURL]}
  for p in "${!problemMap[@]}"; do # foreach key
    if [[ "${problemValue}" == "${problemMap[$p]}" ]]; then
      problem=${p}
      break;
    fi 
  done
  # logdebug "[DEBUG] For ${errataURL}, problemValue = ${problemValue}, problem = ${problem}" # got: "XML validity" (value), want: "malformed XML" (key)

  # compute data as ?result_id=4852505 from the errataURL
  data=${errataURL##*\?}; if [[ ${data} ]]; then data="--data ${data}"; fi
  # logdebug "${data} ${errataURL} -> ${problem}"

  hadError=0
  mkdir -p ${tmpdir} && pushd ${tmpdir} >/dev/null
  curl -s -S -k -X POST -u ${userpass} ${data} ${errataURL} > ${tmpdir}/page.html

  # determine the type of problem to check - look for <b>*Symlinks*</b> - page must include the correct string, 
  # and that must map to one of the problems we're processing
  if [[ $(cat ${tmpdir}/page.html | egrep "<b>\*${problemMap[$problem]}\*<\/b>") ]]; then # ok to proceed
    count=0
    if [[ ${problem} == "malformed XML" ]]; then
      rpmsToInstall=$(cat page.html | egrep "NEEDS INSPECTION" -A4 \
        | sed -e "s#--\|.\+<td>.*\|.\+</td>.*\|.\+NEEDS INSPECTION.*##" | sort | uniq)

      if [[ ${rpmsToInstall} ]]; then
        for f in ${rpmsToInstall}; do let count=count+1; done
      fi
    elif [[ ${problem} == "dangling symlink" ]]; then 
      filesToCheck=$(cat page.html | egrep "is a ${problem} \(to " | sed \
          -e "s#.\+This change is ok because.\+##" \
          -e "s#.\+<pre>File ##" \
          -e "s# is.\+${problem}.\+to #:#" \
          -e "s#) on.\+</pre>##")
      rpmsToInstall=$(cat page.html | egrep "NEEDS INSPECTION" -A4 \
        | sed -e "s#--\|.\+<td>.*\|.\+</td>.*\|.\+NEEDS INSPECTION.*##" | sort | uniq)

      rpm=$(cat page.html | egrep "Results for" | sed -e "s#<h1>.\+Results for \(.\+\) compared to .\+#\1#")
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
    fi
  else
    logdebug "Skip processing ${problem} - ${tmpdir}/page.html" # should never get here
  fi

  if [[ $uninstallRPMsAfter -eq 1 ]]; then
    doInstall remove "${rpmInstallList}"
  fi

  log ""
  let numErrata=numErrata+1
    if [[ ${problem} == "malformed XML" ]]; then
      log "[INFO] [${numErrata}/${totErrata}] Found ${green}${hadError}${norm} of ${green}${count}${norm} ${problem}s at ${errataURL}"
    elif [[ ${problem} == "dangling symlink" ]]; then 
      if [[ ${hadError} -gt 0 ]]; then
        log "${red}[ERROR]${norm} [${numErrata}/${totErrata}] For ${rpm}, found ${red}${hadError}${norm} of ${red}${count}${norm} ${problem}s at ${errataURL}"
      else
        log "[INFO] [${numErrata}/${totErrata}] For ${rpm}, found ${green}${hadError}${norm} of ${green}${count}${norm} ${problem}s at ${errataURL}"
      fi
    fi

    # submit waive automatically
    if [[ ${waive} -eq 1 ]] && [[ ${hadError} -eq 0 ]]; then
      data=""
      #data="${data}&utf8=&#x2713;authenticity_token=QeudVj96QLvlX5PPcs8HTUgzwtCFaueiggPn+S3VAwU="
      #data="${data}&errata_id="
      run_id=${errataURL%\?*}; run_id=${run_id##*/}
      data="${data}&run_id=${run_id}"
      #data="${data}&test_id="
      data="${data}&result_id="${errataURL#*result_id=}
      data="${data}&waive_text=This change is ok because I ran "
      data="${data}https://github.com/jbosstools/jbosstools-build-ci/blob/master/util/errataWaiveChecker.sh and "
      if [[ ${problem} == "malformed XML" ]]; then
        # nothing to check, these are always autowaived
        data="${data}malformed XML errors are traditionally false positives which can be autowaived."
      elif [[ ${problem} == "dangling symlink" ]]; then 
        data="${data}after installing ${rpmInstallList}, all ${count} ${problem}s were resolved locally."
      fi
      errataWaiveURL=${errataURL%show/*}waive/${errataURL#*result_id=}
      logdebug "[DEBUG] Post waiver to ${errataWaiveURL}"
      logdebug "[DEBUG] ${data}"
      curl -s -S -k -X POST -u ${userpass} --data ${data// /%20} ${errataWaiveURL} > ${tmpdir}/page2.html
      log "[INFO] [${numErrata}/${totErrata}] Waived ${errataURL}"
    elif [[ ${hadError} -gt 0 ]]; then
      log "${red}[ERROR]${norm} [${numErrata}/${totErrata}] Cannot auto-waive this result: found ${red}${hadError}${norm} of ${red}${count}${norm} ${problem}s at ${errataURL}"
    elif [[ ${waive} -eq 0 ]]; then
      log "[INFO] [${numErrata}/${totErrata}] To automatically waive this result, re-run this script with the ${blue}-waive${norm} flag."
    fi
  
  logdebug ""

  popd >/dev/null
  rm -fr ${tmpdir}

done