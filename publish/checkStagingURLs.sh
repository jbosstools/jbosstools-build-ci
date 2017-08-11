#!/bin/bash

# verify staging/development/stable URLs are present and not 404'd

versionWithRespin_jbt=""
versionWithRespin_ds=""
devstudioReleaseVersion=10.0
eclipseReleaseName=neon
qual=staging # or snapshots or development or stable
static=""
quiet=0
skipdiscovery=0; # flag to skip discovery sites check
onlydiscovery=0; # flag to only check discovery sites
OPTIONS="" # container for options so we can dump them into the console for logging

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
  log "Usage  : $0 -vrjbt [versionWithRespin_jbt] -vrds [versionWithRespin_ds] -dsrv [devstudioReleaseVersion] -ern [eclipseReleaseName]"
  log "Example: $0 -vrjbt 4.4.1.Final -ern  neon -qual development"
  log "Example: $0 -vrds    10.1.0.GA -dsrv 10.0 -qual stable"
  log "Example: $0 -vrjbt 4.4.1.Final -vrds 10.1.0.GA -dsrv 10.0 -ern neon -qual development"
  log ""
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-vrjbt') versionWithRespin_jbt="$2"; shift 1;;
    '-vrds') versionWithRespin_ds="$2"; shift 1;;
    '-dsrv') devstudioReleaseVersion="$2"; shift 1;;
    '-ern') eclipseReleaseName="$2"; shift 1;;
    '-qual') qual="$2"; shift 1;;
    '-q') quiet="1"; shift 0;;
    '-skipdiscovery') skipdiscovery=1; OPTIONS="${OPTIONS} skipdiscovery"; shift 0;;
    '-onlydiscovery') onlydiscovery=1; OPTIONS="${OPTIONS} onlydiscovery"; shift 0;;
  esac
  shift 1
done

tmpdir=`mktemp -d`
mkdir -p $tmpdir

checkCompositeXML ()
{
    url=$1
    # echo "Check children of $url ..."
    # parse the file for <child location="" URLs>
    urls=$(wget -q --no-check-certificate ${url} -O - | grep "<child location" | sed -e "s#.*location=.\(.\+\).\/>.*#\1#")
    for a in ${urls}; do
        if [[ ${a} != "http"* ]]; then # relative path
            a=${url%/composite*xml}/${a}
        fi
        logn " > ${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
        if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
    done
}

norm="\033[0;39m"
green="\033[1;32m"
yellow='\e[0;30m\e[1;43m' # yellow reversed
red="\033[1;31m"
OK=0
notOK=0
versionWithRespin_ds_latest=${versionWithRespin_ds%.*}.latest

# when not staging, check for static/ URLs and don't check for .latest symlinks but actual files
if [[ ${qual} == "development" ]] || [[ ${qual} == "stable" ]]; then
  static="static/"
fi

