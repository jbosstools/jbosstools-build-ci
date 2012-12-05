#!/bin/bash
old=$1
new=$2
if [[ $1 ]] && [[ $2 ]]; then
	for p in $(find.sh . pom\*.xml ${old} target "" -q); do sed -i -e "s#<version>${old}</version>#<version>${new}</version>#g" $p; done; 
else
	echo "Usage: $0 4.0.0.CR1-SNAPSHOT 4.0.0.Final-SNAPSHOT"; exit 1
fi

