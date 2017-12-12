#!/bin/bash

declare -a theArrays 
declare -a mars
declare -a neon
declare -a oxygen

mars=( 4.3.0.Final 4.3.1.Final )
neon=( 4.4.0.Final 4.4.1.Final 4.4.2.Final 4.4.3.Final 4.4.4.Final )
oxygen=( 4.5.0.Final 4.5.1.Final )

getMaps () {
	eclipseName=$1
	theArray="$2"
	echo ""; 
	#echo $theArray
	for version in $theArray; do
		wget -q http://download.jboss.org/jbosstools/static/${eclipseName}/stable/updates/core/${version}/plugins/ -O - | \
		grep href | grep -v pack.gz | egrep "org.jboss.tools.usage_.*jar" | sed -e "s#.\+<a href=\"\([^\"]\+\)\".\+#${version} :: \1#"
	done

}

getMaps mars "${mars[*]}"
getMaps neon "${neon[*]}"
getMaps oxygen "${oxygen[*]}"
