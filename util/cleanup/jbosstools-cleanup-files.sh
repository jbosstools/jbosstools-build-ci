root="vscode"
dry=0
modules=()

if [[ $# -lt 1 ]]; then
	echo "Usage: $0 [-r root] [-d] folder1 [folder2..foldern]"
	echo "        -r root: root folder under download.jboss.org/tools to start from (default vscode)"
	echo "        -d     : dry run mode (will only list files to be deleted (default false)"
	exit 1;
fi

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-r'|'--root') root="$2"; shift 1;;
		'-d'|'--dryrun') dry=1; shift 0;;
		*) modules+=("$1"); shift 0;;
	esac
	shift 1
done

getLatest() {
local latest=-1
local latestStr=""
local OLDIFS=$IFS
IFS='\n'
for i in `ls -1 $1`
do
    local modif=`stat -c %Y "$1/$i"`
    if ((modif > latest)); then
        latest=$modif
        latestStr=$1/$i
    fi
done
IFS=$OLDIFS
echo $latestStr
}

sshmount() {
mkdir -p ${WORKSPACE}/djo-ssh;
if [[ $(file ${WORKSPACE}/djo-ssh 2>&1) == *"Transport endpoint is not connected"* ]]; then fusermount -uz ${WORKSPACE}/djo-ssh; fi
if [[ ! -d ${WORKSPACE}/djo-ssh/images ]]; then  sshfs tools@10.5.105.197:/downloads_htdocs/tools ${WORKSPACE}/djo-ssh; fi
}

sshmount
shift
for i in "${modules[@]}"
do
    rc=$(getLatest "$WORKSPACE/djo-ssh/$root/stable/$i")
    if [[ $dry -eq 1 ]]; then
        find "$WORKSPACE/djo-ssh/$root/snapshots/$i" -maxdepth 1 ! -newer "$rc" -print
    else
        find "$WORKSPACE/djo-ssh/$root/snapshots/$i" -maxdepth 1 ! -newer "$rc" -print -delete
    fi
done
