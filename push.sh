#!/bin/bash
# CODEPAD icon: mdi-atom-variant
# CODEPAD popup: false

##
## This script is NOT part of the srvctl functions, it is used for development of srvctl.
## Codepad push button: commits the srvctl source with git and pushes it to origin.
## Resides in the project root; optional arguments become part of the commit message.
##

## project directory - this file resides in the project root folder
wd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$wd" || exit 7

if ! [ -d "$wd/.git" ]
then
    echo "ERROR: $wd is not a git repository."
    exit 6
fi

echo "PUSH $HOSTNAME:$wd $(date +%Y.%m.%d-%H:%M:%S)"

branch="$(git branch --show-current)"

## development stays on the master branch
if [ "$branch" != master ]
then
    echo "NOTICE: working on branch $branch - not master."
fi

## lint report - informational only, the push itself is not blocked
## scope: only the .sh files this push will commit, not the whole repo
if command -v shellcheck > /dev/null
then
    changed="$( { git diff --name-only HEAD -- '*.sh'; git ls-files --others --exclude-standard -- '*.sh'; } | sort -u)"
    if [ -n "$changed" ]
    then
        while read -r file
        do
            ## deleted files show up in the diff but can not be linted
            [ -f "$file" ] || continue
            echo "## shellcheck $file"
            shellcheck -x "$file"
        done <<< "$changed"
        echo "## shellcheck report done"
    else
        echo "## no shell files changed - nothing to lint"
    fi
else
    echo "## shellcheck not installed - lint skipped"
    exit 112
fi

if [ -z "$(git status --porcelain)" ]
then
    echo "No files changed. $(cat version) - nothing to commit."
    exit 0
fi

## INCREMENT VERSION - only when there is something to commit
if ! [ -f "$wd/version" ]
then
    echo "0.0.0.0" > "$wd/version"
fi

cv=$(awk -F. -v OFS=. '{$NF++; print}' "$wd/version")
echo "$cv" > "$wd/version"

## commit identity - fall back to the invoking user if git has none configured
if ! git config user.email > /dev/null
then
    export GIT_AUTHOR_NAME="$USER"
    export GIT_AUTHOR_EMAIL="$USER@$HOSTNAME"
    export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
    export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
fi

git add -A .

msg="$cv"
[ $# -gt 0 ] && msg="$cv $*"

if ! git commit -m "$msg"
then
    echo "ERROR: git commit failed."
    exit 5
fi

echo "Committed version $cv on branch $branch."

## push if a remote exists - a push failure must not hide behind the commit success
if git remote | grep -q .
then
    if git push --set-upstream origin "$branch"
    then
        echo "PUSH $cv - OK."
    else
        echo "WARNING: commit $cv created locally but PUSH FAILED - re-run push or push manually."
        exit 4
    fi
else
    echo "No git remote configured - commit $cv is local only."
fi
