#!/bin/bash

if [[ $1 ]]; then stream="$1"; else stream="master"; fi

if [[ $2 ]]; then WORKSPACE="$2"; else WORKSPACE="$(pwd)"; fi

if [[ $3 ]]; then path="$3"; else path="neon/snapshots/builds"; fi

TOOLS="tools@filemgmt.jboss.org:/downloads_htdocs/tools"

pushd ${WORKSPACE} >/dev/null
echo "Check contents of ${WORKSPACE}/$path against contents of $TOOLS"; 
for d in aerogear arquillian birt browsersim base central forge freemarker hibernate javaee jst livereload portlet openshift server vpe webservices; do
	mkdir -p jbosstools-${d}_${stream}
done
for d in `find jbosstools-*_${stream} -mindepth 1 -maxdepth 1 -type f -name "composite*.xml"`; do 
	if [[ $(cat $d | grep "size='0'") ]]; then # this is a placeholder / empty composite
		echo -n "Get $d from $TOOLS ..."; 
		$(rsync -Pzrlt --rsh=ssh --protocol=28 -q $TOOLS/$path/$d $d); # replace them with remote contents
		echo 
	fi
done
popd >/dev/null