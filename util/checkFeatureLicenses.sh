#!/bin/bash

excludepattern="\.git|/target|target/|foundation.license.feature|org.jboss.tools.xulrunner.feature|requirements/swt"

# count features
numfeatures=$(find . -name feature.xml | egrep -v "${excludepattern}" | wc -l)
numfiles=$(find . -name feature.\* | egrep -v "${excludepattern}" | wc -l)
echo "Number of features: ${numfeatures} (files: ${numfiles})"

GRN="\033[1;32m"
RED="\033[1;31m"
BLU="\033[1;34m"
NRM="\033[0;39m"

check () 
{
	pattern="$1"
	files="$2"
	expected="$3"

	echo -n "${pattern}: "
	col=$GRN
	check="$(find.sh . "${files}" "${pattern}" "${excludepattern}" "" -q)"
	cnt=0; for d in $check; do if [[ $d != "st" ]]; then (( cnt++ )); fi; done
	if [[ $expected != $cnt ]]; then 
		listFiles=1
		if [[ $4 ]]; then col="$4"; else col=$RED; fi
	fi
	echo -e "${col}${cnt}${NRM} of $expected"
}

check "providerName|featureProvider" "feature.*" $numfiles
check "licenseURL" "feature.*" $numfiles
check "license-feature" "feature.xml" $numfeatures
check "license=" "feature.properties" 0
check "pdateSite" "feature.*" 0 $BLU
check "Legal Affairs" "*" 0 $BLU

if [[ $listFiles ]]; then find.sh . "feature.*" "=" "" "" -q; fi