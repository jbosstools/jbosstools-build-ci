#!/bin/bash

tmpdir=/tmp/p2diff-check; mkdir -p $tmpdir
# first, create a p2diff report, eg.,
# ./p2diff \
# http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/4.51.0.Final/REPO/ \
# file:/home/mistria/git/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/ \
# > $tmpdir/p2diff.txt
inputfile=$tmpdir/p2diff.txt
if [[ $1 ]]; then inputfile="$1"; fi

if [[ ! -f $inputfile ]]; then 
	echo "No such file $inputfile. Please create a p2diff report file, eg., "
	echo ""
	echo "/path/to/p2diff \\
  http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/4.51.0.Final/REPO/ \\
  file://${HOME}/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/ \\
  > $tmpdir/p2diff.txt"
	exit 1
fi
	
# file looks like this
# < org.eclipse.e4.rcp.feature.group [1.4.0.v20150903-1804] 
# < org.eclipse.emf.mapping.feature.jar [2.9.0.v20150806-0404] 
# ...
# > org.eclipse.sapphire.platform.feature.group [9.0.0.201506110922] 
# > org.eclipse.wst.common_ui.feature.feature.jar [3.7.0.v201505132009] 
# === Summary ===
# http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/4.51.0.Final/REPO/ contains 342 unique IUs
# file:/home/mistria/git/jbosstools-target-platforms/jbosstools/multiple/target/jbosstools-multiple.target.repo/ contains 349 unique IUs

# filter out anything but the diff lines (no need for summary)
cat $inputfile | egrep "<|>" > $tmpdir/p2diff.all.txt
cat $inputfile | egrep -v "<|>" > $tmpdir/p2diff.summary.txt
# split the file into two files, removing the versions and the < or >
cat $tmpdir/p2diff.all.txt | sed "s#<.\+##" | sed "s#> ##" | sed "s#\[.\+\]##" | sed '/^$/d' | sort -r > $tmpdir/p2diff.before.txt
cat $tmpdir/p2diff.all.txt | sed "s#>.\+##"| sed "s#< ##" | sed "s#\[.\+\]##" | sed '/^$/d' | sort -r > $tmpdir/p2diff.after.txt

# show the summary again
cat $tmpdir/p2diff.summary.txt

# show what has been added/removed
diff -u $tmpdir/p2diff.before.txt $tmpdir/p2diff.after.txt | egrep -v "p2diff.before.txt|p2diff.after.txt" | egrep "^\+|^-"
# -org.eclipse.jetty.util  
# -org.eclipse.jetty.servlet  
# -org.eclipse.jetty.server  
# -org.eclipse.jetty.security  
# -org.eclipse.jetty.io  
# -org.eclipse.jetty.http  
# -org.eclipse.jetty.continuation  

# show versions of what has been added/removed
diff $tmpdir/p2diff.before.txt $tmpdir/p2diff.after.txt | egrep "^<|^>" > $tmpdir/p2diff.delta.txt
for d in $(cat /tmp/p2diff-check/p2diff.delta.txt); do 
	if [[ ${d:1} ]]; then # echo $d
		grep $d /tmp/p2diff-check/p2diff.all.txt
	fi
done
# > org.eclipse.jetty.util [9.3.2.v20150730] 
# > org.eclipse.jetty.servlet [9.3.2.v20150730] 
# > org.eclipse.jetty.server [9.3.2.v20150730] 
# > org.eclipse.jetty.security [9.3.2.v20150730] 
# > org.eclipse.jetty.io [9.3.2.v20150730] 
# > org.eclipse.jetty.http [9.3.2.v20150730] 
# > org.eclipse.jetty.continuation [9.3.2.v20150730] 

# cleanup
rm -fr $tmpdir
