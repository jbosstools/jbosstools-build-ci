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
	echo "Usage	: $0 url_to_check [-fn (fail never - report ALL 404s instead of stopping after first)]"
	echo "Example	: $0 http://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/master/"
	echo "Example 2 : $0 http://download.jboss.org/jbosstools/builds/staging/_composite_/core/master/compositeContent.xml -fn"
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

debug=0
failnever=0
sleep=0m
maxsleeps=0
# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-X') debug=1; shift 0;;
		'-fn') failnever=1; shift 0;; # if 1 (true), process all 404s, rather than stopping on the first one
		'-sleep') sleep="$2"; shift 1;; # duration of each sleep. see `man sleep` for syntax, eg., 5m = 5 minutes
		'-maxsleeps') maxsleeps="$2"; shift 1;; # number of sleeps before giving up, eg., 6 = 30 mins (if sleep = 5m)
		'-url') checkurls="$2"; shift 1;; # URL to read, eg., http://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/master/
		*) checkurls="${checkurls} $1"; shift 0;; # URL to read, eg., http://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/master/
	esac
	shift 1
done

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=/tmp; fi

if [[ ! $checkurls ]]; then usage; fi

for checkurl in ${checkurls}; do
	if [[ ! $checkurl == *"/compositeContent.xml" ]]; then checkurl="${checkurl}/compositeContent.xml"; fi
	baseurl=${checkurl%/compositeContent.xml}

	if [[ $sleep != "0m" ]] || [[ $maxsleeps -gt 0 ]]; then
		echo "[INFO] Checking every $sleep x $maxsleeps for valid children in:"
	else
		echo "[INFO] Checking for valid children in:"
	fi
	echo "[INFO] $checkurl"
	echo

	tmpdir=${WORKSPACE}/${0##*/}_tmp; mkdir -p $tmpdir
	if [[ $debug -gt 0 ]]; then
		echo "[DEBUG] tmpdir: ${tmpdir}"
	fi

	curl -s ${checkurl} > ${tmpdir}/composite.xml
	if [[ ! -f ${tmpdir}/composite.xml ]] || [[ $(egrep "404 Not Found" ${tmpdir}/composite.xml) ]]; then
		echo "[ERROR] Could not read ${checkurl} ! "
		rm -fr ${tmpdir}
		exit 1
	fi
	if [[ $debug -gt 0 ]]; then
		echo "[DEBUG] ${tmpdir}/composite.xml"
		echo "[DEBUG] ------------"
		cat ${tmpdir}/composite.xml
		echo "[DEBUG] ------------"
	fi
	countsleeps=0
	cat ${tmpdir}/composite.xml | egrep "<child " | egrep -v "<\!--" | egrep "location" | sed -e "s#.*<child location=[\'\"]\+\([^\'\"]\+\)[\'\"]\+.*\/>#\1#" > ${tmpdir}/composite.txt
	urls=$(cat ${tmpdir}/composite.txt)
	if [[ $debug -gt 0 ]]; then
		echo "[DEBUG] Got urls:"
		echo "[DEBUG] ------------"
		cnt=0
		for url in $urls; do 
			(( cnt = cnt + 1 ))
			echo "[$cnt] $url"
		done
		echo "[DEBUG] ------------"
	fi

	countItems "${urls}"
	numUrls=$itemCount

	while [[ true ]]; do
		if [[ ${maxsleeps} -gt 0 ]]; then
			echo "[INFO] Check ${countsleeps} of ${maxsleeps}:"
		else
			countsleeps=1
		fi
		num=0
		numgood=0
		numbad=0
		numtotal=0
		for url in $urls; do 
			# normalize relative paths against baseurl
			if [[ ${url} != "http"* ]] || [[ ${url} == "../"* ]]; then
				url="${baseurl}/${url}"
			fi
			((num = num + 1 ))
			echo -n "[INFO] [${num}/${numUrls}] $url/ ... "
			stat=$(curl -I -s ${url} | egrep "404 Not Found")
			if [[ $stat ]]; then # 404
				if [[ ${countsleeps} -lt ${maxsleeps} ]]; then
					echo "not found. Sleeping for $sleep"
					sleep ${sleep}
					(( countsleeps = countsleeps + 1 ))
				else
					echo "failed: 404"
					if [[ ${failnever} -lt 1 ]]; then 
						exit 1
					else
	 					(( numbad = numbad + 1 ))
					fi
				fi
				if [[ ${failnever} -lt 1 ]]; then 
					break
				fi
			else
				echo "found."
				(( numgood = numgood + 1 ))
			fi
		done
		(( numtotal = numgood + numbad ))
		if [[ ${numtotal} -eq ${numUrls} ]]; then
			break
		fi
		if [[ ${countsleeps} -ge ${maxsleeps} ]]; then
			break
		fi
	done
	rm -fr ${tmpdir}
done
