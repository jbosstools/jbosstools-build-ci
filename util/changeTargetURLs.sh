#!/bin/bash

# 0. run in ~/tru/jbosstools-target-platforms

# 1. fetch and parse http://jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/DevStudio_Master/job/jbosstoolstargetplatformrequirements-mirror-matrix/38/api/xml?xpath=//description
tmpfile=/tmp/jbosstoolstargetplatformrequirements-mirror-matrix-descriptions.txt
descriptionURL=http://jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/DevStudio_Master/job/jbosstoolstargetplatformrequirements-mirror-matrix/38/api/xml?xpath=//description
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
  ${0/changeTargetURLs.sh/verifyTarget.sh} -x -b `pwd` -p $d &
done
wait

# 4. generate p2diffs
TPVERSION=4.60.0.Final-SNAPSHOT
P2DIFF=/home/nboldt/bin/p2diff
for d in jbosstools jbdevstudio; do
  prefix=http://download.jboss.org/jbosstools; if [[ $d == "jbdevstudio" ]]; then prefix="https://devstudio.jboss.com"; fi
  p2diffcmd="${P2DIFF} ${prefix}/targetplatforms/${d}target/${TPVERSION}/REPO/ file://"$(pwd)"/${d}/multiple/target/${d}-multiple.target.repo/"
  ${p2diffcmd} | tee /tmp/p2diff_${d}_${TPVERSION}_latest.txt
  if [[ ${0/changeTargetURLs.sh/} != $0 ]]; then P2DIFFCHECK=${0/changeTargetURLs.sh/p2diff-check.sh}; else P2DIFFCHECK=~/tru/buildci/util/p2diff-check.sh; fi
  ${P2DIFFCHECK} /tmp/p2diff_${d}_${TPVERSION}_latest.txt | tee /tmp/p2diff_${d}_${TPVERSION}_summary_latest.txt
done

echo ""
for d in jbosstools jbdevstudio; do
  echo "p2diff files: /tmp/p2diff_${d}_${TPVERSION}_latest.txt"
  echo "p2diff files: /tmp/p2diff_${d}_${TPVERSION}_summary_latest.txt"
done
echo ""

# 5. cleanup
rm -f ${tmpfile}

