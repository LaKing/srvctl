#!/bin/bash
#
# modules/containers/selftest/remove-ve.test.sh — remove-ve and destroy-ve are
# one function (remove_ve, libs/removelib.sh). The order of its steps is the
# contract: backup before anything is deleted, record before the files, prune
# last and only when the directory is really gone. Host mutations are stubbed.
# Run: bash modules/containers/selftest/remove-ve.test.sh

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
trap 'command rm -rf "$box"' EXIT

## Source COMMAND.sh as the dispatcher does and print the steps it took, then
## "exit N". EXISTS, OWNER_RC, BACKUP_RC and TREE_RC steer the stubs.
steps() { ## COMMAND
    (
        SRVCTL=selftest
        ARG=site.example
        SC_DATASTORE_DIR="$box/ds"
        mkdir -p "$SC_DATASTORE_DIR/cert/wildcard"
        touch "$SC_DATASTORE_DIR/cert/site.example.pem" "$SC_DATASTORE_DIR/cert/other.example.pem" "$SC_DATASTORE_DIR/cert/wildcard/site.example.pem"
        trail=""
        step() { trail+="$1 "; }
        trap 'echo "${trail}exit $?"' EXIT
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/libs/authlib.sh"
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/libs/removelib.sh"
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/libs/domainonlylib.sh"
        hs_only() { :; }
        argument() { :; }
        msg() { :; }
        err() { :; }
        get() {
            case "$*" in
                *" exist") echo "${EXISTS:-true}" ;;
                *" domain_only") echo "${DOMAIN_ONLY:-false}" ;;
                *) echo alice ;;
            esac
        }
        owner_only() { step owner; [[ ${OWNER_RC:-0} == 0 ]] || exit "$OWNER_RC"; }
        backup_ve() { step backup; [[ ${BACKUP_RC:-0} == 0 ]] || exit "$BACKUP_RC"; }
        container_limits_dropin() { echo "$box/dropin"; }
        del() { step del; }
        remove_container_tree() { step tree; return "${TREE_RC:-0}"; }
        run_prune() { step prune; }
        run() { step "$2"; }
        rm() {
            case "$*" in
                *machines.target.wants*) step unlink ;;
                *"$SC_DATASTORE_DIR/cert/"*) step cert; command rm "$@" ;;
            esac
        }
        cd() { :; }
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/commands/$1.sh"
        [[ -e $SC_DATASTORE_DIR/cert/site.example.pem ]] && step cert-still-there
        [[ -e $SC_DATASTORE_DIR/cert/other.example.pem ]] || step other-cert-lost
        [[ -e $SC_DATASTORE_DIR/cert/wildcard/site.example.pem ]] || step wildcard-lost
        exit 0
    )
}

echo "the two commands"
ok "remove-ve backs up first" "$(steps remove-ve)" "owner backup unlink del cert tree prune exit 0"
ok "destroy-ve is the same without the backup" "$(steps destroy-ve)" "owner unlink del cert tree prune exit 0"

echo "a domain-only record (retire-ve)"
ok "remove-ve deletes it without a backup and unmasks the unit" "$(DOMAIN_ONLY=true steps remove-ve)" "owner unlink del unmask cert tree prune exit 0"
ok "destroy-ve the same" "$(DOMAIN_ONLY=true steps destroy-ve)" "owner unlink del unmask cert tree prune exit 0"

echo "nothing is deleted when"
ok "the container has no record" "$(EXISTS=false steps destroy-ve)" "exit 22"
ok "the caller is not the owner" "$(OWNER_RC=44 steps destroy-ve)" "owner exit 44"
ok "the backup fails" "$(BACKUP_RC=23 steps remove-ve)" "owner backup exit 23"

echo "a directory that cannot be removed"
ok "ends with 16 and does not prune" "$(TREE_RC=16 steps destroy-ve)" "owner unlink del cert tree exit 16"

echo "the guards are in the command files"
for command in remove-ve destroy-ve backup-ve
do
    ok "$command checks the record, then the owner" "$(grep -E '^(existing_container|owner_only) ' "$REPO/modules/containers/commands/$command.sh" | tr '\n' ' ')" 'existing_container "$ARG" owner_only container "$ARG" '
done

echo ""
echo "remove-ve.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
