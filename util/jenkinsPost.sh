#!/bin/bash

# for a given URL, curl it with https then open the http URL in chrome (or firefox) to watch the console

usage ()
{
	echo "Usage: $0 [job] [task] [jenkinsUser] [jenkinsPass] [jenkinsURL] [querystring data foo=bar&baz=foo&...]"
	echo "Example:    export userpass=\"KERBUSER:KERBPWD\" && $0 jbosstools-base_master buildWithParameters"
	echo "Example:    $0 jbosstools-build.parent_master build nboldt PASSWORD jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/DevStudio_Master/job"
	exit 1
}

if [[ $# -lt 2 ]]; then usage; fi

jenkinsURL="jenkins.mw.lab.eng.bos.redhat.com/hudson/view/DevStudio/view/DevStudio_Master/job"

job="$1"
task="$2"
if [[ $3 ]]; then jenkinsUser="$3"; fi
if [[ $4 ]]; then jenkinsPass="$4"; fi
if [[ $5 ]]; then jenkinsURL="$5"; fi
if [[ $6 ]]; then data="--data \"$6\""; fi # to pass in --data to the buildWithParameters POST

if [[ ! ${userpass} ]]; then 
	userpass="${jenkinsUser}:${jenkinsPass}"
fi

if [[ ${userpass} = ":" ]]; then usage; fi

echo -n "["
prevJob=$(curl -s http://${jenkinsURL}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
echo "${prevJob}] POST: https://${jenkinsURL}/${job}/${task} $data"
curl -k -X POST -u ${userpass} ${data} https://${jenkinsURL}/${job}/${task}
sleep 10s

browser=/usr/bin/google-chrome; if [[ ! -x ${browser} ]]; then browser=/usr/bin/firefox; fi

echo -n "["
nextJob=$(curl -s http://${jenkinsURL}/${job}/api/xml?xpath=//lastBuild/number | sed "s#<number>\([0-9]\+\)</number>#\1#")
echo "${nextJob}]  GET:  http://${jenkinsURL}/${job}/lastBuild/"

if [[ $prevJob != $nextJob ]]; then 
  ${browser} >/dev/null 2>/dev/null && ${browser} \
    http://${jenkinsURL}/${job}/lastBuild/console \
    http://${jenkinsURL}/${job}/lastBuild/parameters \
    >/dev/null 2>/dev/null
fi

exit
