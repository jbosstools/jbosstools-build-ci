#!/bin/bash

# errata symlink parser 
# given  the URL of an errata report, parse the HTML for a list of problems and attempt to verify they can be waived
# eg., for https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505, install rh-eclipse47-eclipse-abrt then check the symlinks are resolved.

usage ()
{
    echo "Usage:     $0 -u [username:password] -p [\"problem_type1 problem_type2\"] [errataURL]"
    echo ""
    echo "Example 1: $0 -u \"nboldt:password\" -p \"java_byte_code dangling_symlink malformed_XML\" https://errata.devel.redhat.com/advisory/30618/rpmdiff_runs"
    echo ""
    echo "Example 1: export userpass=username:password; $0 https://errata.devel.redhat.com/advisory/30618/rpmdiff_runs -fn"
    echo ""
    echo "Example 2a: $0 -p \"java_byte_code\"   https://errata.devel.redhat.com/rpmdiff/show/182406?result_id=5037997 -waive"
    echo "Example 2b: $0 -p \"dangling_symlink\" https://errata.devel.redhat.com/rpmdiff/show/182406?result_id=5037979 -waive"
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
failNever=0 # if =1, continue processing all waivers even if something goes wrong (but don't autowaive them!)

# declare problem maps
# 
declare -A rpmInstallProblemMap
declare -A falsePositiveProblemMap
declare -A allProblemsMap
# map [substring in the Content field] = Results Summary label (and link labels) 
rpmInstallProblemMap["dangling symlink"]="Symlinks" # eg., https://errata.devel.redhat.com/rpmdiff/show/182132?result_id=5028531
falsePositiveProblemMap["malformed XML"]="XML validity" # eg., https://errata.devel.redhat.com/rpmdiff/show/182113?result_id=5027897
# java byte code version 52(JDK-8), greater than expected 51(JDK-7)
falsePositiveProblemMap["java byte code"]="Java byte code" # eg., https://errata.devel.redhat.com/rpmdiff/show/182406?result_id=5037979
falsePositiveProblemMap["Desktop file"]="Desktop file sanity" # eg., https://errata.devel.redhat.com/rpmdiff/show/182459?result_id=5040039
falsePositiveProblemMap["sh script"]="Shell syntax" # eg., https://errata.devel.redhat.com/rpmdiff/show/182112?result_id=5027919
falsePositiveProblemMap["changelog"]="RPM changelog" # eg., https://errata.devel.redhat.com/rpmdiff/show/182461?result_id=5039897

# these should never be autowaived as they require human intervention
declare -A neverWaiveMap
neverWaiveMap["ELF file"]="Elflint" # eg., https://errata.devel.redhat.com/rpmdiff/show/182459?result_id=5040040
neverWaiveMap["stripped"]="Binary stripping" # eg., https://errata.devel.redhat.com/rpmdiff/show/182459?result_id=5040060
neverWaiveMap["Requires"]="RPM requires/provides" # eg., https://errata.devel.redhat.com/rpmdiff/show/182407?result_id=5038024
neverWaiveMap["Provides"]="RPM requires/provides" # eg., https://errata.devel.redhat.com/rpmdiff/show/182407?result_id=5038024
neverWaiveMap["GNU_STACK"]="Execshield" # eg., https://errata.devel.redhat.com/rpmdiff/show/182196?result_id=5030668
neverWaiveMap["patch"]="Patches" # eg., https://errata.devel.redhat.com/rpmdiff/show/182120?result_id=5028122

# load both types of problems into the allProblemsMap
for p in "${!rpmInstallProblemMap[@]}"; do # foreach key
  allProblemsMap[${p}]=${rpmInstallProblemMap[$p]}
  problems="${problems} ${p// /_}"
done
for p in "${!falsePositiveProblemMap[@]}"; do # foreach key
  allProblemsMap[${p}]=${falsePositiveProblemMap[$p]}
  problems="${problems} ${p// /_}"
done
# by default check for all supported problem types

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"
blue="\033[1;34m"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-u') userpass="$2"; shift 1;;
    '-p') problems="${problems}"; shift 1;; # by default check for all supported problem types
    '-q') quiet="-q"; shift 0;;
    '-waive') waive=1; shift 0;;
    '-UB') uninstallRPMsBefore=1; shift 0;;
    '-UA') uninstallRPMsAfter=1; shift 0;;
    '-I') installAnyVersion=1; shift 0;;
    '-fn') failNever=1; shift 0;;
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
  if [[ ${errataURL} == *"/rpmdiff_runs" ]]; then 
    curl -s -S -k -X POST -u ${userpass} ${errataURL} | egrep "rpmdiff/show" > ${tmpdir}/page1.html
    childURLs=$(cat ${tmpdir}/page1.html | egrep "Needs inspection|Failed" | sed -e "s#.\+href=\"\(.\+\)\">\(Needs inspection\|Failed\)</a>.\+#\1#")
  else
    childURLs=${errataURL##*${domain}}
  fi
  for childURL in ${childURLs}; do
    # logdebug "[DEBUG] Parse ${protocol}${domain}${childURL}"
    curl -s -S -k -X POST -u ${userpass} ${protocol}${domain}${childURL} | egrep -B1 "rpmdiff/show" > ${tmpdir}/page2.html
    # check for valid URLs to process from the allProblemsMap
    # assumes only ONE hit per matching problem - if more than one found may end up with missing ${protocol}${domain} prefix on a URL
    for problem in "${!allProblemsMap[@]}"; do
      # logdebug "[DEBUG] $problem -> ${allProblemsMap[$problem]}"
      childURLGood=$(cat ${tmpdir}/page2.html | egrep "${allProblemsMap[$problem]}" | sed -e "s#.\+href=\"\(.\+\)\">${allProblemsMap[$problem]}</a>.*#\1#")
      if [[ ${childURLGood} ]]; then 
        logdebug "[DEBUG] Found ${protocol}${domain}${childURLGood} - ${allProblemsMap[$problem]}"
        errataURLsMap["${protocol}${domain}${childURLGood}"]="${allProblemsMap[$problem]}"
        # remove the lines we've processed
        sed -i -e "s/.\+href=\"\(.\+\)\">${allProblemsMap[$problem]}<\/a>//" ${tmpdir}/page2.html
      fi
      # to only process a few items, use this breakpoint with maxNumErrataURLs >= 1
      if [[ ${#errataURLsMap[@]} -ge ${maxNumErrataURLs} ]] && [[ ${maxNumErrataURLs} -gt 0 ]]; then
        break 2
      fi
    done
    if [[ $(cat ${tmpdir}/page2.html) ]]; then
      # strip out waived items and info items by colour
      sed -i "/<td bgcolor=\"#00a37f\">/,/.\+href=\"\(.\+\)\">File list<\/a>/d" ${tmpdir}/page2.html #info
      sed -i "/<td bgcolor=\"#00DD00\">/,/.\+href=\"\(.\+\)\">.\+<\/a>/d" ${tmpdir}/page2.html #waived
      sed -i -e "s/--\|<td bgcolor=\"#00a37f\">\|<td bgcolor=\"#FFFF00\">\|<td bgcolor=\"#00DD00\">\|<td bgcolor=\"#FF0000\">//" ${tmpdir}/page2.html #other lines, other errors
      sed -i '/^$/d' ${tmpdir}/page2.html #empty lines
    fi      
    if [[ $(cat ${tmpdir}/page2.html | tr -d '[:space:]') ]]; then
      # echo -n "["; cat ${tmpdir}/page2.html; echo "]"
      unwaivedIssuesAll="$(cat ${tmpdir}/page2.html | sed -e "s#.\+href=\"\(.\+\)\">\(.\+\)</a>.*#\2:\1#" | \
        sed '/^$/d' | sed -e 's/^[ \t]*//' | sed -e "s# #_#")" # remove empty lines, trim whitespace, and replace spaves with underscores 
        # -->  "RPM_requires/provides:/rpmdiff/show/182461?result_id=5039915"
      unwaivedIssues=""
      for uni in ${unwaivedIssuesAll}; do
        u=${uni//_/ }; nwCheck=${u%%:*}
          collectThis=$u
          for p in "${!neverWaiveMap[@]}"; do # echo "check: [$nwCheck] vs "${neverWaiveMap[$p]}
            if [[ "${nwCheck}" == "${neverWaiveMap[$p]}" ]]; then collectThis=""; break; fi # found a never-waive item
          done
          if [[ ${collectThis} ]]; then unwaivedIssues="${unwaivedIssues} ${collectThis// /_}"; fi # collect this unwaived issue if it's not a never-waive one
      done
      if [[ ${unwaivedIssues} ]]; then
        logdebug "${red}[WARNING] Unwaived problem(s)${norm}:"
        for uni in ${unwaivedIssues}; do 
          u=${uni//_/ }
          url=${u##*:}; url=${url// /_}
          echo "  ! "${u%%:*}" : ${protocol}${domain}"${url}
        done
      fi
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
  for p in "${!allProblemsMap[@]}"; do # foreach key
    if [[ "${problemValue}" == "${allProblemsMap[$p]}" ]]; then
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

  # check if already waived before doing anything else
  previousWaiveReasons="$(egrep "This change is ok because" ${tmpdir}/page.html | sed -e "s#.\+This change is ok because ##" | \
    sed -e "s#I ran https://github.com/jbosstools/jbosstools-build-ci/blob/master/util/errataWaiveChecker.sh and ##" | \
    sed -e "s#\(.\+\)</pre># * \1#" | sort | uniq)"
  if [[ $(echo ${previousWaiveReasons} | egrep "revert-waive-text|Revert|textarea") ]]; then previousWaiveReasons=""; fi
  if [[ ${previousWaiveReasons} ]]; then
    let numErrata=numErrata+1
    log "[INFO] [${numErrata}/${totErrata}] Already waived ${blue}${errataURL}${norm} with reason:"
    log "${previousWaiveReasons}"
  else
    # determine the type of problem to check - look for <b>*Symlinks*</b> - page must include the correct string, 
    # and that must map to one of the problems we're processing
    if [[ ! ${previousWaiveReasons} ]] && [[ $(cat ${tmpdir}/page.html | egrep "<b>\*${allProblemsMap[$problem]}\*<\/b>") ]]; then # ok to proceed
      count=0
      # list of false positive problems to just skip w/o needing further processing
      if [[ ${falsePositiveProblemMap[${problem}]+keyExists} ]]; then
        rpmsToInstall=$(cat ${tmpdir}/page.html | egrep "NEEDS INSPECTION" -A4 \
          | sed -e "s#--\|.\+<td>.*\|.\+</td>.*\|.\+NEEDS INSPECTION.*##" | sort | uniq)

        if [[ ${rpmsToInstall} ]]; then
          for f in ${rpmsToInstall}; do let count=count+1; done
        fi
      # list of problems that require installing RPMs to verify
      elif [[ ${rpmInstallProblemMap[${problem}]+keyExists} ]]; then
        # TODO: add more checks here if required
        filesToCheck=$(cat ${tmpdir}/page.html | egrep "is a ${problem} \(to " | sed \
            -e "s#.\+This change is ok because.\+##" \
            -e "s#.\+<pre>File ##" \
            -e "s#.\+<pre>New file ##" \
            -e "s# is.\+${problem}.\+to #:#" \
            -e "s#) on.\+</pre>##")
        rpmsToInstall=$(cat ${tmpdir}/page.html | egrep "NEEDS INSPECTION" -A4 \
          | sed -e "s#--\|.\+<td>.*\|.\+</td>.*\|.\+NEEDS INSPECTION.*##" | sort | uniq)

        rpm=$(cat ${tmpdir}/page.html | egrep "Results for" | sed -e "s#<h1>.\+Results for \(.\+\) compared to .\+#\1#")
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
            #logdebug ""
            #logdebug "[DEBUG] pair = $f"
            alink=/${f%:*}
            if [[ ${f#*:} = "/"* ]]; then
              afile=${f#*:}
            else
              afile=${alink%/*}/${f#*:}
            fi
            status=""
            #logdebug "[DEBUG] alink = $alink"
            #logdebug "[DEBUG] afile = $afile"
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
                if [[ ${alink} != "/opt/rh"* ]] || [[ ${afile} != "/opt/rh"* ]]; then
                  cat ${tmpdir}/page.html | egrep -A5 -B5 "${f}"
                  log "${red}[ERROR] Parser error reading${norm} ${errataURL} - ${red}script must exit${norm}!"
                  log "Look in ${tmpdir}/page.html for problems and fix this script."
                  if [[ ${failNever} -eq 0 ]]; then exit 1; fi
                fi
                status="${red}[ERROR] Can't find ${norm}'${red}${alink}${norm}' -> '${red}${afile}${norm}'"
                let hadError=hadError+1
              fi
            fi
            if [[ ${status} ]]; then
              log "${status}"
            else
              #logdebug "[INFO] ${green}OK${norm}: ${alink} -> ${afile}"
              continue
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
    if [[ ${falsePositiveProblemMap[${problem}]+keyExists} ]]; then
      log "[INFO] [${numErrata}/${totErrata}] Found ${green}${hadError}${norm} of ${green}${count}${norm} ${problem}s at ${errataURL}"
    elif [[ ${rpmInstallProblemMap[${problem}]+keyExists} ]]; then
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
      data="${data}&waive_text="
      data="${data}This change is ok because I ran https://github.com/jbosstools/jbosstools-build-ci/blob/master/util/errataWaiveChecker.sh and "
      if [[ ${falsePositiveProblemMap[${problem}]+keyExists} ]]; then
        if [[ ${problem} == "changelog" ]]; then
          data="${data}this package was resynchronised with the Fedora upstream."
        else
          # nothing to check, these are always autowaived
          data="${data}${problem} errors are traditionally false positives which can be autowaived."
      fi
      elif [[ ${rpmInstallProblemMap[${problem}]+keyExists} ]]; then
        data="${data}after installing ${rpmInstallList:1}, all ${count} ${problem}s were resolved locally."
      fi

      errataWaiveURL=${errataURL%show/*}waive/${errataURL#*result_id=}
      logdebug "[DEBUG] Post waiver to ${errataWaiveURL}"
      logdebug "[DEBUG] ${data}"
      curl -s -S -k -X POST -u ${userpass} --data ${data// /%20} ${errataWaiveURL} > ${tmpdir}/page2.html
      log "[INFO] [${numErrata}/${totErrata}] Waived ${green}${errataURL}${norm}"
    elif [[ ${hadError} -gt 0 ]]; then
      log "${red}[ERROR]${norm} [${numErrata}/${totErrata}] Cannot auto-waive this result: found ${red}${hadError}${norm} of ${red}${count}${norm} ${problem}s at ${errataURL}"
      if [[ ${failNever} -eq 0 ]]; then exit 1; fi
    elif [[ ${waive} -eq 0 ]]; then
      log "[INFO] [${numErrata}/${totErrata}] To automatically waive this result, re-run this script with the ${blue}-waive${norm} flag."
    fi
  
  fi
  logdebug ""

  popd >/dev/null
  rm -fr ${tmpdir}

done