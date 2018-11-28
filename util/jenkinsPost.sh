#!/bin/bash

# for a given URL, curl it with https then open the http URL in chrome (or firefox) to watch the console

usage ()
{
	echo "Usage: $0 -j JOBNAME -t TaskOrActionToPerform {-u jenkinsUser} {-p jenkinsPass} {-s jenkinsURL} {-d querystring data foo=bar&baz=foo&...}"
	echo ""
	echo "Example:    export userpass=\"KERBUSER:KERBPWD\" && $0 -j jbosstools-base_master -t buildWithParameters"
	echo "Example:    $0 -j jbosstools-build.parent_master -t build -u KERBUSER -p KERBPWD -s https://jenkins.hosts.mwqe.eng.bos.redhat.com/hudson/job"
	echo ""
	exit 1
}

logn ()
{
  if [[ $quiet == 0 ]]; then echo -n -e "$1"; fi
}

log ()
{
  if [[ $quiet == 0 ]]; then echo -e "$1"; fi
}

if [[ $# -lt 2 ]]; then usage; fi

jenkinsURL="https://jenkins.hosts.mwqe.eng.bos.redhat.com/hudson/job"
quiet=0

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-j') job="$2"; shift 1;;
    '-t') task="$2"; shift 1;;
    '-u') jenkinsUser="$2"; shift 1;;
    '-p') jenkinsPass="$2"; shift 1;;
    '-s') jenkinsURL="$2"; shift 1;;
    '-d') data="--data \"&"${2// /%20}"&\""; shift 1;;
	'-c') crumb="$2"; shift 1;;
    '-q') quiet="1"; shift 0;;
  esac
  shift 1
done

if [[ ! ${userpass} ]]; then 
	userpass="${jenkinsUser}:${jenkinsPass}"
fi

if [[ ${userpass} = ":" ]] || [[ ! ${job} ]] || [[ ! ${task} ]]; then usage; fi

if [[ ! ${crumb} ]]; then
	# due to redirection, curl won't work -- wrong crumb returned
	crumb=$(curl -k -s -S -L --location-trusted -s ${jenkinsURL//\/job/}/crumbIssuer/api/xml?xpath=//crumb | sed "s#<crumb>\([0-9a-f]\+\)</crumb>#\1#")
	# so use wget
	crumb=$(wget --no-check-certificate -q --auth-no-challenge --user ${jenkinsUser} --password "${jenkinsPass}" --output-document - "${jenkinsURL//\/job/}/crumbIssuer/api/xml?xpath=//crumb" \
	  | sed "s#<crumb>\([0-9a-f]\+\)</crumb>#\1#")
fi
if [[ $quiet == 0 ]]; then log "Crumb: ${crumb}"; fi

logn "["
prevJob=$(curl -k -s -S -L --location-trusted -s ${jenkinsURL/https/http}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
log "${prevJob}] POST: ${jenkinsURL}/${job}/${task} $data"
if [[ $quiet == 1 ]] && [[ $task != "build"* ]]; then echo ${prevJob}; fi

curl -k -s -S -k -X POST -u ${userpass} -H "Jenkins-Crumb:${crumb}" ${data} ${jenkinsURL}/${job}/${task}

if [[ $task == "build"* ]]; then # build or buildWithParameters
	sleep 10s
	browser=/usr/bin/google-chrome; if [[ ! -x ${browser} ]]; then browser=/usr/bin/firefox; fi
	nextJob=$(curl -k -s -S -L --location-trusted -s ${jenkinsURL/https/http}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
	if [[ $quiet == 1 ]]; then echo ${nextJob}; fi
	if [[ "${prevJob}" != "${nextJob}" ]]; then
		log "[${nextJob}]  GET:  ${jenkinsURL/https/http}/${job}/lastBuild/"
		${browser} ${jenkinsURL/https/http}/${job}/lastBuild/parameters ${jenkinsURL/https/http}/${job}/lastBuild/console >/dev/null 2>/dev/null
	fi
fi
