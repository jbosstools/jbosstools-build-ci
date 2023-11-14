#!/bin/sh
# This script is run here: http://hudson.qa.jboss.com/hudson/job/jbosstools-cleanup/configure
# And archived here: http://anonsvn.jboss.org/repos/jbosstools/trunk/build/util/cleanup/jbosstools-cleanup.sh
# --------------------------------------------------------------------------------
# clean JBT/JBDS snapshot builds from sftp://tools@filemgmt.jboss.org:/downloads_htdocs/tools/ or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio/

#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

log=${tmpdir}/${0##*/}.log.`date +%Y%m%d-%H%M`.txt

echo "Logfile: $log" | tee -a $log
echo "" | tee -a $log

# commandline options so we can call it from jbosstools-cleanup Jenkins job using 
#	`jbosstools-cleanup.sh -k 1 -a 2 -S /all/repo/` 
# or call it from within publish.sh using
# 	`jbosstools-cleanup.sh -k 5 -a 5 -S /all/repo/`
# or call it from within promote.sh using
# 	`jbosstools-cleanup.sh --dirs-to-scan "updates/${BUILD_TYPE}/${TARGET_PLATFORM}/${PARENT_FOLDER}" --regen-metadata-only`

#defaults
debug=0
numbuildstokeep=1000 # keep X builds per branch
numbuildstolink=1000 # link X builds total
threshholdwhendelete=365 # purge builds more than X days old
# for JBDS, use --dirs-to-scan "10.0/snapshots/builds 9.0/snapshots/builds" -DESTINATION devstudio@filemgmt.jboss.org:/www_htdocs/devstudio
dirsToScan="oxygen/snapshots/builds neon/snapshots/builds"
excludes="sftp>|((\.properties|\.jar|\.zip|\.MD5|\.md5|\.sha256|p2.index)$)|(^(*.*ml|\.blobstore|web|plugins|features|binary|empty_composite_site|latest|logs)$)" # when dir matching, exclude *.*ml, *.properties, *.jar, *.zip, *.MD5, *.md5, web/features/plugins/binary/.blobstore
includes=""; # regex pattern to match within subdirs to make cleanup faster + more restrictive; eg., jbosstools-build-sites.aggregate.earlyaccess-site_master
delete=1 # if 1, files will be deleted. if 0, files will be listed for delete but not actually removed
checkTimeStamps=1 # if 1, check for timestamped folders, eg., 2012-09-30_04-01-36-H5622 and deduce the age from name. if 0, skip name-to-age parsing and delete nothing
childFolderSuffix="/" # for component update sites, set to "/"; for aggregate builds (not update sites) use "/all/repo/"
regenMetadataOnly=0 # set to 1 if only regenerating metadata, not cleaning up old build folders
doRegenMetadata=1; # set to 0 to suppress regenerating metadata entirely (no composite site will be produced)
noSubDirs=0 # normally, we want to scan for subdirs, but for a project like Locus, there's one less level of nesting so we need to override this with noSubDirs=1
DESTINATION=tools@filemgmt.jboss.org:/downloads_htdocs/tools # or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio

if [[ $# -lt 1 ]]; then
	echo "Usage: $0 [-k num-builds-to-keep] [-a num-days-at-which-to-delete] [-d dirs-to-scan] [-i subdir-include-pattern] [--regen-metadata-only] [--childFolderSuffix /all/repo/]"
	echo "Example (Jenkins):    $0 --keep 1 --age-to-delete 2 --childFolderSuffix /all/repo/"
	echo "Example (publish.sh): $0 -k 5 -a 5 -S /all/repo/"
	echo "Example (promote.sh): $0 --regen-metadata-only --dirs-to-scan 'updates/integration/indigo/soa-tooling/'"
	echo "Example (promote.sh): $0 --regen-metadata-only --no-subdirs --dirs-to-scan 'updates/integration//locus'"
	echo "Example (rsync.sh):   $0 -k 2 -a 2 -l 5 -S /all/repo/ -d neon/snapshots/builds --include jbosstools-build-sites.aggregate"
	echo "Example (regen meta): $0 --regen-metadata-only --no-subdirs --link 1 -d oxygen/development/updates/rhamt --exclude composite"
	exit 1;
fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-k'|'--keep') numbuildstokeep="$2"; shift 1;;
		'-l'|'--link') numbuildstolink="$2"; shift 1;;
		'-a'|'--age-to-delete') threshholdwhendelete="$2"; shift 1;;
		'-d'|'--dirs-to-scan') dirsToScan="$2"; shift 1;;
		'-i'|'--include') includes="$2"; shift 1;;
		'-e'|'--exclude') excludes="${excludes}|$2"; shift 1;;
		'-S'|'--childFolderSuffix') childFolderSuffix="$2"; shift 1;;
		'-M'|'--regen-metadata-only') delete=0; checkTimeStamps=0; doRegenMetadata=1; regenMetadataOnly=1; shift 0;;
		'-R'|'--no-regen-metadata') doRegenMetadata=0; regenMetadataOnly=0; shift 0;;
		'-N'|'--no-subdirs') noSubDirs=1; shift 0;;
		'-DESTINATION') DESTINATION="$2"; shift 1;; # override for JBDS publishing, eg., devstudio@filemgmt.jboss.org:/www_htdocs/devstudio
		'-X') debug=1; shift 0;;
	esac
	shift 1
