#!/bin/bash
# Hudson script used to validate if the child links within a composite site exist as real sites, or return 404
# if all children exist, return 0 (success)
# if not, sleep for 5 mins and try again.
# if after 30 mins, return 1 (fail)

# For example, perform a 30 min check/wait/check loop when we're pushing bits to a new URL
# (eg., http://www.qa.jboss.com/binaries/RHDS/updates/development/7.1.0.CR1.core is a child link in http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/4.1.kepler/ ) 
# That way after jbosstools-discovery_41 job is done, it won't immediately trigger a failing run of jbosstools-install-grinder.install-tests.matrix_41 due to 404'd content
# So install grinder may take 30 mins longer to complete, but won't be red

usage ()
{
  echo "Usage  : $0 -sleep duration -maxsleeps num -url url_to_check"
  echo "Example  : $0 -sleep 5m -maxsleeps 6 -url http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/4.1.kepler/compositeContent.xml"
  exit 1

}

countItems () 
{
  list="$1"
  listItems="${list//,/ }"
  itemCount=0
  for c in ${listItems}; do 
    (( itemCount++ ))
  done
}

if [[ $# -lt 1 ]]; then usage; fi

sleep=5m
maxsleeps=6
# read commandline args
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-sleep') sleep="$2"; shift 1;; # duration of each sleep. see `man sleep` for syntax, eg., 5m = 5 minutes
    '-maxsleeps') maxsleeps="$2"; shift 1;; # number of sleeps before giving up, eg., 6 = 30 mins (if sleep = 5m)
    '-url') url="$2"; shift 1;; # URL to read, eg., http://www.qa.jboss.com/binaries/RHDS/discovery/nightly/core/4.1.kepler/compositeContent.xml
  esac
  shift 1
done

if [[ ! $url ]]; then usage; fi

echo "Checking every $sleep x $maxsleeps for valid children in:"
echo $url
echo

tmpdir=`mktemp -d`

wgetParams="--timeout=900 --wait=10 --random-wait --tries=10 --retry-connrefused --no-check-certificate"
wget ${wgetParams} ${url} -O ${tmpdir}/composite.xml -q
countsleeps=0
urls="`cat ${tmpdir}/composite.xml | grep http | sed -e "s/\([\t ]\+\)<child location='\|'\/>//g"`"
countItems "${urls}"
numUrls=$itemCount

while [[ true ]]; do
  echo "Check ${countsleeps} of ${maxsleeps}:"
  num=0
  numgood=0
  for url in $urls; do 
    ((num = num + 1 ))
    echo -n "[${num}/${numUrls}] $url/ ... "
    if [[ `wget ${wgetParams} ${url}/ -O ${tmpdir}/testfile 2>&1 | egrep "ERROR 404"` ]]; then #invalid URL, so sleep and loop
      if [[ ${countsleeps} -lt ${maxsleeps} ]]; then
        echo "not found. Sleeping for $sleep"
        sleep ${sleep}
        (( countsleeps = countsleeps + 1 ))
      else
        echo "not found. FAILURE."
        exit 1
      fi
      break
    else
      echo "found."
      (( numgood = numgood + 1 ))
    fi
    rm -fr ${tmpdir}/testfile
  done
  if [[ ${numgood} -eq ${numUrls} ]]; then
    break
  fi
done
rm -fr ${tmpdir}