if [[ ${versionWithRespin_jbt} ]]; then

  # if versionWithRespin_jbt ends with any of abcdwxyz, trim tht character off to get version_jbt without the respin-suffix
  version_jbt=$(echo ${versionWithRespin_jbt} | sed -e '/[abcdwxyz]$/ s/\(^.*\)\(.$\)/\1/')

  # discovery sites
  if [[ ${skipdiscovery} -lt 1 ]] || [[ ${onlydiscovery} -gt 0 ]]; then 
    for u in http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/builds \
             http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/updates; do
      for f in discovery.central discovery.earlyaccess; do
        for ff in compositeContent.xml compositeArtifacts.xml jbosstools-earlyaccess.properties jbosstools-directory.xml plugins/; do
          if [[ ${f} == "discovery.central" ]] && [[ ${ff/earlyaccess.properties/} != ${ff} ]]; then continue; fi # skip check for central + earlyaccess.properties
          if [[ ${u/builds/} != ${u} ]]; then
            if [[ ${qual} == "snapshots" ]]; then
              b=${u}/jbosstools-${f}_${versionWithRespin_jbt}/latest/all/repo/${ff} # builds
            else
              b=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/all/repo/${ff} # builds
            fi
          else
            b="${u}/${f}/${versionWithRespin_jbt}/${ff} ${u}/${f}/${ff}" # updates
          fi
          for a in ${b}; do
            if [[ ${ff} == "composite"*".xml" ]] || [[ ${a} == ${u}/${f}/${versionWithRespin_jbt}/${ff} ]] || [[ ${u/builds/} != ${u} ]]; then
              logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
              if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
            fi
            if [[ ${ff} == "composite"*".xml" ]]; then
              checkCompositeXML ${a}
            elif [[ ${a} == ${u}/${f}/${versionWithRespin_jbt}/${ff} ]] || [[ ${u/builds/} != ${u} ]]; then
              if [[ ${ff} == "plugins/" ]]; then
                jars=$(curl -s ${a} | grep ".jar" | sed -e "s#.\+href=\"\([^\"]\+\)\".\+#\1#")
                # check jar 404s
                for j in ${jars}; do
                  logn " + ${j} : "; stat=$(curl -I -s ${a}${j} | egrep "404 Not Found")
                  if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
                done
              elif [[ ${ff/directory.xml} != ${ff} ]]; then
                jars=$(curl -s ${a} | grep "url" | sed -e "s#.\+url=\"\([^\"]\+\)\".\+#\1#")
                # check jar 404s
                for j in ${jars}; do
                  logn " + ${j} : "; stat=$(curl -I -s ${a/${ff}/${j}} | egrep "404 Not Found")
                  if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
                done
              fi
            fi
          done
        done
      done
      log ""
    done
  fi

  if [[ ${onlydiscovery} -lt 1 ]]; then 
    # build folders
    for u in http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/builds; do
      for f in coretests central earlyaccess integration-tests core; do
        for ff in repo/artifacts.xml.xz repo/content.xml.xz repo/category.xml repo/buildinfo.json repository.zip repository.zip.sha256; do
          a=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/all/${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
        log ""
      done
    done
    for u in http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/builds; do
      for f in fuse-extras; do
        for ff in repo/artifacts.xml.xz repo/content.xml.xz repo/category.xml repo/buildinfo.json; do # no repo zip to check here
          a=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/all/${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
        log ""
      done
    done

    # browsersim-standalone.zip in browsersim (parent) folder
    for u in http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/builds; do
      fp=browsersim
      f=browsersim-standalone
      for ff in jbosstools-${version_jbt}-${f}.zip jbosstools-${version_jbt}-${f}.zip.sha256; do
        a=${u}/jbosstools-${versionWithRespin_jbt}-build-${fp}/latest/
        logn "${a}${ff} : "; stat=$(curl -I -s ${a}${ff} | egrep "404 Not Found")
        if [[ ! $stat ]]; then
          log "${green}OK${norm}"; let OK+=1
        else
          # could be running with respin suffix or we're mock building so this might be OK. Check folder for children instead.
          ext=".zip"${ff##*.zip}
          zips=$(curl -s ${a} | grep "${ext}\"" | sed -e "s#.\+href=\"\([^\"]\+\)\".\+#\1#")
          if [[ ! ${zips} ]]; then
            logerr "${a} : " "${red}NO ${ext} FOUND${norm} : $(curl -I -s ${a})"; let notOK+=1;
          else
            log "${yellow}WARNING${norm}"
            for j in ${zips}; do
              logn " => ${j} : "; stat=$(curl -I -s ${a}${j} | egrep "404 Not Found")
              if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm} \n$(curl -I -s ${a}${j})"; let notOK+=1; fi
            done
          fi
        fi
      done
    done
    log ""

    # update sites
    for u in http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/updates; do
      for f in fuse-extras coretests central earlyaccess integration-tests core; do
        for ff in artifacts.xml.xz content.xml.xz category.xml buildinfo.json; do
          a=${u}/${f}/${versionWithRespin_jbt}/${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
        log ""
      done
    done

    # released artifacts linked from tools.jboss.org
    if [[ $qual != "staging" ]]; then 
      for u in http://download.jboss.org/jbosstools/${static}${eclipseReleaseName}/${qual}/updates/core; do
        for f in browsersim-standalone src updatesite-core; do
          for ff in jbosstools-${version_jbt}-${f}.zip jbosstools-${version_jbt}-${f}.zip.sha256; do
            a=${u}/${ff}
            logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
            if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
          done
        done
      done
    fi
  fi
fi

##################################

if [[ ${versionWithRespin_ds} ]]; then

  # if versionWithRespin_jbt ends with any of abcdwxyz, trim tht character off to get version_jbt without the respin-suffix
  version_ds=$(echo ${versionWithRespin_ds} | sed -e '/[abcdwxyz]$/ s/\(^.*\)\(.$\)/\1/')

  # check installer build folder [INTERNAL]
  versionWithRespin_ds_latest_actual=${versionWithRespin_ds_latest} # normally this is a .latest filename
  if [[ ${qual} == "stable" ]]; then 
    versionWithRespin_ds_latest_actual=${versionWithRespin_ds} # but for stable, look for .GA
  fi

  # discovery sites
  if [[ ${skipdiscovery} -lt 1 ]] || [[ ${onlydiscovery} -gt 0 ]]; then 
    for u in https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/builds \
             https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/updates; do
      for f in discovery.central discovery.earlyaccess; do
        for ff in compositeContent.xml compositeArtifacts.xml devstudio-earlyaccess.properties devstudio-directory.xml plugins/; do
          if [[ ${f} == "discovery.central" ]] && [[ ${ff/earlyaccess.properties/} != ${ff} ]]; then continue; fi # skip check for central + earlyaccess.properties
          if [[ ${u/builds/} != ${u} ]]; then
            if [[ ${qual} == "snapshots" ]]; then
              b=${u}/jbosstools-${f}_${versionWithRespin_jbt}/latest/all/repo/${ff} # builds
            else
              b=${u}/devstudio-${versionWithRespin_ds}-build-${f}/latest/all/repo/${ff} # builds
            fi
          else
            b="${u}/${f}/${versionWithRespin_ds}/${ff} ${u}/${f}/${ff}" # updates
          fi
          for a in ${b}; do
            if [[ ${ff} == "composite"*".xml" ]] || [[ ${a} == ${u}/${f}/${versionWithRespin_ds}/${ff} ]] || [[ ${u/builds/} != ${u} ]]; then
              logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
              if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
            fi
            if [[ ${ff} == "composite"*".xml" ]]; then
              checkCompositeXML ${a}
            elif [[ ${a} == ${u}/${f}/${versionWithRespin_ds}/${ff} ]] || [[ ${u/builds/} != ${u} ]]; then
              if [[ ${ff} == "plugins/" ]]; then
                jars=$(curl -s ${a} | grep ".jar" | sed -e "s#.\+href=\"\([^\"]\+\)\".\+#\1#")
                # check jar 404s
                for j in ${jars}; do
                  logn " + ${j} : "; stat=$(curl -I -s ${a}${j} | egrep "404 Not Found")
                  if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
                done
              elif [[ ${ff/directory.xml} != ${ff} ]]; then
                jars=$(curl -s ${a} | grep "url" | sed -e "s#.\+url=\"\([^\"]\+\)\".\+#\1#")
                # check jar 404s
                for j in ${jars}; do
                  logn " + ${j} : "; stat=$(curl -I -s ${a/${ff}/${j}} | egrep "404 Not Found")
                  if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr " + ${j} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
                done
              fi
            fi
          done
        done
      done
      log ""
    done
  fi

  if [[ ${onlydiscovery} -lt 1 ]]; then 
    # no longer publishing to wonka 
    # zips: only if /stable/ or /staging/
    # if [[ ${qual} != "development" ]]; then
    #   for u in http://wonka.mw.lab.eng.bos.redhat.com/rhd/devstudio/${devstudioReleaseVersion}/${qual}/builds/devstudio-${versionWithRespin_ds}-build-product/latest/all; do
    #     for f in devstudio-${versionWithRespin_ds_latest_actual}-installer-standalone.jar \
    #       devstudio-${versionWithRespin_ds_latest_actual}-updatesite-central.zip devstudio-${versionWithRespin_ds_latest_actual}-updatesite-core.zip; do
    #       for ff in $f ${f}.sha256; do
    #         a=${u}/${ff}
    #         logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
    #         if [[ $stat ]]; then # try backup URL (.latest or .GA)
    #           #logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"
    #           log ""
    #           a=${u}/${ff/.latest/.GA}
    #           logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
    #         fi
    #         if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
    #       done
    #     done
    #   done
    # fi
    # log ""

    # installer build folder [EXTERNAL]
    for u in https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/builds/devstudio-${versionWithRespin_ds}-build-product/latest/all; do
      for f in devstudio-${versionWithRespin_ds_latest_actual}-installer-standalone.jar \
        devstudio-${versionWithRespin_ds_latest_actual}-updatesite-central.zip devstudio-${versionWithRespin_ds_latest_actual}-updatesite-core.zip; do
        for ff in $f ${f}.sha256; do
            a=${u}/${ff}
            logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
            if [[ $stat ]]; then # try backup URL (.latest or .GA)
              #logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"
              log ""
              a=${u}/${ff/.latest/.GA}
              logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
            fi
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${u}/${ff} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
      done
    done
    log ""

    # build folders
    for u in https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/builds; do
      for f in central earlyaccess; do
        for ff in repo/artifacts.xml.xz repo/content.xml.xz repo/category.xml repo/buildinfo.json repository.zip repository.zip.sha256; do
          a=${u}/devstudio-${versionWithRespin_ds}-build-${f}/latest/all/${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
      log ""
      done
    done
    for u in https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/builds; do
      for f in fuse-extras; do
        for ff in repo/artifacts.xml.xz repo/content.xml.xz repo/category.xml repo/buildinfo.json; do # no repo zip to check here
          a=${u}/devstudio-${versionWithRespin_ds}-build-${f}/latest/all/${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
      log ""
      done
    done

    # yum repo for rpm: only if /stable/ or /staging/
    # https://devstudio.jboss.com/10.0/staging/builds/devstudio-10.2.0.GA-build-rpm/latest/x86_64/
    # https://devstudio.jboss.com/static/10.0/stable/rpms/x86_64/
    if [[ ${qual} == "staging" ]]; then
      u=https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/builds/devstudio-${versionWithRespin_ds}-build-rpm/latest
    else
      u=https://devstudio.jboss.com/${static}${devstudioReleaseVersion}/${qual}/rpms
    fi
    if [[ ${qual} != "development" ]]; then
      for ff in x86_64/README.html x86_64/repodata/repomd.xml; do
        a=${u}/${ff}
        logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
        if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
      done
    fi
    log ""

    # zips
    for u in https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/updates; do
      for f in core/devstudio-${versionWithRespin_ds}-updatesite-core.zip          core/devstudio-${versionWithRespin_ds}-target-platform.zip \
          central/devstudio-${versionWithRespin_ds}-updatesite-central.zip         core/devstudio-${versionWithRespin_ds}-target-platform-central.zip \
          earlyaccess/devstudio-${versionWithRespin_ds}-updatesite-earlyaccess.zip core/devstudio-${versionWithRespin_ds}-target-platform-earlyaccess.zip; do
        for ff in $f ${f}.sha256; do
          logn "${u}/${ff} : "; stat=$(curl -I -s ${u}/${ff} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${u}/${ff} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
      done
    done
    log ""

    # check update sites
    for u in https://devstudio.redhat.com/${static}${devstudioReleaseVersion}/${qual}/updates; do
      for f in fuse-extras core central earlyaccess; do
        for ff in artifacts.xml.xz content.xml.xz category.xml buildinfo.json; do
          a=${u}/${f}/${versionWithRespin_ds}/${ff}
          logn "${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
          if [[ ! $stat ]]; then log "${green}OK${norm}"; let OK+=1; else logerr "${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"; let notOK+=1; fi
        done
      log ""
      done
    done
  fi

fi

##################################

log "[INFO] $qual URLs found: ${OK} (${OPTIONS})"
if [[ ${notOK} -gt 0 ]]; then 
  logerr "" "[ERROR] $qual URLs missing: ${notOK} (${OPTIONS})"
  exit $notOK
fi
