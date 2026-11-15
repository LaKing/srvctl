#!/bin/bash
#
# modules/containers/selftest/add-ve.test.sh — what add-ve refuses. The name
# and the type come from the command line of any user and end up in paths, in
# unit names and in the datastore; a file of a base image or of a container is
# read, never sourced. Everything after the datastore record is stubbed.
# Run: bash modules/containers/selftest/add-ve.test.sh

# shellcheck disable=SC2030,SC2031,SC2034,SC2329
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
mkdir -p "$box/rootfs/fedora/etc" "$box/rootfs/hostile/etc" "$box/outside/etc"
echo 'ID=fedora' > "$box/rootfs/fedora/etc/os-release"
printf '%s\n' 'ID=fedora' "touch '$box/sourced'" > "$box/rootfs/hostile/etc/os-release"
printf '%s\n' "touch '$box/sourced'" > "$box/outside/etc/os-release"

# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/addcontainerlib.sh"
# shellcheck source=/dev/null
source "$REPO/modules/containers/libs/create-container.sh"

echo "container names"
for name in example.com a.b-c.d v4-devel x 2024.example.de xn--bcher-kva.example
do
    ok "$name is a name" "$(valid_container_name "$name"; echo $?)" 0
done
long="$(printf 'a%.0s' {1..61}).com"
for name in Example.com -a.com a-.com a..b .hidden a. a/b ../x 'a b' 'a;b' 'a$(id)' '' "$long"
do
    ok "'$name' is no name" "$(valid_container_name "$name"; echo $?)" 1
done

echo "a name that another container serves"
list() {
    printf '%s\n' 'shop.example	["shop.example","www.shop.example","alias.example","www.alias.example"]' 'v4-devel	[]' 'www.old.example	["www.old.example","www.www.old.example"]'
    return "${LIST_RC:-0}"
}
ok "an alias" "$(container_domain_owner alias.example)" shop.example
ok "the www of a name" "$(container_domain_owner www.shop.example)" shop.example
ok "the name below a www container" "$(container_domain_owner old.example)" www.old.example
ok "a part of a name is free" "$(container_domain_owner hop.example)" ""
ok "a subdomain is free" "$(container_domain_owner api.shop.example)" ""
ok "a failed read is an error, not a free name" "$(LIST_RC=112 container_domain_owner free.example > /dev/null; echo $?)" 112

echo "add-ve"
## Source the command file as the dispatcher does; print "new NAME TYPE" when
## the datastore record would be written, then "exit N".
add() { ## NAME [TYPE]
    (
        ## the command files are not written for nounset
        set +u
        SRVCTL=selftest
        ARG="$1"
        OPA="${2:-}"
        SC_ROOTFS_DIR="$box/rootfs"
        trap 'echo "exit $?"' EXIT
        argument() { :; }
        users_only() { :; }
        sudomize() { :; }
        msg() { :; }
        err() { :; }
        exif() { local rc=$?; [[ $rc == 0 ]] || exit "$rc"; }
        run_hook() { :; }
        get() { [[ $* == "container taken.example exist" ]] && echo true || echo false; }
        new() { echo "new $2 $3"; exit 0; }
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/commands/add-ve.sh"
    )
}
ok "a good name reaches the datastore, type fedora by default" "$(add good.example | tr '\n' ' ')" "new good.example fedora exit 0 "
ok "an invalid name" "$(add 'Bad_Name')" "exit 22"
ok "a name with a path" "$(add '../../etc')" "exit 22"
ok "an unknown type" "$(add good.example debian)" "exit 10"
ok "a type that leaves the image directory" "$(add good.example ../outside)" "exit 10"
ok "an existing container" "$(add taken.example)" "exit 11"
ok "a domain of another container" "$(add alias.example)" "exit 13"
ok "a base image's os-release is not sourced" "$(add good.example hostile | tr '\n' ' '; [[ -e $box/sourced ]] && echo sourced)" "new good.example hostile exit 0 "

echo "the os-release of a container"
mkdir -p "$box/ve/quoted/etc" "$box/ve/code/etc" "$box/ve/empty"
echo 'ID="debian"' > "$box/ve/quoted/etc/os-release"
printf '%s\n' "ID=\$(touch '$box/sourced')" > "$box/ve/code/etc/os-release"
ok "is read" "$(rootfs_os_id "$box/rootfs/fedora")" fedora
ok "quotes are dropped" "$(rootfs_os_id "$box/ve/quoted")" debian
ok "shell code is not an id" "$(rootfs_os_id "$box/ve/code"; echo $?)" 1
ok "a missing file is not an id" "$(rootfs_os_id "$box/ve/empty"; echo $?)" 1
ok "and nothing was executed" "$([[ -e $box/sourced ]] && echo sourced || echo clean)" clean
ok "no lib sources a file below a rootfs" "$(grep -lE '^[^#]*source[^#]*rootfs' "$REPO"/modules/containers/libs/*.sh "$REPO"/modules/containers/commands/*.sh | wc -l)" 0

echo ""
echo "add-ve.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
