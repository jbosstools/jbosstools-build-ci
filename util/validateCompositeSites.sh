#!/bin/bash
# recursively validate if child links within a composite site exist as real sites, or return 404

usage ()
{
	echo "Usage	: $0 url_to_check1 url_to_check2"
	echo "Example (good URLs): $0 \\"
	echo "  http://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/master \\"
	echo "  http://download.jboss.org/jbosstools/oxygen/stable/updates/ \\"
	echo "  http://download.jboss.org/jbosstools/targetplatforms/jbosstoolstarget/4.71.0.Final/REPO"
	echo "Example (obsolete URL): $0 \\"
	echo "  http://download.jboss.org/jbosstools/builds/staging/_composite_/core/master"
	echo "Example (bad URLs): $0 \\"
	echo "  http://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/4.5.oxygen \\"
	echo "  http://download.jboss.org/jbosstools/oxygen/development/updates/integration-stack/discovery/earlyaccess/"
	exit 1

}

if [[ $# -lt 1 ]]; then usage; fi

quiet=0
debug=0
# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
	    '-q') quiet="1"; shift 0;;
	    '-X') debug="1"; shift 0;;
		*) checkurls="${checkurls} $1"; shift 0;; # URLs to read
	esac
	shift 1
done

if [[ ! ${WORKSPACE} ]]; then WORKSPACE=/tmp; fi

if [[ ! $checkurls ]]; then usage; fi

countItems () 
{
	list="$1"
	listItems="${list//,/ }"
	itemCount=0
	for c in ${listItems}; do 
		(( itemCount++ ))
	done
}

logn ()
{
  if [[ $quiet == 0 ]]; then echo -n -e "$1"; fi
}

log ()
{
  if [[ $quiet == 0 ]]; then echo -e "$1"; fi
}
logerr ()
{
  if [[ $quiet == 0 ]]; then 
    echo -e "$2"
  else
    echo -e "$1$2"
  fi
}

norm="\033[0;39m"
green="\033[1;32m"
yellow='\e[0;30m\e[1;43m' # yellow reversed
red="\033[1;31m"
OK=0
notOK=0

checkCompositeXML ()
{
    # parse the file for <child location="" URLs>
    checkurl=$1
    indent=$2
    checkurl_PREV=$3
    indent_PREV=$4
	if [[ $debug -eq 1 ]]; then
	    echo "[DEBUG] Check children of $checkurl"
	fi

	curl -s ${checkurl} > ${tmpdir}/composite.xml
	if [[ ! -f ${tmpdir}/composite.xml ]] || [[ $(egrep "404 Not Found" ${tmpdir}/composite.xml) ]]; then
		echo "[ERROR] Could not read ${checkurl} ! "
		rm -fr ${tmpdir}
		exit 1
	fi
	if [[ $debug -eq 1 ]]; then
		echo "[DEBUG] ${tmpdir}/composite.xml"
		echo "[DEBUG] ------------"
		cat ${tmpdir}/composite.xml
		echo "[DEBUG] ------------"
	fi
	cat ${tmpdir}/composite.xml | egrep "<child " | egrep -v "<\!--" | egrep "location" \
	  | sed -e "s#.*<child location=[\'\"]\+\([^\'\"]\+\)[\'\"]\+\/>.*#\1#" > ${tmpdir}/composite.txt
	urls=$(cat ${tmpdir}/composite.txt)
	if [[ $debug -eq 1 ]]; then
		echo "[DEBUG] Got urls (in ${tmpdir}/composite.txt ):"
		echo "[DEBUG] ------------"
		cnt=0
		for url in $urls; do 
			(( cnt = cnt + 1 ))
			echo "[$cnt] $url"
		done
		echo "[DEBUG] ------------"
	fi
	rm -f ${tmpdir}/composite.txt ${tmpdir}/composite.xml

	countItems "${urls}"
	(( numUrls = numUrls + itemCount ))

	newurls=""
    for a in ${urls}; do
        if [[ ${a} != "http"* ]]; then # relative path
            a=${checkurl%/composite*xml}/${a}
        fi
	    newurls="${newurls} ${a}"
    done
    urls=${newurls}

	if [[ $debug -eq 1 ]]; then
		echo "[DEBUG] Got urls:"
		echo "[DEBUG] ------------"
		cnt=0
		for url in $urls; do 
			(( cnt = cnt + 1 ))
			echo "[$cnt] $url"
		done
		echo "[DEBUG] ------------"
	fi
 
    for a in ${urls}; do
		((num = num + 1 ))
        logn "{${checkurlnum}/${checkurltot}} [${num}/${numUrls}]${indent} ${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
        if [[ ! $stat ]]; then 
        	log "${green}OK${norm}"
        	let OK+=1
			stat=$(curl -I -s ${a}/compositeContent.xml | egrep "404 Not Found")
			if [[ ! $stat ]]; then # exists
				checkCompositeXML ${a}/compositeContent.xml "${indent_PREV} >" ${checkurl} ${indent}
			fi
        else 
        	if [[ $quiet == 0 ]]; then 
	        	logerr "{${checkurlnum}/${checkurltot}} [${num}/${numUrls}]${indent} ${a} : " "${red}NO${norm} \n$(curl -I -s ${a})"
	        else
    	    	logerr "{${checkurlnum}/${checkurltot}} [${num}/${numUrls}]${indent} ${a} : " "${red}NO${norm}"
    	    fi
        	let notOK+=1
        fi
    done
}

checkurlnum=0
for checkurl in ${checkurls}; do
	(( checkurltot = checkurltot + 1 ))
done

for checkurl in ${checkurls}; do
	if [[ ! $checkurl == *"/compositeContent.xml" ]]; then checkurl="${checkurl}/compositeContent.xml"; fi
	baseurl=${checkurl%/compositeContent.xml}

	log
	log "[INFO] Checking for valid children in: $checkurl"
	log

	tmpdir=${WORKSPACE}/${0##*/}_tmp; mkdir -p $tmpdir
	if [[ $debug -eq 1 ]]; then
		echo "[DEBUG] tmpdir: ${tmpdir}"
	fi

	stat=$(curl -I -s ${checkurl} | egrep "404 Not Found")
	if [[ ! $stat ]]; then # exists
		(( checkurlnum = checkurlnum + 1 ))
		num=0
		numUrls=0
		checkCompositeXML ${checkurl} "" 
	else
		logerr "" "[ERROR] Could not read ${checkurl} ! "
		rm -fr ${tmpdir}
		exit 1
	fi
	rm -fr ${tmpdir}
done

log 
log "[INFO] URLs found: ${OK}"
if [[ ${notOK} -gt 0 ]]; then 
  logerr "" "[ERROR] URLs missing: ${notOK}"
  exit $notOK
fi
