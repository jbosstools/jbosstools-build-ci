#!/bin/bash

# This utility script will help you determine if all your projects have correctly updated their root poms to use the 
# latest parent pom version. It will first pull down the latest sources from origin/master, then parse the root pom and
# compare that to the requested parent pom version. Should any mismatches be found, the offending lines are shown and 
# links to github (to review latest commits) and Jenkins (to run any missing builds) are provided.

# This script is mostly used by releng right before a code freeze to determine which projects are building w/ an outdated
# parent pom.

usage ()
{
    echo "Usage:     $0 -b GITHUBBRANCH -pv PARENTVERSION [-skipupdate] -w1 [/path/to/jbosstools-projects/parent-folder] -w2 [/path/to/jbdevstudio-projects/parent-folder]"
    echo ""
    echo "Example 1: $0 -b jbosstools-4.4.2.x -pv 4.4.2.Final-SNAPSHOT -w1 /home/nboldt/44x -w2 /home/nboldt/44xx \\"
    echo "              -p1 \"aerogear arquillian base browsersim central discovery forge freemarker \\"
    echo "              hibernate javaee jst livereload openshift server vpe webservices\""
    echo ""
    echo "Example 2: $0 -pv 4.4.2.Final-SNAPSHOT -skipupdate -w1 /home/nboldt/tru -w2 /home/nboldt/truu -p2 build-sites -p3 product -noCreateTaskJIRAs"
    echo ""
    echo "Example 3: $0 -b master -pv 4.4.2.Final-SNAPSHOT -w1 \${WORKSPACE}/jbosstools.github -w2 \${WORKSPACE}/jbdevstudio.github \\"
    echo "               -p1 openshift -p2 build-sites -p3 product"
    echo ""
    echo "Example 4: $0 -updateRootPom -createBranch -b jbosstools-4.4.2.x -b2 master -pv 4.4.2.Final-SNAPSHOT \\"
    echo "              -w1 /tmp/jbosstools.github -p1 \"aerogear::aerogear-hybrid arquillian base::foundation browsersim central forge freemarker hibernate \\"
    echo "               javaee::jsf jst livereload openshift server vpe::visual-page-editor-core webservices integration-tests\" \\"
    echo "              -p2 \"build build-sites::updatesite discovery::central-update devdoc download.jboss.org maven-plugins:build versionwatch\" \\"
    echo "              -p3 \"artwork ci::build devdoc product::installer qa website\" -q"
    echo ""
    exit 1;
}

if [[ ${0} == "./getProjectRootPomParents.sh" ]] || [[ ${0##/*} ]]; then
  echo "[ERROR] Must run this script using an absolute path."
  echo "[ERROR] If you're trying to run this script WITHOUT creating Task JIRAs, use -noCreateTaskJIRAs flag."
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage;
fi

quiet="" # or "" or "-q"
doGitUpdate=1 # perform a git update to ensure we're current; default true
doUpdateRootPom=0 # if the wrong parent pom is referenced from the root pom (and all-tests/pom.xml) update it locally and push to master
doCreateBranch=0 # if the required branch doesn't exist, fetch from master instead, and create a new branch after pushing root pom update to master
doCreateTaskJIRAs=1 # create Task JIRAs for the changes to be done
logfileprefix=${0##*/}; logfileprefix=${logfileprefix%.sh}
version_jbt=4.4.2.Final
version_ds=10.2.0.GA
version_parent=4.4.2.Final-SNAPSHOT
#TODO support branching from somewhere other than master
github_branch=jbosstools-4.4.1.x # or master
github_branch_fallback=master # if required branch doesn't exist, fall back to fetching sources from this branch instead; default: master (eg., could be 4.4.x instead)
TARGET_PLATFORM_VERSION_MIN=4.60.2.Final
TARGET_PLATFORM_VERSION_MAX=4.61.0.Final
JIRA_HOST="https://issues.stage.jboss.org" # or https://issues.jboss.org
WORKSPACE1=/tmp
PROJECTS1="" # or "aerogear::aerogear-hybrid arquillian base::foundation browsersim central forge freemarker hibernate  \
                # javaee::jsf jst livereload openshift server vpe::visual-page-editor-core webservices integration-tests"
PROJECTS2="" # or "build build-sites::updatesite discovery::central-update devdoc download.jboss.org maven-plugins:build versionwatch"
PROJECTS3="" # or "artwork ci::build devdoc product::installer qa website
hadError=0

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-b') github_branch="$2"; shift 1;;
    '-b2') github_branch_fallback="$2"; shift 1;;
    '-pv') version_parent="$2"; shift 1;;
    '-skipupdate'|'-k') doGitUpdate=0; shift 0;;
    '-w1') WORKSPACE1="$2"; shift 1;;
    '-w2') WORKSPACE2="$2"; shift 1;;
    '-p1') PROJECTS1="$2"; shift 1;; # jbosstools-* projects
    '-p2') PROJECTS2="$2"; shift 1;; # jbosstools-build-* projects
    '-p3') PROJECTS3="$2"; shift 1;; # jbdevstudio-* projects
    '-sj') stream_jbt="$2"; shift 1;;
    '-sd') stream_ds="$2"; shift 1;;
    '-vjbt') version_jbt="$2"; shift 1;;
    '-vds') version_ds="$2"; shift 1;;
    '-tpmin') TARGET_PLATFORM_VERSION_MIN="$2"; shift 1;;
    '-tpmax') TARGET_PLATFORM_VERSION_MAX="$2"; shift 1;;
    '-jirahost') JIRA_HOST="$2"; shift 1;;
    '-jirauser') JIRA_USER="$2"; shift 1;;
    '-jirapwd') JIRA_PWD="$2"; shift 1;;
    '-updateRootPom') doUpdateRootPom=1; shift 0;;
    '-createBranch') doCreateBranch=1; shift 0;;
    '-noCreateTaskJIRAs') doCreateTaskJIRAs=0; shift 0;;
    '-q') quiet="-q"; shift 0;;
  esac
  shift 1
