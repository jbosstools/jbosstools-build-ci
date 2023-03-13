#!/bin/bash

# for a given URL, curl it with https then open the http URL in chrome (or firefox) to watch the console

usage ()
{
	echo "Usage: $0 -j JOBNAME -t TaskOrActionToPerform {-u jenkinsUser} {-p jenkinsPass} {-s jenkinsURL} {-d querystring data foo=bar&baz=foo&...}"
	echo ""
	echo "Example:    export userpass=\"KERBUSER:KERBPWD\" && $0 -j jbosstools-base_master -t buildWithParameters"
	echo "Example:    $0 -j jbosstools-build.parent_master -t build -u KERBUSER -p KERBPWD -s https://studio-jenkins-csb-codeready.apps.ocp-c1.prod.psi.redhat.com/job/"
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

jenkinsURL="https://studio-jenkins-csb-codeready.apps.ocp-c1.prod.psi.redhat.com/job/"
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

# testing if host reachable
host=$(echo "${jenkinsURL}" | cut -d'/' -f 3)
ping -c 1 ${host} &> /dev/null
if [[ $? -ne 0 ]]; then
    echo -e  "\033[1;91m[ERROR] host '${host}' not reachable.\033[0m"
	exit 1
fi

if [[ ! ${crumb} ]]; then
	crumb=$(wget --no-check-certificate -q --auth-no-challenge --user ${jenkinsUser} --password ${jenkinsPass} --output-document - "${jenkinsURL//\/job/}/crumbIssuer/api/xml?xpath=//crumb" | sed "s#<crumb>\([0-9a-f]\+\)</crumb>#\1#")
fi
if [[ $quiet == 0 ]] && [[ -n ${crumb} ]]; then log "Crumb: ${crumb}"; fi

prevJob=$(curl -k -s -S -L --location-trusted -s ${jenkinsURL/https/http}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
logn "[${prevJob}] POST: ${jenkinsURL}/${job}/${task} $data\n"
if [[ $quiet == 1 ]] && [[ $task != "build"* ]]; then echo ${prevJob}; fi

curl -k -s -S -k -X POST -u ${userpass} -H "Jenkins-Crumb:${crumb}" ${data} ${jenkinsURL}/${job}/${task}

if [[ $task == "build"* ]]; then # build or buildWithParameters
	sleep 10s
	nextJob=$(curl -k -s -S -L --location-trusted -s ${jenkinsURL/https/http}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
	if [[ $quiet == 1 ]]; then 
		echo ${nextJob}
	else
		echo ${nextJob}
		browser=/usr/bin/google-chrome; if [[ ! -x ${browser} ]]; then browser=/usr/bin/firefox; fi
		${browser} ${jenkinsURL/https/http}/${job}/lastBuild/parameters ${jenkinsURL/https/http}/${job}/lastBuild/console >/dev/null 2>/dev/null
	fi
	if [[ "${prevJob}" != "${nextJob}" ]]; then
		log "[${nextJob}]  GET:  ${jenkinsURL/https/http}/${job}/lastBuild/"
	fi
fi
