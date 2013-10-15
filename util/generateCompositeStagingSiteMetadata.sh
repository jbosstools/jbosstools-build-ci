#!/bin/bash

# this Jenkins script is used to produce a pair of composite*.xml files based on these parameters:

# -NUM      :: number of new builds to include per JOB_NAME
# -NAME     :: name of the resulting site, eg., 'JBoss Tools - Core - Stable Staging Site'
# -SITES    :: comma-separated list of URLs of additional update sites to include in the composite, eg., for components which have not changed
# -JOBNAMES :: comma-separated list of JOB_NAMEs - for each, search in /builds/staging/JOB_NAME/ for subfolders, and return the N most recent ones
# -DESTINATION :: sftp (or local?) path to publish composite*.xml files, eg., tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging/_composite_/core/4.1.x.kepler/

usage ()
{
  echo "Usage    : $0 -NUM <num builds to include, eg., 1 or 2> -NAME 'Site Name' \
-DESTINATION tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging/_composite_/path/goes/here/ \
-SITES http://download.jboss.org/jbosstools/updates/site/to/include1,http://download.jboss.org/jbosstools/updates/site/to/include2,... \
-JOBNAMES <job1,job2,job3,...> "
  echo ""
  echo "Example 1 (stable branch site): $0 -NUM 1 -NAME 'JBoss Tools - Core - Stable Branch Staging Site' \
-DESTINATION tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging/_composite_/core/4.1.x.kepler/ \
-SITES \
http://download.jboss.org/jbosstools/updates/stable/kepler/,\
http://download.jboss.org/jbosstools/updates/stable/juno/core/gwt/,\
http://download.jboss.org/jbosstools/updates/stable/kepler/core/freemarker/ \
-JOBNAMES \
jbosstools-aerogear_41,\
jbosstools-arquillian_41,\
jbosstools-base_41,\
jbosstools-birt_41,\
jbosstools-central_41,\
jbosstools-forge_41,\
jbosstools-hibernate_41,\
jbosstools-javaee_41,\
jbosstools-jst_41,\
jbosstools-livereload_41,\
jbosstools-openshift_41,\
jbosstools-portlet_41,\
jbosstools-server_41,\
jbosstools-vpe_41,\
jbosstools-webservices_41,\
openshift-java-client-master\
"
  echo ""
  echo "Example 2 (master branch site): $0 -NUM 2 -NAME 'JBoss Tools - Core - Master Branch Staging Site' \
-DESTINATION tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging/_composite_/core/master/ \
-SITES \
http://download.jboss.org/jbosstools/updates/requirements/xulrunner-1.9.2/,\
http://download.jboss.org/jbosstools/updates/stable/juno/core/gwt/,\
http://download.jboss.org/jbosstools/updates/stable/kepler/core/freemarker/ \
-JOBNAMES \
jbosstools-aerogear_master,\
jbosstools-arquillian_master,\
jbosstools-base_master,\
jbosstools-birt_master,\
jbosstools-central_master,\
jbosstools-forge_master,\
jbosstools-hibernate_master,\
jbosstools-javaee_master,\
jbosstools-jst_master,\
jbosstools-livereload_master,\
jbosstools-openshift_master,\
jbosstools-portlet_master,\
jbosstools-server_master,\
jbosstools-vpe_master,\
jbosstools-webservices_master,\
openshift-java-client-master\
"
  # TODO JBIDE-15482 ensure example matches with actual path we settle on (ie., builds/staging/CI or builds/ci/)
  echo ""
  echo "Example 3 (local site - do not use JOBNAMES): $0 -NAME 'My Local Upstream Composite Site' \
-DESTINATION /tmp/my-local-site/ \
-SITES \
http://download.jboss.org/jbosstools/updates/requirements/xulrunner-1.9.2/,\
http://download.jboss.org/jbosstools/builds/staging/CI/jbosstools-base_master/2013-09-25_09-26-23-B349/all/repo/,\
http://download.jboss.org/jbosstools/builds/staging/CI/jbosstools-server_master/2013-09-24_04-26-25-B380/all/repo/
"
	exit 1;
}

