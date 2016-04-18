#!/bin/sh

###########################################
#  
#   Find any missing commits that are IN a given branch 
#   but are NOT in the 2nd branch. 
#  
#   These missing commits are found via a concept
#   called patch-id, which will hash the contents
#   of 'git show $commitid' ignoring whitespace. 
#   
#   The mechanism used is to find the 'patch-id' for 
#   all commits in branch1 (aka maintenance) since the last-common-ancestor
#   of the two branches. It will then check for a matching
#   patch-id in the set of commits since last-common-ancestor
#   for branch2 (or master, if unset)
#  
#   If a match is not found anywhere in branch2 (master), it will output
#   this as a missing commit. 
#
###########################################

# a simple function to check if an array contains an element
# example:   IFTEST=$(contains "${somearray[@]}" "wonka")
function contains() {
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
            echo "y"
            return 0
        fi
    }
    echo "n"
    return 1
}
   
# how far back in history do we want to look to find common ancestor?
MAXDEPTHSEARCH=1000;

# get branch names from parameters.  
BRANCH1="$1"
if [ "x$BRANCH1" = "x" ]
 then
   echo "Usage: $0 jbosstools-4.3.x [master]";
   exit 1;
fi

# If branch2 isn't set via params, use master
BRANCH2="$2"
if [ "x$BRANCH2" = "x" ]
  then
     BRANCH2="master"
fi

# get the name of this folder (ie,  "jbosstools-server")
PWD1=`pwd`
BASENAME=`basename "$PWD1"`
# get the repo url for linking in the report
REPOURL="https://github.com/jbosstools/$BASENAME"

# print some info about the repo / folder
echo "Folder: $BASENAME at $REPOURL"
REPOURL2="$REPOURL/commit/"

# stash any changes, and update branches $BRANCH1 and $BRANCH2
git stash > /dev/null 2>&1
git fetch origin > /dev/null 2>&1
git checkout $BRANCH1 > /dev/null 2>&1
git reset --hard origin/$BRANCH1 > /dev/null 2>&1
git checkout $BRANCH2 > /dev/null 2>&1
git reset --hard origin/$BRANCH2 > /dev/null 2>&1

# find the last common ancestor between $BRANCH1 and $BRANCH2
# max depth to find common ancestor is MAXDEPTHSEARCH commits
LASTCOMMON=`git merge-base $BRANCH1 $BRANCH2  | cut -c 1,2,3,4,5,6`
FROMMASTER=`git lg -$MAXDEPTHSEARCH | grep -n $LASTCOMMON | cut -f 1 -d ":"`

git checkout $BRANCH1 > /dev/null 2>&1
FROMMAINT=`git lg -$MAXDEPTHSEARCH | grep -n $LASTCOMMON | cut -f 1 -d ":"`
echo "Searching for commits present in $BRANCH1 and missing from $BRANCH2";
echo " Commit hash  \"$LASTCOMMON\" is the last common ancestor of $BRANCH1 and $BRANCH2"
echo " $LASTCOMMON is $FROMMASTER commits ago in branch $BRANCH2"
echo " $LASTCOMMON is $FROMMAINT commits ago in branch $BRANCH1"

# currently in $BRANCH1
# get all commit id's from maitnenance between top and last common ancestor
MAINTCOMMITS=(`git log --format="%H" -$FROMMAINT | cut -f 2 -d " "`)

# get all commit id's from $BRANCH2 between top and last common ancestor
git checkout $BRANCH2 > /dev/null 2>&1
MASTERCOMMITS=(`git log --format="%H" -$FROMMASTER | cut -f 2 -d " "`)

#get the patch-id for each commit in $BRANCH2
MASTERPATCHID=()
git checkout $BRANCH2 > /dev/null 2>&1
for i in ${MASTERCOMMITS[@]}; do
    TMPPATCHID=`git show -U1 $i | git patch-id | cut -f 1 -d " "`
    MASTERPATCHID+=($TMPPATCHID)
done

echo "   Commits missing from $BRANCH2 that are in $BRANCH1:"
# get the patch id for each commit in $BRANCH1
MAINTPATCHID=()
git checkout $BRANCH1 > /dev/null 2>&1
for i in ${MAINTCOMMITS[@]}; do
    TEMPPATCHID=`git show -U1 $i | git patch-id | cut -f 1 -d " "`
    MAINTPATCHID+=($TEMPPATCHID)
    # if $BRANCH2 doesn't contain a matching commit, we should output this as a missing commit
    IFTEST=$(contains "${MASTERPATCHID[@]}" "$TEMPPATCHID")
    if [ $IFTEST == "y" ]; then :; else
       echo "* missing: [$i|$REPOURL2$i]"
       COMMITMSG=`git log --format=%f -n 1 $i`
       git log $BRANCH2 --format='%H - %f' -n 1000 | grep $COMMITMSG | cut -f 1 -d " " \
       | awk -v originalid="$i" -v repo="$REPOURL2" '{ print "** possible match: [" $0 "|" repo $0 "]."; system("git show " originalid " > .testscript1"); system("git show " $0 " > .testscript2"); system("diff .testscript1 .testscript2 | curl -s -F \"sprunge=<-\" \"http://sprunge.us\"");}' | sed  -e 's/^http/\*\*\* Inspect the difference between the two patches:  http/'
    fi
done

