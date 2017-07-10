#!/bin/bash

# errata symlink parser 
# given  the URL of an errata report, parse the HTML for a list of problems and attempt to verify they can be waived
# eg., for https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505, install rh-eclipse47-eclipse-abrt then check the symlinks are resolved.

usage ()
{
    echo "Usage:     $0 -u [username:password] -s [errataURL] -p [problem]"
    echo ""
    echo "Example 1: $0 -u \"nboldt:password\" -s https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505 -p \"dangling symlink\""
    echo ""
    echo "Example 2: export userpass=username:password; $0 -s https://errata.devel.redhat.com/rpmdiff/show/177004?result_id=4852505 -p \"dangling symlink\" -q"
    echo ""
    exit 1;
}

if [[ $# -lt 1 ]]; then
  usage;
fi

# defaults
data="?result_id=4852505"
quiet=""
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-u') userpass="$2"; shift 1;;
    '-s') errataURL="$2"; shift 1;;
    '-p') problem="$2"; shift 1;;
    '-q') quiet="-q"; shift 0;;
  esac
  shift 1
done
data=${errataURL##*\?}; if [[ ${data} ]]; then data="--data ${data}"; fi

# echo "${data} ${errataURL} -> ${problem}"

hadError=0
tmpdir=`mktemp -d` && mkdir -p ${tmpdir} && pushd ${tmpdir} >/dev/null
  curl -s -S -k -X POST -u ${userpass} ${data} ${errataURL} > ${tmpdir}/page.html
  filesToCheck=$(cat page.html | egrep "${problem}|Results for" \
    | sed \
      -e "s#<h1> Results for \(.\+\) compared to .\+#\1#" \
      -e "s#.\+<pre>File ##" \
      -e "s# is.\+${problem}.\+to #:#" \
      -e "s#) on.\+</pre>##")
  if [[ ${filesToCheck} ]]; then
    rpm=""
    for f in ${filesToCheck}; do # echo f = $f
      # first item is the rpm we're checking
      if [[ ! ${rpm} ]]; then 
        rpm=$f
        echo "[INFO] Install rpm: ${rpm}" 
        sudo yum install $rpm -y ${quiet}
      else # split the rest into pairs
        alink=/${f%:*}
        afile=${alink%/*}/${f#*:}
        status=""
        #echo alink = $alink
        #echo afile = $afile
        if [[ ! -f ${afile} ]]; then
          if [[ -L ${afile} ]]; then
            if [[ $(file ${afile} | grep "broken symbolic link") ]]; then
              status="[ERROR] Can't find ${afile}"
              let hadError=hadError+1
            fi
          else
            status="[ERROR] Can't find ${alink} -> ${afile}"
            let hadError=hadError+1
          fi
        fi
        if [[ ${status} ]]; then
          echo ${status}
        else
          if [[ ${quiet} == "" ]]; then echo "[INFO] OK: ${alink} -> ${afile}"; fi
        fi
      fi
    done
  fi
popd >/dev/null
rm -fr ${tmpdir}

echo ""
if [[ ${hadError} -gt 0 ]]; then
  echo "[ERROR] For ${rpm}, found ${hadError} ${problem}s at ${errataURL}"
else
  echo "[INFO] For ${rpm}, found ${hadError} ${problem}s at ${errataURL}"  
fi
echo ""