done

# split DESTINATION by colon, eg., tools@filemgmt.jboss.org:/downloads_htdocs/tools
DEST_SERV=${DESTINATION%%:*}; # tools@filemgmt.jboss.org
DEST_PATH=${DESTINATION##*:}; # /downloads_htdocs/tools

recursive_del ()
{
	local sd=$1
	local dd=$2
	local subdir=''
	tmp=`mktemp`
	echo -e "ls -1l $dd/" | sftp -q $DEST_SERV:$sd/ > $tmp
	while IFS= read -r line; do
		if egrep -q '^d' <<< $line; then
		subdir=$(echo "$line" | awk '{ print $NF }')
		recursive_del $sd "$dd/$subdir"
		echo -e "rm $dd/$subdir/*" | sftp -q $DEST_SERV:$sd/
		echo -e "rmdir $dd/$subdir" | sftp -q $DEST_SERV:$sd/
		fi
	done < $tmp
	rm -f $tmp
}

getSubDirs () 
{
	getSubDirsReturn=""
	tab=""
	includePattern=""
	if [[ $1 ]]; then dir="$1"; else echo "No directory passed to getSubDirs()!"; fi
	if [[ $dir ]]; then 
		if [[ $2 ]] && [[ $2 -gt 0 ]]; then
			lev=$2
			while [[ $lev -gt 0 ]]; do
				tab=$tab"> ";
				(( lev-- ));
			done
		fi
		if [[ $3 ]]; then 
			includePattern="$3"
			echo "${tab}Check $dir for dirs matching /${includePattern}/ ..." | tee -a $log
		else
			echo "${tab}Check $dir..." | tee -a $log
		fi
		tmp=`mktemp`
		echo "ls $dir" > $tmp
		dirs=$(sftp -b $tmp $DEST_SERV 2>/dev/null)
		i=0
		for c in $dirs; do #exclude *.*ml, *.properties, *.jar, *.zip, *.MD5, *.md5, web/features/plugins/binary/.blobstore
			# old way... if [[ $i -gt 2 ]] && [[ $c != "sftp>" ]] && [[ ${c##*.} != "" ]] && [[ ${c##*/*.*ml} != "" ]] && [[ ${c##*/*.properties} != "" ]] && [[ ${c##*/*.jar} != "" ]] && [[ ${c##*/*.zip} != "" ]] && [[ ${c##*/*.MD5} != "" ]] && [[ ${c##*/*.md5} != "" ]] && [[ ${c##*/web} != "" ]] && [[ ${c##*/plugins} != "" ]] && [[ ${c##*/features} != "" ]] && [[ ${c##*/binary} != "" ]] && [[ ${c##*/.blobstore} != "" ]]; then
			if [[ $debug -gt 0 ]]; then echo -n "$c ..."; fi
			if [[ $i -gt 2 ]] && [[ ${c##*.} != "" ]] && [[ ! $(echo "$c" | egrep "${excludes}") ]]; then
				# if no include pattern set, or pattern matches, include this folder.
				if [[ $debug -gt 0 ]]; then echo -n "not excluded ..."; fi
				if [[ ! $includePattern ]] || [[ $(echo "$c" | egrep "$includePattern")	]]; then 
					if [[ $debug -gt 0 ]]; then echo -n "is included ..."; fi
					getSubDirsReturn=$getSubDirsReturn" "$c
				fi
			fi
			(( i++ ))
			if [[ $debug -gt 0 ]]; then echo ""; fi
		done
		rm -f $tmp
	fi
}

# Check for $somepath builds more than $threshholdwhendelete days old; keep minimum $numbuildstokeep builds per branch
clean () 
{
	somepath=$1 # builds/nightly or updates/development/juno/soa-tooling, etc.
	numbuildstokeep=$2 # number of builds to keep per branch
	threshholdwhendelete=$3 # purge builds more than $threshholdwhendelete days old
	numbuildstolink=$4 # number of TOTAL builds to keep
	somepath=${somepath//\/\//\/}; # remove duplicate slashes in paths - replace all // with / 
	somepath=${somepath//\/\//\/}; # repeat to replace /// with /
	echo "Check for $somepath builds more than ${threshholdwhendelete} days old; keep minimum ${numbuildstokeep} builds per branch (linked in composite: ${numbuildstolink})" | tee -a $log 

	getSubDirs ${DEST_PATH}/$somepath/ 0 $includes
	subdirs=$getSubDirsReturn

	# special case for Locus builds - only work in subfolders (3 levels: /updates/integration/locus/x.y.z/, not sub-subfolders (5 levels: /updates/integration/kepler/core/project/x.y.z/)
	if [[ ${regenMetadataOnly} -eq 1 ]] && [[ ${noSubDirs} -eq 1 ]]; then 
		tmp=`mktemp`
		subdirCount=0;
		for sd in $subdirs; do
			buildid=${sd##*/};
			let subdirCount=subdirCount+1;
			# echo "[${subdirCount}] Found $buildid"
			echo $buildid >> $tmp
		done
		regenProcess ${subdirCount} ${DEST_PATH}/$somepath/ ${numbuildstolink}
	else # for everyone else, work in sub-subfolders
		for sd in $subdirs; do
			getSubDirs $sd 1
			subsubdirs=$getSubDirsReturn
			#echo $subsubdirs
			tmp=`mktemp`
			for ssd in $subsubdirs; do
				if [[ ${ssd##$sd/20*} == "" ]] || [[ $checkTimeStamps -eq 0 ]]; then # a build dir
					buildid=${ssd##*/}; 
					echo $buildid >> $tmp
				fi
			done
			if [[ $checkTimeStamps -eq 1 ]]; then
				newest=$(cat $tmp | sort -r | head -$numbuildstokeep) # keep these
				all=$(cat $tmp | sort -r) # check these
				rm -f $tmp
				for dd in $all; do
					keep=0
					age=0
					if [[ -d $dd ]]; then
						# NEW WAY: JBIDE-22757 instead of the $dd path defining its create date / age, use the last modification time of the $dd folder (date -r)
						sec=$(date -u +%s -r $dd)
					else
						# OLD WAY: convert buildID (folder) - ${BUILD_TIMESTAMP}-B${BUILD_NUMBER} - to timestamp, then to # seconds since 2009-01-01 00:00:00 (1230786000)
						sec=$(date -u +%s -d "$(echo $dd | perl -pe "s/(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})-(H|B)(\d+)(_PR\d+)?/\1-\2-\3 \4:\5:\6Z/")")
					fi
					now=$(date -u +%s)
					(( age = now - sec ))
					(( day = age / 3600 / 24 ))
					for n in $newest; do
						if [[ $dd == $n ]] || [[ $day -le $threshholdwhendelete ]]; then
							keep=1
						fi
					done
					if [[ $keep -eq 0 ]]; then
						echo -n "- $sd/$dd (${day}d)... " | tee -a $log
						if [[ $delete -eq 1 ]]; then
							if [[ $USER == "hudson" ]]; then
								# can't delete the dir, but can at least purge its contents
								rm -fr ${tmpdir}/$dd; mkdir ${tmpdir}/$dd; pushd ${tmpdir}/$dd >/dev/null
								# delete all inner direcories
								echo "" | tee -a $log
								recursive_del "$sd" "$dd"
								echo -e "rm $dd/*" | sftp -q $DEST_SERV:$sd/ 
								echo -e "rmdir $dd" | sftp -q $DEST_SERV:$sd/
								popd >/dev/null; rm -fr ${tmpdir}/$dd
							else
								echo "" | tee -a $log
							fi
						else
							echo " SKIPPED."
						fi
					else
						echo "+ $sd/$dd (${day}d)" | tee -a $log
					fi
				done
			fi

			# generate metadata in the nightly/core/trunk/ folder to composite the remaining sites into one
			tmp=`mktemp`
			subdirCount=0;
			for ssd in $subsubdirs; do
				#echo "ssd = $ssd, sd = $sd"
				if [[ $(echo $ssd | sed "s#^$sd/[0-9]\+-B[0-9]\+##") == "" ]] || [[ ${ssd##$sd/20*} == "" ]] || [[ $checkTimeStamps -eq 0 ]]; then # a build dir
					# make sure all dirs contain content; if not, remove them
					thisDirsContents="something"
					thisDirsContents=$(echo "ls" | sftp $DEST_SERV:$sd/${ssd} 2>&1 | egrep -v "sftp|Connected to|Changing to") # will be "" if nothing found
					if [[ $thisDirsContents == "" ]]; then
						echo -n "- $sd/$ssd (empty dir)... " | tee -a $log
						# remove the empty dir from the list we'll composite together, delete it from the server, and don't count it in the subdirCount
						rm -fr $tmp/$ssd
						echo -e "rmdir $ssd" | sftp $DEST_SERV:$sd/
					else
						# check that $DEST_SERV:$sd/${ssd}/${childFolderSuffix} exists, or else 'File "..." not found'
						thisDirsContents=$(echo "ls" | sftp $DEST_SERV:$sd/${ssd}/${childFolderSuffix} 2>&1 | egrep -v "sftp|Connected to|Changing to") # will be "" if nothing found
						if [[ ${thisDirsContents/File \"*\" not found./NO} == "NO" ]]; then 
							echo $thisDirsContents
							# remove the empty dir from the list we'll composite together, and don't count it in the subdirCount
							rm -fr $tmp/$ssd
						else
							buildid=${ssd##*/};
							let subdirCount=subdirCount+1;
							# echo "[${subdirCount}] Found $buildid"
							echo $buildid >> $tmp
						fi
					fi
				fi
			done
			regenProcess ${subdirCount} ${sd} ${numbuildstolink}
		done
	fi
	echo "" | tee -a $log
}

regenProcess ()
{
	if [[ $doRegenMetadata -gt 0 ]]; then
		subdirCount=$1
		sd=$2
		numbuildstolink=$3
		all=$(cat $tmp | sort -Vr | head -$numbuildstolink) # link only the latest $numbuildstolink builds using natural sort of (version) numbers within text 
		rm -f $tmp
		if [[ $subdirCount -gt 0 ]]; then
			siteName=${sd##*${DEST_PATH}/}
			# JBIDE-25045 check if the destination folder is a symlink - we don't need (or want) to regen a symlink folder
			# $➔ echo "ls -l" | sftp -q ${TOOLS}/neon/stable/updates/windup | egrep "^l"
			#    lrwxrwxrwx    1 tools    tools           6 May 19 15:21 windup
			echo "> Check if $sd is symlink..." | tee -a $log
			if [[ $debug -gt 0 ]]; then
				rsync --protocol=28 --rsh=ssh -e 'ssh -p 2222' tools@filemgmt-prod-sync.jboss.org:/downloads_htdocs/tools:$sd | egrep "^l"
				echo "ls -l" | sftp -q ${DEST_SERV}:$sd/ | tee -a $log
				echo "ls -l $sd" | sftp -q ${DEST_SERV} | tee -a $log
				echo "ls -l" | sftp -q ${DEST_SERV}:$sd/ | egrep "^l" | tee -a $log
			fi
			isSymlink=$(echo "ls -l" | sftp -q ${DEST_SERV}:$sd/ | egrep "^l")
			if [[ ! ${isSymlink} ]]; then
				echo "+ Generate metadata for first ${numbuildstolink} of ${subdirCount} subdir(s) in $sd" | tee -a $log
				mkdir -p ${tmpdir}/cleanup-fresh-metadata/
				regenCompositeMetadata "$siteName" "$all" "$numbuildstolink" "org.eclipse.equinox.internal.p2.metadata.repository.CompositeMetadataRepository" "${tmpdir}/cleanup-fresh-metadata/compositeContent.xml"
				regenCompositeMetadata "$siteName" "$all" "$numbuildstolink" "org.eclipse.equinox.internal.p2.artifact.repository.CompositeArtifactRepository" "${tmpdir}/cleanup-fresh-metadata/compositeArtifacts.xml"
				echo -e "put ${tmpdir}/cleanup-fresh-metadata/composite*.xml" | sftp -Cpq ${DEST_SERV}:$sd/
				rm -fr ${tmpdir}/cleanup-fresh-metadata/
			else
				echo "- Skip symlinked folder $sd" | tee -a $log
			fi
		else
			echo "No subdirs found in $sd/" | tee -a $log
			# TODO delete composite*.xml from $sd/ folder if there are no subdirs present
		fi
	else
		echo "Metadata generation skipped by --no-regen-metadata flag."
	fi
}

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

# now that we have all the methods and vars defined, let's do some cleaning!
for path in $dirsToScan; do
	clean $path $numbuildstokeep $threshholdwhendelete $numbuildstolink
done

# purge temp folder
rm -fr ${tmpdir}
