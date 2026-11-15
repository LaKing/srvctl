#!/bin/bash
#
# modules/usersonhost/selftest/prune-shares.test.sh — a share in a user's home
# is taken back when the user is not entitled to the container any more, and
# nothing else in the home is touched. The datastore, getent, umount and the
# owner of a directory (stat) are stubbed; the mount table is a file.
# Run: bash modules/usersonhost/selftest/prune-shares.test.sh

# shellcheck disable=SC2012,SC2034,SC2329
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

pass=0
fail=0
ok() {
    if [[ "$2" == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
SC_LOG="$box/log"
NOW=now
SC_USER=tester
SC_MOUNTINFO="$box/mountinfo"
# shellcheck source=/dev/null
source "$REPO/lablib.sh"
ntc() { :; }
err() { :; }
# shellcheck source=/dev/null
source "$REPO/modules/usersonhost/libs/prunelib.sh"

## containers/libs/prunelib.sh: the domain-only records of the run
RETIRED=""
container_is_retired() { [[ " $RETIRED " == *" $1 "* ]]; }
getent() { [[ $2 == nohome ]] || echo "$2:x:1000:1000::$box/home/$2:/bin/bash"; }
declare -a CALLS=()
umount() { CALLS+=("$2"); }
## srvctl's directories are root's; projects and notes are the users' own
stat() {
    case $3 in
        */projects | */notes) echo 1000 ;;
        *) echo 0 ;;
    esac
}
LIST_RC=0
list() {
    if [[ $1 == user ]]
    then
        printf '%s\n' root anna bela nohome
    else
        printf '%s\n' 'live.example	anna	["bela"]	-' 'mail.example	root	-	anna' 'other.example	root	-	-'
    fi
    return "$LIST_RC"
}

setup() {
    rm -rf "${box:?}/home"
    ## anna owns live.example, reads mail.example; bela is a user of live.example
    mkdir -p "$box/home/anna/live.example/bindfs" "$box/home/anna/live.example/html" "$box/home/anna/mail.example/bindfs" "$box/home/bela/live.example/bindfs"
    ## anna: a removed container (still mounted), bela: taken off other.example, an empty leftover
    mkdir -p "$box/home/anna/gone.example/bindfs" "$box/home/anna/gone.example/html" "$box/home/bela/other.example/bindfs" "$box/home/bela/remote-gone.example"
    ## not shares: own data, and a look-alike with something else in it
    mkdir -p "$box/home/anna/projects/bindfs" "$box/home/bela/notes"
    echo data > "$box/home/anna/projects/file"
    ln -s "$box/home/anna/live.example" "$box/home/bela/link.example"
    printf '%s\n' "36 25 0:32 / $box/home/anna/gone.example/bindfs rw - fuse.bindfs x rw" "37 25 0:33 / $box/home/anna/gone.example/html rw - fuse.bindfs x rw" "38 25 0:34 / $box/home/anna/live.example/bindfs rw - fuse.bindfs x rw" > "$SC_MOUNTINFO"
    SC_PRUNE_CONTAINERS=" live.example mail.example other.example "
    CALLS=()
}
names() { (cd "$box/home/$1" && ls | tr '\n' ' '); }

echo "dry run"
setup
SC_PRUNE_DRY_RUN=true prune_user_shares
ok "keeps every directory" "$(find "$box/home" -mindepth 2 -maxdepth 2 | wc -l)" 9
ok "unmounts nothing" "${#CALLS[@]}" 0

echo "prune"
setup
prune_user_shares
ok "the removed container's share goes, entitled shares and own data stay" "$(names anna)" "live.example mail.example projects "
ok "its mounts are unmounted, deepest first, and no other" "${CALLS[*]}" "$box/home/anna/gone.example/html $box/home/anna/gone.example/bindfs"
ok "a user taken off a container loses the share; an empty leftover goes; a link and own data stay" "$(names bela)" "link.example live.example notes "
ok "a look-alike with other content is not touched" "$(cat "$box/home/anna/projects/file")" data

echo "a domain-only record (retire-ve)"
setup
RETIRED="other.example mail.example"
prune_user_shares
ok "its shares go although the record still lists the users" "$(names anna) / $(names bela)" "live.example projects  / link.example live.example notes "
RETIRED=""

echo "a root-owned directory with content"
setup
echo data > "$box/home/bela/other.example/file"
prune_user_shares
ok "is not a share and stays" "$(cat "$box/home/bela/other.example/file")" data

echo "a failed datastore read"
setup
LIST_RC=112
prune_user_shares
ok "keeps every directory" "$(find "$box/home" -mindepth 2 -maxdepth 2 | wc -l)" 9
LIST_RC=0
setup
SC_PRUNE_CONTAINERS=""
prune_user_shares
ok "outside run_prune nothing is removed" "$(find "$box/home" -mindepth 2 -maxdepth 2 | wc -l)" 9

echo ""
echo "prune-shares.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
