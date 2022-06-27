#!/bin/bash
# recursively validate if child links within a composite site exist as real sites, or return 404

usage ()
{
	echo "Usage	: $0 url_to_check1 url_to_check2"
	echo "Example (good URLs): $0 \\"
	echo "  https://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/master \\"
 	echo "  https://download.jboss.org/jbosstools/oxygen/snapshots/updates/discovery.earlyaccess/master \\"
 	echo "  \\"

 	echo "  https://download.jboss.org/jbosstools/oxygen/development/updates/ \\"
 	echo "  https://download.jboss.org/jbosstools/oxygen/development/updates/discovery.earlyaccess \\"
 	echo "  \\"

	echo "  https://download.jboss.org/jbosstools/oxygen/stable/updates/ \\"
 	echo "  https://download.jboss.org/jbosstools/oxygen/stable/updates/discovery.earlyaccess"
 	echo ""

	echo "Example (good URLs): $0 \\"
 	echo "  https://devstudio.redhat.com/11/stable/updates \\"
 	echo "  https://devstudio.redhat.com/11/stable/updates/discovery.earlyaccess"
	echo ""

	echo "Example (bad/obsolete URLs): $0 \\"
	echo "  https://download.jboss.org/jbosstools/builds/staging/_composite_/core/master \\"
	echo "  https://download.jboss.org/jbosstools/oxygen/snapshots/builds/_composite_/core/4.5.oxygen \\"
	echo "  https://download.jboss.org/jbosstools/oxygen/development/updates/integration-stack/discovery/earlyaccess/"
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
blue="\033[1;34m"
red="\033[1;31m"
OK=0
notOK=0
warnOK=0

checkCompositeXML ()
{
	# parse the file for <child location="" URLs>
	checkurl=$1
	indentNum=$2
	if [[ $debug -eq 1 ]]; then
		log "[DEBUG] Check children of $checkurl"
	fi

	curl -s ${checkurl} > ${tmpdir}/composite.xml
	if [[ ! -f ${tmpdir}/composite.xml ]] || [[ $(egrep "404 Not Found" ${tmpdir}/composite.xml) ]]; then
		# check if the folder exists (but isn't a composite)
		curl -s ${checkurl%/composite*.xml} > ${tmpdir}/index.html
		if [[ ! -f ${tmpdir}/index.html ]] || [[ $(egrep "404 Not Found" ${tmpdir}/index.html) ]]; then
			logerr "[ERROR] Could not read ${checkurl} ! "
			rm -fr ${tmpdir}
			exit 1
		else
			checkurl=${checkurl%/composite*.xml}
			logerr "" "{${checkurlnum}/${checkurltot}} [${num}/${numUrls}]${indent} ${checkurl} is not a composite site: ${blue}OK${norm}"
			let warnOK+=1
		fi
	fi
	if [[ -f ${tmpdir}/composite.xml ]]; then
		if [[ $debug -eq 1 ]]; then
			log "[DEBUG] ${tmpdir}/composite.xml"
			log "[DEBUG] ------------"
			cat ${tmpdir}/composite.xml
			log "[DEBUG] ------------"
		fi
		cat ${tmpdir}/composite.xml | egrep "<child " | egrep -v "<\!--" | egrep "location" \
		  | sed -e "s#.*<child location=[\'\"]\+\([^\'\"]\+\)[\'\"]\+.*\/>.*#\1#" > ${tmpdir}/composite.txt
		urls=$(cat ${tmpdir}/composite.txt)
		if [[ $debug -eq 1 ]]; then
			log "[DEBUG] Got urls (in ${tmpdir}/composite.txt ):"
			log "[DEBUG] ------------"
			cnt=0
			for url in $urls; do 
				(( cnt = cnt + 1 ))
				log "[$cnt] $url"
			done
			log "[DEBUG] ------------"
		fi
		rm -f ${tmpdir}/composite.txt ${tmpdir}/composite.xml
	elif [[ -f ${tmpdir}/index.html ]]; then
		urls="${checkurl}"
		# TODO parse the index page for links to validate?
	else
		urls="${checkurl}"
	fi

	if [[ ${urls} ]]; then
		countItems "${urls}"
		(( numUrls = numUrls + itemCount ))

		newurls=""
		for a in ${urls}; do
			if [[ ${a} == "/"* ]]; then # absolute path
				prot=${checkurl%%/*}; server=${checkurl##${prot}//}; server=${server%%/*}; # echo $prot $server
				a=${prot}//${server}${a}
			elif [[ ${a} != "http"* ]]; then # relative path
				a=${checkurl%/composite*xml}/${a}
			fi
			newurls="${newurls} ${a}"
		done
		urls=${newurls}

		if [[ $debug -eq 1 ]]; then
			log "[DEBUG] Got urls:"
			log "[DEBUG] ------------"
			cnt=0
			for url in $urls; do 
				(( cnt = cnt + 1 ))
				log "[$cnt] $url"
			done
			log "[DEBUG] ------------"
		fi
	 
		for a in ${urls}; do
			((num = num + 1 ))

			indent=""
			if [[ $indentNum -gt 0 ]]; then
				for i in `seq 1 ${indentNum}`; do
					indent="${indent} >"
				done
			fi
			logn "{${checkurlnum}/${checkurltot}} [${num}/${numUrls}]${indent} ${a} : "; stat=$(curl -I -s ${a} | egrep "404 Not Found")
			if [[ ! $stat ]]; then 
				log "${green}OK${norm}"
				let OK+=1
				stat=$(curl -I -s ${a}/compositeContent.xml | egrep "404 Not Found")
				if [[ ! $stat ]]; then # exists
					(( indentNum = indentNum + 1 ))
					checkCompositeXML ${a}/compositeContent.xml ${indentNum}
					(( indentNum = indentNum - 1 ))
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
	fi
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
		log "[DEBUG] tmpdir: ${tmpdir}"
	fi

	stat=$(curl -I -s ${checkurl} | egrep "404 Not Found")
	if [[ ! $stat ]]; then # exists
		(( checkurlnum = checkurlnum + 1 ))
		num=0
		numUrls=0
		checkCompositeXML ${checkurl} 0
	else
		curl -s ${checkurl%composite*.xml} > ${tmpdir}/index.html
		(( checkurlnum = checkurlnum + 1 ))
		if [[ ! -f ${tmpdir}/index.html ]] || [[ $(egrep "404 Not Found" ${tmpdir}/index.html) ]]; then
			checkurl=${checkurl%composite*.xml}
			logn "{${checkurlnum}/${checkurltot}} [0/0]${indent} ${checkurl} : "
			logerr "{${checkurlnum}/${checkurltot}} [0/0]${indent} ${checkurl} : " "${red}NO${norm}"
			let notOK+=1
		else
			num=0
			numUrls=0
			checkCompositeXML ${checkurl} 0
		fi
	fi
	rm -fr ${tmpdir}
done

log 
log "[INFO] URLs found: ${OK}"
if [[ $warnOK -gt 0 ]]; then
	logerr "" "[WARNING] Non-composite URLs found: ${warnOK}"
fi
if [[ ${notOK} -gt 0 ]]; then 
  logerr "" "[ERROR] URLs missing: ${notOK}"
  exit $notOK
fi
