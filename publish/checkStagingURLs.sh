#!/bin/bash

# verify staging URLs are present and not 404'd
# 
# TODO: check file contents (eg., composite*.xml, directory.xml) and verify discovery jars are present
# TODO: check integration stack jars are present too

versionWithRespin_jbt=4.4.1.AM3
versionWithRespin_ds=10.1.0.AM3
devstudioReleaseVersion=10.0
eclipseReleaseName=neon

usage ()
{
  echo "Usage  : $0 -vrjbt [versionWithRespin_jbt] -vrds [versionWithRespin_ds] -dsrv [devstudioReleaseVersion] -ern [eclipseReleaseName]"
  echo "Example: $0 -vrjbt 4.4.1.AM3 -vrds 10.1.0.AM3 -dsrv 10.0 -ern neon"
  echo ""
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-vrjbt') vrjbt="${versionWithRespin_jbt} $2"; shift 1;;
    '-vrds') vrjbt="${versionWithRespin_ds} $2"; shift 1;;
    '-dsrv') devstudioReleaseVersion="$2"; shift 1;;
    '-ern') eclipseReleaseName="$2"; shift 1;;
  esac
  shift 1
done

norm="\033[0;39m"
green="\033[1;32m"
red="\033[1;31m"
OK=0
notOK=0

# check build folders
for u in http://download.jboss.org/jbosstools/${eclipseReleaseName}/staging/builds; do
  for f in core coretests central earlyaccess; do
    for ff in repo/artifacts.xml.xz repo/content.xml.xz repository.zip repository.zip.sha256; do
      a=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/all/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
    echo ""
  done
done

# discovery sites
for u in http://download.jboss.org/jbosstools/${eclipseReleaseName}/staging/builds; do
  for f in discovery.central; do
    for ff in compositeContent.xml compositeArtifacts.xml jbosstools-directory.xml plugins/; do
      a=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/all/repo/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
  echo ""
  for f in discovery.earlyaccess; do
    for ff in compositeContent.xml compositeArtifacts.xml jbosstools-directory.xml jbosstools-earlyaccess.properties plugins/; do
      a=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/all/repo/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

# browsersim-standalone.zip
for u in http://download.jboss.org/jbosstools/${eclipseReleaseName}/staging/builds; do
  for f in browsersim-standalone; do
    for ff in jbosstools-${versionWithRespin_jbt}-${f}.zip jbosstools-${versionWithRespin_jbt}-${f}.zip.sha256; do
      a=${u}/jbosstools-${versionWithRespin_jbt}-build-${f}/latest/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

# check update sites
for u in http://download.jboss.org/jbosstools/${eclipseReleaseName}/staging/updates; do
  for f in core coretests central earlyaccess; do
    for ff in artifacts.xml.xz content.xml.xz; do
      a=${u}/${f}/${versionWithRespin_jbt}/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
    echo ""
  done
done

# check discovery sites
for u in http://download.jboss.org/jbosstools/${eclipseReleaseName}/staging/updates; do
  for f in discovery.central; do
    for ff in jbosstools-directory.xml plugins/; do
      a=${u}/${f}/${versionWithRespin_jbt}/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
  echo ""
  for f in discovery.earlyaccess; do
    for ff in jbosstools-directory.xml jbosstools-earlyaccess.properties plugins/; do
      a=${u}/${f}/${versionWithRespin_jbt}/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

##################################

versionWithRespin_ds_latest=${versionWithRespin_ds%.*}.latest

