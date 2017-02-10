#!/bin/bash

# verify staging/development/stable URLs are present and not 404'd

TARGET_PLATFORM_VERSION_MAX=""
qual=development # or stable
static=""
quiet=0

logn ()
{
  if [[ $quiet == 0 ]]; then echo -n -e "$1"; fi
}

log ()
{
  if [[ $quiet == 0 ]]; then echo -e "$1"; fi
}
logerr ()
{
  if [[ $quiet == 0 ]]; then 
    echo -e "$2"
  else
    echo -e "$1$2"
  fi
}

usage ()
{
  log "Usage (normal): $0 -v [TARGET_PLATFORM_VERSION_MAX]"
  log "Usage (quiet) : $0 -v [TARGET_PLATFORM_VERSION_MAX] -q"
  log ""
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-v') TARGET_PLATFORM_VERSION_MAX="$2"; shift 1;;
    '-q') quiet="1"; shift 0;;
  esac
  shift 1
done

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"
OK=0
notOK=0

if [[ ${TARGET_PLATFORM_VERSION_MAX} ]]; then

  # check that the redirection composites are in place
  if [[ ${TARGET_PLATFORM_VERSION_MAX} == *".Final" ]]; then
    static="";
    for u in http://download.jboss.org/jbosstools/${static}targetplatforms/jbosstoolstarget \
             https://devstudio.jboss.com/${static}targetplatforms/jbdevstudiotarget; do
      t=${u%%/}; t=${t##*/}; # echo $t; # jbosstoolstarget or jbdevstudiotarget      
      for f in ${TARGET_PLATFORM_VERSION_MAX}; do
        for ff in / /REPO; do
          a=${u}/${f}${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm}"; let notOK+=1; fi
          for j in compositeArtifacts.xml compositeContent.xml p2.index; do
            logn " + ${j} : "; stat=$(curl -I -s ${a}/${j} | egrep "404")
            if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm}"; let notOK+=1; fi
          done
        done
      done
      log ""
    done  
  fi

  if [[ ${TARGET_PLATFORM_VERSION_MAX} == *".Final" ]]; then 
    static="static/"
    qual="stable"
  fi

  # check that the main site is in place, whether it's a .Final under /static/targetplatforms/ or a SNAPSHOT under /targetplatforms/
  for u in http://download.jboss.org/jbosstools/${static}targetplatforms/jbosstoolstarget \
           https://devstudio.jboss.com/${static}targetplatforms/jbdevstudiotarget; do
    t=${u%%/}; t=${t##*/}; # echo $t; # jbosstoolstarget or jbdevstudiotarget

    for f in ${TARGET_PLATFORM_VERSION_MAX}; do
      for ff in / /REPO; do
        a=${u}/${f}${ff}
        logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404")
        if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm}"; let notOK+=1; fi

        if [[ ${ff} == "/REPO" ]]; then
          for j in artifacts.jar binary content.jar features plugins; do
            logn " + ${j} : "; stat=$(curl -I -s ${a}/${j} | egrep "404")
            if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm}"; let notOK+=1; fi
          done
        else
          for j in compositeArtifacts.xml compositeContent.xml ${t}-${TARGET_PLATFORM_VERSION_MAX}.zip ${t}-${TARGET_PLATFORM_VERSION_MAX}.zip.sha256; do
            logn " + ${j} : "; stat=$(curl -I -s ${a}/${j} | egrep "404")
            if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} s: " "${red}NO${norm}"; let notOK+=1; fi
          done
        fi
      done
    done
    log ""
  done
fi


##################################

log "[INFO] $qual URLs found: ${OK}"
if [[ ${notOK} -gt 0 ]]; then 
  logerr "" "[ERROR] $qual URLs missing: ${notOK}"
  exit $notOK
fi
