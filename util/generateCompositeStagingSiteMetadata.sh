#!/bin/bash

# this Jenkins script is used to produce a pair of composite*.xml files based on these parameters:

# -NUM      :: number of new builds to include per JOB_NAME
# -NAME     :: name of the resulting site, eg., 'JBoss Tools - Core - Stable Staging Repository'
# -SITES    :: comma-separated list of URLs of additional update sites to include in the composite, eg., for components which have not changed
# -JOBNAMES :: comma-separated list of JOB_NAMEs - for each, search in /builds/staging/JOB_NAME/ for subfolders, and return the N most recent ones
usage ()
{
  echo "Usage    : $0 -NUM <num builds to include> -NAME 'Site Name' -JOBNAMES <job1,job2,job3,...> \
-SITES http://download.jboss.org/jbosstools/updates/site/to/include1,http://download.jboss.org/jbosstools/updates/site/to/include,..."
  echo ""
  echo "Example 1: $0 -NUM 1 -NAME 'JBoss Tools - Core - Stable Staging Repository' -SITES \
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
  echo "Example 2: $0 -NUM 2 -NAME 'JBoss Tools - Core - Trunk Staging Repository' -SITES \
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

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
    '-NUM') NUM="$2"; shift 1;;
    '-NAME') NAME="$2"; shift 1;;
		'-SITES') SITES="$2"; shift 1;;
    '-JOBNAMES') JOBNAMES="$2"; shift 1;;
	esac
	shift 1
done

getSubDirs () 
{
  getSubDirsReturn="";
  tab="";
  if [[ $1 ]]; then dir="$1"; else dir="/downloads_htdocs/tools/builds/nightly/"; fi
  if [[ $2 ]] && [[ $2 -gt 0 ]]; then
    lev=$2
    while [[ $lev -gt 0 ]]; do  
      tab=$tab"> ";
      (( lev-- ));
    done
  fi
  echo "${tab}Check $dir..." | tee -a $log
  tmp=`mktemp`
  echo "ls $dir" > $tmp
  dirs=$(sftp -b $tmp tools@filemgmt.jboss.org 2>/dev/null)
  i=0
  for c in $dirs; do #exclude *.xml, *.html, *.properties, *.jar, *.zip, web/features/plugins/binary/.blobstore
    if [[ $i -gt 2 ]] && [[ $c != "sftp>" ]] && [[ ${c##*.} != "" ]] && [[ ${c##*/*.*ml} != "" ]] && [[ ${c##*/*.properties} != "" ]] && [[ ${c##*/*.jar} != "" ]] && [[ ${c##*/*.zip} != "" ]] && [[ ${c##*/web} != "" ]] && [[ ${c##*/plugins} != "" ]] && [[ ${c##*/features} != "" ]] && [[ ${c##*/binary} != "" ]] && [[ ${c##*/.blobstore} != "" ]]; then
      getSubDirsReturn=$getSubDirsReturn" "$c
    fi
    (( i++ ))
  done
  rm -f $tmp
}

# TODO adapt this to work for new params
regenProcess ()
{
  subdirCount=$1
  sd=$2
  all=$(cat $tmp | sort -r) # check these
  rm -f $tmp
  if [[ $subdirCount -gt 0 ]]; then
    siteName=${sd##*/downloads_htdocs/tools/}
    echo "Generate metadata for ${subdirCount} subdir(s) in $sd/ (siteName = ${siteName}" | tee -a $log
    mkdir -p /tmp/cleanup-fresh-metadata/
    regenCompositeMetadata "$siteName" "$all" "$subdirCount" "org.eclipse.equinox.internal.p2.metadata.repository.CompositeMetadataRepository" "/tmp/cleanup-fresh-metadata/compositeContent.xml"
    regenCompositeMetadata "$siteName" "$all" "$subdirCount" "org.eclipse.equinox.internal.p2.artifact.repository.CompositeArtifactRepository" "/tmp/cleanup-fresh-metadata/compositeArtifacts.xml"
    rsync --rsh=ssh --protocol=28 -q /tmp/cleanup-fresh-metadata/composite*.xml tools@filemgmt.jboss.org:$sd/
    rm -fr /tmp/cleanup-fresh-metadata/
  else
    echo "No subdirs found in $sd/" | tee -a $log 
  fi
}

# TODO adapt this to run using NUM x dirs, SITES, and NAME
#regen metadata for remaining subdirs in this folder
regenCompositeMetadata ()
{
  siteName=$1
  subsubdirs=$2
  countChildren=$3
  fileType=$4
  fileName=$5
  now=$(date +%s000)
  
  echo "<?xml version='1.0' encoding='UTF-8'?><?compositeArtifactRepository version='1.0.0'?>
<repository name='${siteName}' type='${fileType}' version='1.0.0'>
<properties size='2'><property name='p2.timestamp' value='${now}'/><property name='p2.compressed' value='true'/></properties>
<children size='${countChildren}'>" > ${fileName}
  for ssd in $subsubdirs; do
    echo "<child location='${ssd}${childFolderSuffix}'/>" >> ${fileName}
  done
  echo "</children>
</repository>
" >> ${fileName}
}

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=`pwd`; fi
cd ${WORKSPACE}

# for a given list of JOBNAMES
for JN in ${JOBNAMES//,/ }; do
  getSubDirs /downloads_htdocs/tools/builds/staging/CI/${JN} 0
  subdirs=$getSubDirsReturn
  echo $subdirs
done
# search for subfolders, order them, and pull out the NUM newest ones (1 if stable site, or 2 if trunk site)
# then generate composite*.xml files using those (dirs x NUM) + the SITES + the NAME
# TODO pass in the right params here:
# regenProcess foo bar
