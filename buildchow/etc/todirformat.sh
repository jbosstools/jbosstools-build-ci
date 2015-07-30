#!/bin/bash

# this script will take a folder full of config files called ../configs/default/generated/jbosstools-base_4.3.mars
# and rename them into ../configs/default/generated-old/master/job/jbosstools-base_4.3.mars/config.xml

usage ()
{
    echo "Usage:     $0 /path/to/source/folder site_stream"
    echo "Example 1: $0 ../configs/default/generated 4.3.mars"
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi
SRCDIR=${1%/} # trim trailing slash if present
STREAM=${2}
FILES=${SRCDIR}/*_${STREAM}

DESTDIR=${SRCDIR}-old/${STREAM}/job
mkdir -p $DESTDIR

cnt=0
for f in $FILES; do
  # take action on each file. $f store current file name
  DEST=$DESTDIR/$(basename $f)
  if [[ -d $DEST ]]; then 
  	echo "[WARNING] Directory already exists: $DEST"
  else
	  # echo "[INFO] [$cnt] Processing $f ..."
  	mkdir -p $DEST
  	cp $f $DEST/config.xml
	  (( cnt++ ))
  fi
done

echo ""
echo "[INFO] $cnt config.xml files produced in $DESTDIR" 