if [[ $# -lt 1 ]]; then
	usage;
fi

#defaults
NUM=1
NAME=""
SITES=""
JOBNAMES=""
DESTINATION="" # default to tools@filemgmt.jboss.org:/downloads_htdocs/tools/builds/staging/_composite_/core/master/ ?
PATHPREFIX="/downloads_htdocs/tools"
URLPREFIX="http://download.jboss.org/jbosstools"
CIPATH="builds/staging/CI"
childFolderSuffix="/all/repo"

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
    '-NUM') NUM="$2"; shift 1;;
    '-NAME') NAME="$2"; shift 1;;
		'-SITES') SITES="$2"; shift 1;;
    '-JOBNAMES') JOBNAMES="$2"; shift 1;;
    '-DESTINATION') DESTINATION="$2"; shift 1;;
	esac
	shift 1
done

# without a destination folder there's little point in proceeding here
if [[ ! $DESTINATION ]]; then
  usage; exit 1
fi

# if using this script to generate a composite site locally, blank out PATHPREFIX, URLPREFIX, and JOBNAMES
if [[ ${DESTINATION//@} == ${DESTINATION//@} ]]; then
  JOBNAMES=""
  PATHPREFIX=""
  URLPREFIX=""
fi

mkdirs ()
{
  fullPath=$1
  if [[ ${fullPath##*@*:*} == "" ]]; then # user@server, do remote op
    # break fullPath into series of folders
    server=${fullPath%%:/*}
    dirs=${fullPath##*@*:/}
    dirs=${dirs//\// }
    e=""
    for d in $dirs; do
      # echo "mkdir $d | sftp $server:/$e"
      if [[ ! `echo "ls" | sftp $server:/${e} 2>/dev/null | grep ${d}` ]]; then
        echo -e "mkdir ${d}" | sftp $server:/${e} 2>/dev/null
      fi
      if [[ $e ]]; then e=${e}/$d; else e=$d; fi
    done
  else
    mkdir -p $fullPath
  fi
}

countItems () 
{
  list="$1"
  listItems="${list//,/ }"
  itemCount=0
  for c in ${listItems}; do 
    (( itemCount++ ))
  done
}

getSubDirs () 
{
  getSubDirsReturn="";
  tab="";
  if [[ $1 ]]; then dir="$1"; else dir="${PATHPREFIX}/${CIPATH}"; fi
  if [[ $2 ]] && [[ $2 -gt 0 ]]; then
    lev=$2
    while [[ $lev -gt 0 ]]; do  
      tab=$tab"> ";
      (( lev-- ));
    done
  fi
  #echo "" | tee -a $log; echo "${tab}Check $dir..." | tee -a $log
  tmp=`mktemp`
  echo "ls $dir" > $tmp
  dirs=$(sftp -b $tmp tools@filemgmt.jboss.org 2>/dev/null)
  i=0
  for c in $dirs; do #exclude *.xml, *.html, *.properties, *.jar, *.zip, web/features/plugins/binary/.blobstore
    if [[ $i -gt 2 ]] && [[ $c != "sftp>" ]] && [[ ${c##*.} != "" ]] && [[ ${c##*/*.*ml} != "" ]] && [[ ${c##*/*.properties} != "" ]] && [[ ${c##*/*.jar} != "" ]] && [[ ${c##*/*.zip} != "" ]] && [[ ${c##*/web} != "" ]] && [[ ${c##*/plugins} != "" ]] && [[ ${c##*/features} != "" ]] && [[ ${c##*/binary} != "" ]] && [[ ${c##*/.blobstore} != "" ]]; then
      getSubDirsReturn=$getSubDirsReturn","$c
    fi
    (( i++ ))
  done
  rm -f $tmp
}

regenProcess ()
{
  subdirCount=$1
  subdirs=$2

  # count static URLs added via -SITES
  countItems "${SITES}"
  numSites=$itemCount
  # echo "Found $numSites URLs to feed to composite site (NAME = ${NAME}" | tee -a $log 
  # get a total count of child folders + static URLs
  countChildren=0
  (( countChildren = subdirCount + numSites ))
  if [[ $countChildren -gt 0 ]]; then
    echo "Generate metadata for $numSites URLs + ${subdirCount} builds" | tee -a $log
    mkdir -p /tmp/cleanup-fresh-metadata/
    regenCompositeMetadata "$NAME" "${subdirs}" "$countChildren" "org.eclipse.equinox.internal.p2.metadata.repository.CompositeMetadataRepository" "/tmp/cleanup-fresh-metadata/compositeContent.xml"
    regenCompositeMetadata "$NAME" "${subdirs}" "$countChildren" "org.eclipse.equinox.internal.p2.artifact.repository.CompositeArtifactRepository" "/tmp/cleanup-fresh-metadata/compositeArtifacts.xml"
    # cat /tmp/cleanup-fresh-metadata/composite*.xml

    # ensure the target folder exists
    if [[ `echo "ls" | sftp $DESTINATION 2>&1 | grep "not found"` ]]; then mkdirs $DESTINATION; fi

    echo "Publish composite*.xml to ${DESTINATION}" | tee -a $log
    rsync --rsh=ssh --protocol=28 -q /tmp/cleanup-fresh-metadata/composite*.xml $DESTINATION
    if [[ ${URLPREFIX} ]]; then 
      echo ">> "${URLPREFIX}${DESTINATION##*${PATHPREFIX}} | tee -a $log
    fi
    rm -fr /tmp/cleanup-fresh-metadata/
  else
    echo "No SITES or builds found for specified JOBNAMES" | tee -a $log 
  fi
}

#regen metadata for static SITES and filtered list of NUM x subdirs
regenCompositeMetadata ()
{
  siteName=$1
  subdirs=$2
  countChildren=$3
  fileType=$4
  fileName=$5
  now=$(date +%s000)

  echo "<?xml version='1.0' encoding='UTF-8'?><?compositeArtifactRepository version='1.0.0'?>
<repository name='${siteName}' type='${fileType}' version='1.0.0'>
<properties size='2'><property name='p2.timestamp' value='${now}'/><property name='p2.compressed' value='true'/></properties>
<children size='${countChildren}'>" > ${fileName}
  siteItems="${SITES//,/ }"
  for site in $siteItems; do
    echo "<child location='${site}'/>" >> ${fileName}
  done
  subdirItems="${subdirs//,/ }"
  for sd in $subdirItems; do
    echo "<child location='${sd}${childFolderSuffix}'/>" >> ${fileName}
  done
  echo "</children>
</repository>
" >> ${fileName}
}

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=`pwd`; fi
cd ${WORKSPACE}

subdirs=""
subdirCount=0
# for a given list of JOBNAMES
for sd in ${JOBNAMES//,/ }; do
  getSubDirs ${PATHPREFIX}/${CIPATH}/${sd} 0
  # echo "Found these builds: $getSubDirsReturn"
  subsubdirs="${getSubDirsReturn}"
  tmp=`mktemp`
  subdirItems="${subsubdirs//,/ }"
  for ssd in $subdirItems; do
    if [[ ${ssd##*$sd/201*} == "" ]]; then # a build dir
      buildid=${ssd##*/}; 
      echo $buildid >> $tmp # 2013-09-24_14-46-04-B13
    fi
  done
  newest=$(cat $tmp | sort -r | head -${NUM}) # keep these
  rm -f $tmp
  for dd in $newest; do
    keep=0;
    # convert buildID (folder) to timestamp, then to # seconds since 2009-01-01 00:00:00 (1230786000)
    sec=$(date -d "$(echo $dd | perl -pe "s/(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})-(H|B)(\d+)/\1-\2-\3\ \4:\5:\6/")" +%s); (( sec = sec - 1230786000 ))
    now=$(date +%s); (( now = now - 1230786000 ))
    (( day = now - sec )) 
    (( day = day / 3600 / 24 ))
    echo "+ $sd/$dd (${day}d)" | tee -a $log
    subdirs="${subdirs},${URLPREFIX}/${CIPATH}/$sd/$dd"
  done
done
rm -f $tmp
echo $itemCount
countItems $subdirs
subdirCount=$itemCount

# search for subfolders, order them, and pull out the NUM newest ones (1 if stable milestone site, or 2 if master site)
# then generate composite*.xml files using those (dirs x NUM) + the SITES + the NAME
regenProcess $subdirCount "${subdirs}"