done

if [[ ! -f ${0/getProjectRootPomParents.sh/createTaskJIRAs.py} ]] && [[ ${doCreateTaskJIRAs} -gt 0 ]]; then
  echo "[ERROR] Could not find createTaskJIRAs.py in ${0/getProjectRootPomParents.sh/}"
  exit 1
fi

# backups if not set above
if [[ ! ${stream_jbt} ]] || [[ ! ${stream_ds} ]]; then
  if [[ $github_branch == "master" ]]; then
    stream_jbt="master"
    stream_ds="master"
  elif [[ ${github_branch/4.4/} != ${github_branch} ]]; then
    stream_jbt="4.4.neon"
    stream_ds="10.0.neon"
  fi
fi
if [[ ! ${WORKSPACE2} ]]; then
  WORKSPACE2=${WORKSPACE1}
fi

gitUpdate () {
  ghb=$1
  # if [[ ${quiet} != "-q" ]]; then echo "[INFO] Stash any changes, checkout, reset, rebase, pull changes... "; fi
  if [[ ${doGitUpdate} -gt 0 ]]; then
    git stash -q | tee -a ${logfile}
    git checkout -q -- .; git reset -q HEAD . | tee -a ${logfile}
    git rebase --abort >/dev/null 2>&1
    git pull -q origin ${ghb} | tee -a ${logfile}
    git checkout -q ${ghb} | tee -a ${logfile}
    git pull -q origin ${ghb} | tee -a ${logfile}
  fi
}