# check installer build folder [INTERNAL]
for u in http://www.qa.jboss.com/binaries/devstudio/${devstudioReleaseVersion}/staging/builds/devstudio-${versionWithRespin_ds}-build-product/latest/all; do
  for f in devstudio-${versionWithRespin_ds_latest}-installer-eap.jar devstudio-${versionWithRespin_ds_latest}-installer-standalone.jar \
    devstudio-${versionWithRespin_ds_latest}-src.zip devstudio-${versionWithRespin_ds_latest}-updatesite-central.zip \
    devstudio-${versionWithRespin_ds_latest}-updatesite-core.zip; do
    for ff in $f ${f}.sha256; do
      echo -n "${u}/${ff}: "; stat=$(curl -I -s ${u}/${ff} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

# check installer build folder [EXTERNAL]
for u in https://devstudio.redhat.com/${devstudioReleaseVersion}/staging/builds/devstudio-${versionWithRespin_ds}-build-product/latest/all; do
  for f in devstudio-${versionWithRespin_ds_latest}-installer-standalone.jar \
    devstudio-${versionWithRespin_ds_latest}-src.zip devstudio-${versionWithRespin_ds_latest}-updatesite-central.zip \
    devstudio-${versionWithRespin_ds_latest}-updatesite-core.zip; do
    for ff in $f ${f}.sha256; do
      echo -n "${u}/${ff}: "; stat=$(curl -I -s ${u}/${ff} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

# check build folders
for u in https://devstudio.redhat.com/${devstudioReleaseVersion}/staging/builds; do
  for f in central earlyaccess; do
    for ff in repo/artifacts.xml.xz repo/content.xml.xz repository.zip repository.zip.sha256; do
      a=${u}/devstudio-${versionWithRespin_ds}-build-${f}/latest/all/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
	echo ""
  done
done

# discovery sites
for u in https://devstudio.redhat.com/${devstudioReleaseVersion}/staging/builds; do
  for f in discovery.central; do
    for ff in compositeContent.xml compositeArtifacts.xml devstudio-directory.xml plugins/; do
      a=${u}/devstudio-${versionWithRespin_ds}-build-${f}/latest/all/repo/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
  echo ""
  for f in discovery.earlyaccess; do
    for ff in compositeContent.xml compositeArtifacts.xml devstudio-directory.xml devstudio-earlyaccess.properties plugins/; do
      a=${u}/devstudio-${versionWithRespin_ds}-build-${f}/latest/all/repo/${ff}
      echo -n "${a}: "; stat=$(curl -I -s ${a} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

# check zips
for u in https://devstudio.redhat.com/${devstudioReleaseVersion}/staging/updates; do
  for f in core/devstudio-${versionWithRespin_ds}-updatesite-core.zip          core/devstudio-${versionWithRespin_ds}-target-platform.zip \
      central/devstudio-${versionWithRespin_ds}-updatesite-central.zip         core/devstudio-${versionWithRespin_ds}-target-platform-central.zip \
      earlyaccess/devstudio-${versionWithRespin_ds}-updatesite-earlyaccess.zip core/devstudio-${versionWithRespin_ds}-target-platform-earlyaccess.zip; do
    for ff in $f ${f}.sha256; do
      echo -n "${u}/${ff}: "; stat=$(curl -I -s ${u}/${ff} | egrep "404")
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

# check update sites
for u in https://devstudio.redhat.com/${devstudioReleaseVersion}/staging/updates; do
  for f in core central earlyaccess; do
    for ff in artifacts.xml.xz content.xml.xz; do
      echo -n "${u}/${f}/${versionWithRespin_ds}/${ff}: "; stat=$(curl -I -s ${u}/${f}/${versionWithRespin_ds}/${ff} | egrep "404"); 
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
	echo ""
  done
done

# check discovery sites
for u in https://devstudio.redhat.com/${devstudioReleaseVersion}/staging/updates; do
  for f in discovery.central; do
    for ff in compositeContent.xml compositeArtifacts.xml devstudio-directory.xml plugins/; do
      echo -n "${u}/${f}/${versionWithRespin_ds}/${ff}: "; stat=$(curl -I -s ${u}/${f}/${versionWithRespin_ds}/${ff} | egrep "404"); 
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
  echo ""
  for f in discovery.earlyaccess; do
    for ff in compositeContent.xml compositeArtifacts.xml devstudio-directory.xml devstudio-earlyaccess.properties plugins/; do
      echo -n "${u}/${f}/${versionWithRespin_ds}/${ff}: "; stat=$(curl -I -s ${u}/${f}/${versionWithRespin_ds}/${ff} | egrep "404"); 
      if [[ ! $stat ]]; then echo -e "${green}OK${norm}"; let OK+=1; else echo -e "${red}NO${norm}"; let notOK+=1; fi
    done
  done
done
echo ""

##################################

echo -e "[INFO] Found URLs: ${green}${OK}${norm}"
if [[ ${notOK} -gt 0 ]]; then 
	echo -e "[ERROR] Missing URLs: ${red}${notOK}${norm}"
	exit $notOK
fi
