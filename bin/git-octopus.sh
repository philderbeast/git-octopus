#!/bin/bash
usage() {
cat <<EOF
NAME
    git-octopus - Does an octopus merge based on branch naming pattern 
Usage
    [OPTION..] [<pattern>...] 

DESCRIPTION
    <pattern> can be any usual refspec or a pattern.
    Performs an octopus merge of all commits directly listed or induced by patterns.

OPTION
    -n, leaves the repository back to HEAD
EOF
}

line_break(){
    echo "-----------------------------------------------------------"
}

#assuming that HEAD is a symbolic ref, ie not detached
triggeredBranch=`git symbolic-ref HEAD`

resetRepository(){
    echo
    line_break
    echo "Stoping..."
    echo "HEAD -> $triggeredBranch"
    git reset -q --hard
    git checkout -q ${triggeredBranch#refs/heads/}
}

trap "resetRepository && exit 1;" SIGINT SIGQUIT

while getopts "nh" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    n)
      noCommit=1
      ;;
    \?)
      echo "Invalid option: -$opt" >&2
      exit 1
      ;;
  esac
done

if [[ -n `git diff-index HEAD` ]]
then
    echo "The repository has to be clean"
    exit 1
fi

#Shift all options in order to iterate over refspec-patterns
shift `expr $OPTIND - 1`

if [ -z $@ ] ; then
    echo "Bad use of git-octopus"
    echo
    usage
    exit 1
fi

echo "Branches beeing merged :"
for ref in `git ls-remote . $@ | cut -d $'\t' -f 2` ; do
    echo $'\t'${ref#refs/}
    refsToMerge+="${ref#refs/} "
done

line_break

if [ $noCommit ] ; then
    mergeArg="--no-commit"
fi

git merge -q --no-edit $mergeArg $refsToMerge

if [ $? -eq 0 ]
then
    # Octopus merge went well
    # Resets the repository if -n was specified, let it as it is otherwise.
    if [ $noCommit ]
    then
        git merge --abort
    fi
    line_break
    echo "OCTOPUS SUCCESS"
else
    # Octopus merge failed, starting to run the analysis sequence ...
    line_break
   
    git reset -q --hard HEAD

    echo "Testing merges one by one with ${triggeredBranch#refs/heads/}..."
    echo

    tmpFile=`mktemp -t octopus-conflicts-output`

    # Will perform a simple merge from the current branch with each branches one by one.
    for branch in $refsToMerge
    do
        if [ `git rev-parse $branch` != `git rev-parse $triggeredBranch` ]
        then
            echo -n "merging $branch... "

            #computing the best common ancestor to base the merge with
            mergeBase=`git merge-base HEAD $branch`

            # Merges the tree of the branch with the HEAD tree
            git read-tree -um --aggressive $mergeBase HEAD $branch > /dev/null

            # Doing the simple merge for conflicting paths
            # this is what octopus merge strategy does
            git merge-index -o -q git-merge-one-file -a 1> /dev/null 2> $tmpFile

            if [ $? -eq 0 ]
            then
                echo "SUCCESS"
            else
                echo "FAILED"
                cat $tmpFile
                git diff
                conflicts+="$branch "
            fi
            git reset -q --hard
        fi
    done
    
    line_break

    if [ -z "$conflicts" ]; then
        echo "No conflicts found between ${triggeredBranch#refs/heads} and the rest of the branches"
    else
        echo "${triggeredBranch#refs/heads/} has conflicts with :"
        for branch in $conflicts
        do
            echo $'\t'$branch
        done
    fi

    echo "OCTOPUS FAILED"
    exit 1
fi