checkProjects () {
  logfile=${WORKSPACE1}/${logfileprefix}.log.txt
  chgfile=${WORKSPACE1}/${logfileprefix}.chg.txt
  errfile=${WORKSPACE1}/${logfileprefix}.err.txt

  rm -f ${logfile} ${errfile} ${chgfile}

  workspace="$1" # absolure path to the root folder where git projects are checked out
  prefix="$2" # jbosstools- or jbdevstudio-
  projects="$3" # list of projects to check
  pomfileroot="$4" # path to pomfile to check, eg., pom.xml or aggregate/pom.xml
  jobname_prefix="$5" # jbosstools- or devstudio.
  g_project_prefix="$6" # jbosstools/jbosstools- or jbdevstudio/jbdevstudio-
  stream="$7" # ${stream_jbt} or ${stream_ds}
  if [[ ${g_project_prefix/jbdevstudio/} != ${g_project_prefix} ]]; then
    componentFlag="--componentjbds"
  else
    componentFlag="--componentjbide"
  fi

  mkdir -p ${workspace}
  for j in ${projects}; do
    if [[ ${j/:/} != ${j} ]]; then # split pair into git project : jira component
      k=${j##*:} # jira component
      j=${j%%:*} # git project
    else
      k=${j} # jira component
    fi
    if [[ ${quiet} != "-q" ]]; then echo "[INFO] == ${g_project_prefix}${j} (${k}) =="; fi
    branchDoesNotExist="$(curl -s -I https://github.com/${g_project_prefix}${j}/tree/${github_branch} | egrep "404 Not Found")"
    if [[ ! -d ${workspace}/${prefix}${j} ]]; then
      # fetch the project to the workspace as it's not already here!
      pushd ${workspace} >/dev/null
      if [[ ${branchDoesNotExist} ]]; then # branch does not exist yet
        git clone --depth 1 -b ${github_branch_fallback} ${quiet} git@github.com:${g_project_prefix}${j}.git | tee -a ${logfile} # shallow clone just the fallback branch
      else
        git clone --depth 1 -b ${github_branch} ${quiet} git@github.com:${g_project_prefix}${j}.git | tee -a ${logfile} # shallow clone just the branch we want
      fi
      popd >/dev/null
    fi
    if [[ ! -d ${workspace}/${prefix}${j} ]]; then 
      echo "Error! Cannot enter ${workspace}/${prefix}${j}"
      exit 1
    fi
    pushd ${workspace}/${prefix}${j} >/dev/null
    if [[ ${branchDoesNotExist} ]]; then # branch does not exist yet
      gitUpdate ${github_branch_fallback}
    else
      gitUpdate ${github_branch}
    fi

        echo "# >>> ${prefix}${j} <<<
" >> ${tskfile}

    pomfiles=${pomfileroot}
    for z in all-tests aggregate parent; do
      if [[ -d ${workspace}/${prefix}${j}/${z} ]] && [[ -f ${workspace}/${prefix}${j}/${z}/pom.xml ]]; then pomfiles="${pomfiles} ${z}/pom.xml"; fi
    done
    for pomfile in ${pomfiles}; do
      if [[ -f ${pomfile} ]]; then # echo "$j $pomfile..."

        thisparent=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<"` # contains actual version
        wasCorrectVersion=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<" | grep $version_parent` # empty string if wrong version
        # echo "thisparent = [$thisparent]"
        if [[ ${thisparent} ]]; then
          if [[ ! $wasCorrectVersion ]]; then
            if [[ ${doUpdateRootPom} ]]; then
              perl -0777 -i.orig -pe \
              's#(<artifactId>parent</artifactId>)[\r\n\ \t]+(<version>)([\d.]+[^<>]+)(</version>)#\1\n\t\t<version>'${version_parent}'\4#igs' \
              ${pomfile}
              isCorrectVersion=`cat ${pomfile} | sed "s/[\r\n\$\^\t\ ]\+//g" | grep -A2 -B2 ">parent<" | grep $version_parent` # empty string if wrong version
            fi
            if [[ ${isCorrectVersion} ]] && [[ ${doCreateTaskJIRAs} -gt 0 ]]; then
              # create new JIRA using createTaskJIRAs.py, then pass that into the commit comment below
              # if component does not exist, JIRA will be nullstring
              if [[ ${doCreateBranch} -gt 0 ]]; then # update root poms then branch
                JIRAcmd="python -W ignore ${0/getProjectRootPomParents.sh/createTaskJIRAs.py} --jbide ${version_jbt} --jbds ${version_ds} \
--task \"Prepare for ${version_jbt} / ${version_ds}\" --taskfull \"Please perform the following tasks: \
 \
0. Make sure your component has no remaining unresolved JIRAs set for fixVersion = ${version_jbt} or ${version_ds} \

[Unresolved JIRAs with fixVersion = ${version_jbt}, ${version_ds}|https://issues.jboss.org/issues/?jql=%28%28project%20%3D%20%22JBIDE%22%20and\
%20fixVersion%20in%20%28${version_jbt}%29%29%20or%20%28project%20%3D%20%22JBDS%22%20and%20fixversion%20in%20%28\
${version_ds}%29%29%29%20and%20resolution%20%3D%20Unresolved] \
 \
1. Check out your existing *{color:orange}${github_branch_fallback}{color}* branch: \
 \
{code} \
git checkout ${github_branch_fallback} \
{code} \
 \
2. Update your *{color:orange}${github_branch_fallback} branch{color}* root pom to use the latest parent pom version, *{color:orange}${version_parent}{color}*: \
 \
{code} \
  <parent> \
    <groupId>org.jboss.tools</groupId> \
    <artifactId>parent</artifactId> \
    <version>${version_parent}</version> \
  </parent> \
{code} \
 \
Now, your root pom will use parent pom version: \
 \
* *{color:orange}${version_parent}{color}* in your *{color:orange}${github_branch_fallback}{color}* branch \
 \
3. Branch from your existing ${github_branch_fallback} branch into a new *{color:blue}${github_branch}{color}* branch: \
 \
{code} \
git checkout ${github_branch_fallback}; \
git pull origin ${github_branch_fallback}; \
git checkout -b ${github_branch}; \
git push origin ${github_branch} \
{code} \
 \
Now, your root pom will use parent pom version: \
 \
* *{color:blue}${version_parent}{color}* in your *{color:blue}${github_branch}{color}* branch, too. \
 \
4a. Ensure you've *built your code* using the latest *minimum* target platform version ${TARGET_PLATFORM_VERSION_MIN} \
 \
{code} \
mvn clean verify -Dtpc.version=${TARGET_PLATFORM_VERSION_MIN} \
{code} \
 \
4b. Ensure you've *run your tests* using the latest *maximum* target platform version ${TARGET_PLATFORM_VERSION_MAX} \
 \
{code} \
mvn clean verify -Dtpc.version=${TARGET_PLATFORM_VERSION_MAX} \
{code} \
 \
5. Close (do not resolve) this JIRA when done. \
 \
6. If you have any outstanding [New + Noteworthy JIRAs|https://issues.jboss.org/issues/?jql=%28%28project%20%3D%20%22JBIDE%22%20and%20fixVersion%20in%20%28\
${version_jbt}%29%29%20or%20%28project%20%3D%20%22JBDS%22%20and%20fixversion%20in%20%28${version_ds}%29%29%29%20AND%20resolution%20is%20\
null%20AND%20%28labels%20%3D%20new_and_noteworthy%20OR%20summary%20~%20%22New%20and%20Noteworthy%20for%20%22%29] to do, please complete them next. \
\" \
-s ${JIRA_HOST} -u ${JIRA_USER} -p ${JIRA_PWD} -J ${componentFlag} ${k}"
                echo ${JIRAcmd}
                JIRA=$(${JIRAcmd})
              else # no branching - just update root poms
                JIRAcmd="python -W ignore ${0/getProjectRootPomParents.sh/createTaskJIRAs.py} --jbide ${version_jbt} --jbds ${version_ds} \
--task \"Prepare for ${version_jbt} / ${version_ds}\" --taskfull \"Please perform the following tasks: \
 \
1. Check out your existing *{color:orange}${github_branch}{color}* branch: \
 \
{code} \
git checkout ${github_branch} \
{code} \
 \
2. Update your *{color:orange}${github_branch} branch{color}* root pom to use the latest parent pom version, *{color:orange}${version_parent}{color}*: \
 \
{code} \
  <parent> \
    <groupId>org.jboss.tools</groupId> \
    <artifactId>parent</artifactId> \
    <version>${version_parent}</version> \
  </parent> \
{code} \
 \
Now, your root pom will use parent pom version: \
 \
* *{color:orange}${version_parent}{color}* in your *{color:orange}${github_branch}{color}* branch \
 \
3. Ensure that component features/plugins have been [properly upversioned|http://wiki.eclipse.org/Version_Numbering#Overall_example], eg., from 1.0.0 to 1.0.1.  \
 \
{code} \
mvn -Dtycho.mode=maven org.eclipse.tycho:tycho-versions-plugin:0.26.0:set-version -DnewVersion=1.0.1-SNAPSHOT \
{code} \
 \
 \
4a. Ensure you've *built your code* using the latest *minimum* target platform version ${TARGET_PLATFORM_VERSION_MIN} \
 \
{code} \
mvn clean verify -Dtpc.version=${TARGET_PLATFORM_VERSION_MIN} \
{code} \
 \
4b. Ensure you've *run your tests* using the latest *maximum* target platform version ${TARGET_PLATFORM_VERSION_MAX} \
 \
{code} \
mvn clean verify -Dtpc.version=${TARGET_PLATFORM_VERSION_MAX} \
{code} \
 \
5. Close (do not resolve) this JIRA when done. \
 \
6. If you have any outstanding [New + Noteworthy JIRAs|https://issues.jboss.org/issues/?jql=%28%28project%20%3D%20%22JBIDE%22%20and%20fixVersion%20in%20%28\
${version_jbt}%29%29%20or%20%28project%20%3D%20%22JBDS%22%20and%20fixversion%20in%20%28${version_ds}%29%29%29%20AND%20resolution%20is%20\
null%20AND%20%28labels%20%3D%20new_and_noteworthy%20OR%20summary%20~%20%22New%20and%20Noteworthy%20for%20%22%29] to do, please complete them next. \
\" \
-s ${JIRA_HOST} -u ${JIRA_USER} -p ${JIRA_PWD} -J ${componentFlag} ${k}"
                echo ${JIRAcmd}
                JIRA=$(${JIRAcmd})
              fi
              if [[ ${j} == ${k} ]]; then
                echo -n "$j :: " >> ${chgfile}
              else
                echo -n "$j ($k) :: " >> ${chgfile}
              fi
              if [[ ${JIRA} ]]; then
                echo -n "${JIRA} :: " >> ${chgfile}
              fi
              echo $isCorrectVersion >> ${chgfile}
              echo "# Commit change to https://github.com/${g_project_prefix}${j}/blob/${github_branch_fallback}/${pomfile}
pushd ${workspace}/${prefix}${j} >/dev/null && perl -0777 -i.orig -pe \\
's#(<artifactId>parent</artifactId>)[\r\n\ \t]+(<version>)([\d.]+[^<>]+)(</version>)#\1\n\t\t<version>'${version_parent}'\4#igs' \\
${pomfile} && git commit -m \"${JIRA} #comment bump up to parent pom version = ${version_parent} #close\" . && git push origin ${github_branch_fallback} &&
popd >/dev/null; echo \">>> https://github.com/${g_project_prefix}${j}/commits/${github_branch_fallback}\"
" >> ${tskfile}
            else
              if [[ ${j} == ${k} ]]; then
                echo -n "$j :: " >> ${errfile}
              else
                echo -n "$j ($k) :: " >> ${errfile}
              fi
              echo $thisparent | grep version >> ${errfile}
            fi
            # echo "isCorrectVersion = [$isCorrectVersion]"
          else
        echo "# No change needed: https://github.com/${g_project_prefix}${j}/blob/${github_branch_fallback}/${pomfile} !
" >> ${tskfile}
          fi
        else
          # no reference to jbosstools >parent< found.
          continue
        fi
        if [[ $wasCorrectVersion ]]; then
          echo $j :: $wasCorrectVersion >> ${logfile}
        fi
      fi
    done
    if [[ ${doCreateBranch} -gt 0 ]]; then
      if [[ ${branchDoesNotExist} ]]; then # branch does not exist yet
        echo "# Create branch https://github.com/${g_project_prefix}${j}/tree/${github_branch} from ${github_branch_fallback}
pushd ${workspace}/${prefix}${j} && git checkout ${github_branch_fallback} && git pull origin ${github_branch_fallback}
git checkout -b ${github_branch} && git push origin ${github_branch}
popd >/dev/null && echo \">>> https://github.com/${g_project_prefix}${j}/tree/${github_branch}\"
" >> ${tskfile}
      else
        echo "# Branch exists: https://github.com/${g_project_prefix}${j}/tree/${github_branch} !
" >> ${tskfile}
      fi
    fi

    popd >/dev/null
    if [[ ${quiet} != "-q" ]]; then echo ""; fi
  done

  if [[ ${quiet} != "-q" ]] && [[ -f ${logfile} ]] && [[ $(cat ${logfile}) ]] ; then
    echo "Found these root pom versions   [CORRECT]:"
    cat ${logfile}
    echo ""
  fi

  if [[ ${quiet} != "-q" ]] && [[ -f ${chgfile} ]]; then
    echo "Found these root pom versions   [TO CHANGE]:"
    cat ${chgfile}
    echo ""
  fi

  if [[ -f ${errfile} ]]; then
    echo "Found these root pom versions [INCORRECT]:"; echo ""
    cat ${errfile}
    echo ""
    hadError=1
  fi
}

mkdir -p ${WORKSPACE1} ${WORKSPACE2}
tskfile=${WORKSPACE1}/${logfileprefix}.tsk.txt
if [[ -f ${tskfile} ]]; then rm -f ${tskfile}; fi

if [[ "${PROJECTS1}" ]]; then checkProjects ${WORKSPACE1} jbosstools-  "${PROJECTS1}" pom.xml jbosstools- jbosstools/jbosstools-   "${stream_jbt}"; fi
if [[ "${PROJECTS2}" ]]; then checkProjects ${WORKSPACE1} jbosstools-  "${PROJECTS2}" pom.xml jbosstools- jbosstools/jbosstools-   "${stream_jbt}"; fi
if [[ "${PROJECTS3}" ]]; then checkProjects ${WORKSPACE2} jbdevstudio- "${PROJECTS3}" pom.xml devstudio.  jbdevstudio/jbdevstudio- "${stream_ds}" ; fi


if [[ ${doUpdateRootPom} -gt 0 ]] || [[ ${doCreateBranch} -gt 0 ]]; then
  echo ""
  echo "Steps to perform can be found in:"
  echo "${tskfile}"
  echo ""
fi
if [[ ${hadError} -gt 0 ]]; then
  exit 1
fi