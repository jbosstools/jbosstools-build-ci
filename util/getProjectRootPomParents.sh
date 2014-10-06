#!/bin/bash

# TODO parameterize this so parent and branch are cmdline options
# TODO check jbdevstudio-product too
parent=4.2.0.CR2-SNAPSHOT # or 4.3.0.Alpha1-SNAPSHOT
basedir=/home/nboldt/tru
logfile=/tmp/log.txt
errfile=/tmp/err.txt
branch=jbosstools-4.2.x # or master

echo "Found these root pom versions   [CORRECT]:" > ${logfile}; echo "" >> ${logfile}
echo "Found these root pom versions [INCORRECT]:" > ${errfile}; echo "" >> ${errfile}
for j in aerogear arquillian base birt browsersim central discovery forge freemarker hibernate javaee jst livereload openshift portlet server vpe webservices; do
  echo "== ${j} =="
  pushd ${basedir}/jbosstools-${j} >/dev/null
  git stash; 
  git checkout -- .; git reset HEAD .
  git checkout -- .; git reset HEAD .
  git checkout master; git pull --rebase origin master -p; git rebase --abort 
  git pull origin
  git checkout ${branch}; git pull origin ${branch}
  thisparent=`cat pom.xml | grep -A2 -B2 ">parent<"` # contains actual version
  isCorrectVersion=`cat pom.xml | grep -A2 -B2 ">parent<" | grep $parent` # empty string if wrong version
  if [[ ! $isCorrectVersion ]]; then
    echo -n "$j :: " >> $errfile
    echo $thisparent | grep version >> $errfile
  else
    echo $j :: $isCorrectVersion >> ${logfile}
  fi

  #if [[ $thisparent ]]
  popd >/dev/null
  echo ""
done

cat $logfile
echo ""
cat $errfile