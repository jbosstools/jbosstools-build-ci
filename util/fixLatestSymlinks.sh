#!/bin/bash


# can be used to check for invalid symlinks and composite sites
usage ()
{
	echo "Usage  : $0 -s source_path -t target_path -p prefix -x suffix -DESTINATION user@server:/path/to/files"
	echo ""
	echo "Example: $0 -s \${HOME}/TOOLS-ssh -t neon/snapshots/builds -p jbosstools -x master"
	echo "Example: $0 -s \${HOME}/JBDS-ssh -t 10.0/snapshots/builds -p devstudio -x master -DESTINATION devstudio@filemgmt.jboss.org:/www_htdocs/devstudio"
	echo "Example: $0 -s \${HOME}/JBDS-ssh -t 10.0/snapshots/builds -p jbosstools -x master -JBDS"

	exit 1
}

SOURCE_PATH=${HOME}/TOOLS-ssh
DESTINATION="tools@filemgmt.jboss.org:/downloads_htdocs/tools"
JBDS="devstudio@filemgmt.jboss.org:/www_htdocs/devstudio"
TARGET_PATH=neon/snapshots/builds # or 10.0/snapshots/builds
PREFIX="jbosstools-" # or devstudio
SUFFIX="master" # or 4.4.neon or 10.0.neon

if [[ $# -lt 1 ]]; then usage; fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-s') SOURCE_PATH="$2"; shift 1;; # ${HOME}/TOOLS-ssh (or where you have tools@filemgmt.jboss.org:/downloads_htdocs/tools sshfs-mounted)
		'-t') TARGET_PATH="$2"; shift 1;; # neon/snapshots/builds or 10.0/snapshots/builds
		'-DESTINATION') DESTINATION="$2"; shift 1;; # tools@filemgmt.jboss.org:/downloads_htdocs/tools or devstudio@filemgmt.jboss.org:/www_htdocs/devstudio
		'-JBDS') DESTINATION="${JBDS}"; shift 0;; 
		'-p') PREFIX="$2"; shift 1;; # jbosstools- or devstudio
		'-x') SUFFIX="$2"; shift 1;; # _master or 4.4.neon or 10.0.neon
		*) OTHER="${OTHER} $1"; shift 0;; 
	esac
	shift 1
done

SCPR="rsync -Pzrlt --rsh=ssh --protocol=28 -q"
#set up tmpdir
tmpdir=`mktemp -d`
mkdir -p $tmpdir

pushd ${SOURCE_PATH} >/dev/null
	dirs=$(find ${TARGET_PATH}/ -maxdepth 1 -type d -name "${PREFIX}*_${SUFFIX}" | sort)
	for d in ${dirs}; do
		echo -n "Check ${d}/latest: "
		if [[ -d ${d}/latest ]]; then 
			echo "OK!"
		else 
			echo -n "symlink to non-existent folder - must remove! "
			rm -f ${d}/latest 
			latest=$(ls ${d} -t -c -p --group-directories-first | head -1)
			echo -n "New link to ${latest}... "
			pushd ${d} >/dev/null
				ln -s ${latest} latest
			popd >/dev/null
			echo "Success!"
		fi

		for comp in compositeArtifacts.xml compositeContent.xml; do
			echo -n "Check ${d}/${comp}: "
			for child in $(cat ${d}/${comp} | grep "child location" | sed "s#<child location='\(.\+\)'/>#\1#"); do
				if [[ ! -d ${d}/${child} ]]; then 
					echo -n "remove ${child} ... "
					sed "s#<child location='\(.\+\)'/>##" ${d}/${comp} > ${tmpdir}/${comp}.out
					${SCPR} ${tmpdir}/${comp}.out ${DESTINATION}/${d}/${comp}
					rm -f ${tmpdir}/${comp}.out
				fi
			done
			echo "OK!"
		done
		echo ""
	done
popd >/dev/null

# purge temp folder
rm -fr ${tmpdir} 
