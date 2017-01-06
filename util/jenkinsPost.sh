#!/bin/bash

# for a given URL, curl it with https then open the http URL in chrome (or firefox) to watch the console

usage ()
{
	echo "Usage: $0 -j JOBNAME -t TaskOrActionToPerform {-u jenkinsUser} {-p jenkinsPass} {-s jenkinsURL} {-d querystring data foo=bar&baz=foo&...}"
	echo ""
	echo "Example:    export userpass=\"KERBUSER:KERBPWD\" && $0 -j jbosstools-base_master -t buildWithParameters"
	echo "Example:    $0 -j jbosstools-build.parent_master -t build -u KERBUSER -p KERBPWD -s jenkins.mw.lab.eng.bos.redhat.com/hudson/job"
	echo ""
	exit 1
}

if [[ $# -lt 2 ]]; then usage; fi

jenkinsURL="jenkins.mw.lab.eng.bos.redhat.com/hudson/job"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-j') job="$2"; shift 1;;
    '-t') task="$2"; shift 1;;
    '-u') jenkinsUser="$2"; shift 1;;
    '-p') jenkinsPass="$2"; shift 1;;
    '-s') jenkinsURL="$2"; shift 1;;
    '-d') data="--data \"$2&\""; shift 1;;
  esac
  shift 1
done

if [[ ! ${userpass} ]]; then 
	userpass="${jenkinsUser}:${jenkinsPass}"
fi

if [[ ${userpass} = ":" ]] || [[ ! ${job} ]] || [[ ! ${task} ]]; then usage; fi

echo -n "["
prevJob=$(curl -s http://${jenkinsURL}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
echo "${prevJob}] POST: https://${jenkinsURL}/${job}/${task} $data"
curl -k -X POST -u ${userpass} ${data} https://${jenkinsURL}/${job}/${task}
sleep 10s

browser=/usr/bin/google-chrome; if [[ ! -x ${browser} ]]; then browser=/usr/bin/firefox; fi

if [[ $task == "build"* ]]; then # build or buildWithParameters
	nextJob=$(curl -s http://${jenkinsURL}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
	if [[ $prevJob != $nextJob ]]; then 
		echo "[${nextJob}]  GET:  http://${jenkinsURL}/${job}/lastBuild/"
		${browser} ttp://${jenkinsURL}/${job}/lastBuild/parameters http://${jenkinsURL}/${job}/lastBuild/console >/dev/null 2>/dev/null
	fi
fi

exit
