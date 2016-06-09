#!/bin/bash

# 0. run in ~/tru/jbosstools-target-platforms or jenkins workspace with jbosstools-target-platforms checked out to $WORKSPACE

usage ()
{
  echo "Usage  : $0 -tp TARGET_PLATFORM_VERSION_MAXIMUM [-p2diff /path/to/p2diff] [-b whichBuild]"
  echo ""
  echo "Example: $0 -tp 4.60.0.Final-SNAPSHOT -p2diff /home/nboldt/bin/p2diff -m /opt/apache-maven-3.2.5/bin/mvn -b lastSuccessfulBuild "
  echo "Example: $0 -tp 4.60.0.Final -b 47"
  echo ""
  exit 1
}

if [[ $# -lt 1 ]]; then usage; fi

p2diff=/home/hudson/static_build_env/jbds/p2diff/x86$(if [[ $(uname -a | grep x86_64) ]]; then echo _64; fi)/p2diff
whichBuild=lastSuccessfulBuild
M2_HOME=/qa/tools/opt/apache-maven-3.2.5/
MVN=${M2_HOME}/bin/mvn

# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-tp') TARGET_PLATFORM_VERSION_MAXIMUM="$2"; shift 1;; 
	'-p2diff') p2diff="$2"; shift 1;; # /path/to/p2diff executable
	'-b') whichBuild="$2"; shift 1;; # could be lastBuild, lastCompletedBuild, lastSuccessfulBuild, or a build by number, eg., 38
	'-WORKSPACE') WORKSPACE="$2"; shift 1;;
	'-mh') M2_HOME="$2"; shift 1;;
	'-m') MVN="$2"; shift 1;;
    *) OTHER="${OTHER} $1"; shift 0;;
  esac
  shift 1
done

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=/tmp; fi
if [[ ! -x $p2diff ]]; then echo "Error: cannot run p2diff from $p2diff"; echo ""; usage; fi

# 1. fetch and parse http://jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/DevStudio_Master/job/jbosstoolstargetplatformrequirements-mirror-matrix/${whichBuild}/api/xml?xpath=//description
tmpfile=${WORKSPACE}/jbosstoolstargetplatformrequirements-mirror-matrix-descriptions.txt
descriptionURL=http://jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/DevStudio_Master/job/jbosstoolstargetplatformrequirements-mirror-matrix/${whichBuild}/api/xml?xpath=//description
curl -s ${descriptionURL} > ${tmpfile}
if [[ ! $(cat ${tmpfile} | grep "http://download.jboss.org/jbosstools/updates/requirements/") ]]; then
	echo "Error: could not parse description from ${descriptionURL}"
	exit 1
fi

URLs=$(cat ${tmpfile} | tr " " "\n" | grep href | sed "s%href=\"\(.\+\)\#.\+\".\+%\1%")

# 2. for all *.target files, find and replace similar URLs
for u in ${URLs}; do
	REQ_NAME=${u##http://download.jboss.org/jbosstools/updates/requirements/}; REQ_NAME=${REQ_NAME%%/*}; # echo $REQ_NAME
	for t in $(find . -name "*.target" | grep -v "/target/"); do
		echo "[INFO] Processing $t (${REQ_NAME}) ..."
		sed -i "s#<repository location=\"http://download.jboss.org/jbosstools/updates/requirements/${REQ_NAME}/.\+\"/>#<repository location=\"${u}\"/>#" $t
	done
done

# 3. run verifyTarget.sh from same util/ folder 
for d in jbosstools jbdevstudio; do
  ${0/changeTargetURLs.sh/verifyTarget.sh} -x -b `pwd` -p $d -m ${MVN} -mrl ${WORKSPACE}/.repository &
done
wait

# 4. generate p2diffs
for d in jbosstools jbdevstudio; do
  prefix=http://download.jboss.org/jbosstools; if [[ $d == "jbdevstudio" ]]; then prefix="https://devstudio.jboss.com"; fi
  p2diffcmd="${p2diff} ${prefix}/targetplatforms/${d}target/${TARGET_PLATFORM_VERSION_MAXIMUM}/REPO/ file://"$(pwd)"/${d}/multiple/target/${d}-multiple.target.repo/"
  ${p2diffcmd} | tee ${WORKSPACE}/p2diff_${d}_${TARGET_PLATFORM_VERSION_MAXIMUM}_latest.txt
  if [[ ${0/changeTargetURLs.sh/} != $0 ]]; then p2diffcheck=${0/changeTargetURLs.sh/p2diff-check.sh}; else p2diffcheck=~/tru/buildci/util/p2diff-check.sh; fi
  ${p2diffcheck} ${WORKSPACE}/p2diff_${d}_${TARGET_PLATFORM_VERSION_MAXIMUM}_latest.txt | tee ${WORKSPACE}/p2diff_${d}_${TARGET_PLATFORM_VERSION_MAXIMUM}_summary_latest.txt
done

echo ""
for d in jbosstools jbdevstudio; do
  echo "p2diff files: ${WORKSPACE}/p2diff_${d}_${TARGET_PLATFORM_VERSION_MAXIMUM}_latest.txt"
  echo "p2diff files: ${WORKSPACE}/p2diff_${d}_${TARGET_PLATFORM_VERSION_MAXIMUM}_summary_latest.txt"
done
echo ""

# 5. generate git diff
git diff --color=never > ${WORKSPACE}/git.diff.txt

# 6. cleanup
rm -f ${tmpfile}

# 7. now archive the artifacts or apply the git diff / review the p2diffs