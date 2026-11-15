#!/bin/bash
#
# modules/containers/selftest/retire-ve.test.sh — retire-ve (libs/domainonlylib.sh)
# makes a container a domain-only record. The order of its steps is the
# contract: every refusal before any change, backup and DKIM key before
# anything is deleted, the record marked before the files go, prune last.
# Host mutations are stubbed; the DKIM copy runs on real temporary files.
# Run: bash modules/containers/selftest/retire-ve.test.sh

# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2329
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

## Source retire-ve.sh as the dispatcher does and print the steps it took, then
## "exit N". FIELDS ("field=value ..." of site.example), OTHERS (list rows),
## ROOT_RC, BACKUP_RC, TREE_RC, OPA and HOST steer the stubs.
steps() {
    (
        SRVCTL=selftest
        ARG=site.example
        OPA="${OPA:-}"
        HOSTNAME=node1
        SC_DATASTORE_DIR="$box/ds"
        SC_RETIRE_SRV_DIR="$box/srv"
        command rm -rf "$box/srv" "$box/ds" "$box/errors"
        mkdir -p "$box/srv/site.example/rootfs" "$box/srv/site.example/opendkim" "$box/ds/opendkim"
        echo key > "$box/srv/site.example/opendkim/default.private"
        [[ ${NO_ROOTFS:-} ]] && command rm -rf "$box/srv/site.example/rootfs"
        trail=""
        step() { trail+="$1 "; }
        trap 'echo "${trail}exit $?"' EXIT
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/libs/authlib.sh"
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/libs/domainonlylib.sh"
        declare -A field=([user]=alice [web_ve]=web.example [mail_ve]=web.example [host_by_ip]="${HOST:-node1}" [domain_only]=false)
        local kv
        for kv in ${FIELDS:-}
        do
            field[${kv%%=*}]="${kv#*=}"
        done
        hs_only() { :; }
        root_only() { [[ ${ROOT_RC:-0} == 0 ]] || exit 44; }
        argument() { :; }
        msg() { :; }
        ntc() { :; }
        err() { echo "$*" >> "$box/errors"; }
        get() {
            local C="$2" f="${3:-}"
            if [[ $C == site.example ]]
            then
                [[ $f == exist ]] && { echo true; return 0; }
                [[ -n ${field[$f]:-} ]] || return 100
                echo "${field[$f]}"
                return 0
            fi
            case "$f" in
                exist) [[ $C == web.example || $C == retired.example ]] && echo true || echo false ;;
                domain_only) [[ $C == retired.example ]] && echo true || echo false ;;
                *) return 100 ;;
            esac
        }
        list() { printf '%s' "${OTHERS:-$'web.example\t-\t-\n'}"; }
        put() { step "put:$3${4:+=$4}"; }
        backup_ve() { step backup; [[ ${BACKUP_RC:-0} == 0 ]] || exit "$BACKUP_RC"; }
        preserve_real="$(declare -f preserve_dkim_keys)"
        preserve_dkim_keys() { step dkim; [[ ${DKIM_RC:-0} == 0 ]] || return 1; eval "${preserve_real/preserve_dkim_keys/_preserve}"; _preserve "$@"; }
        container_limits_dropin() { echo "$box/dropin"; }
        remove_container_tree() { step tree; return "${TREE_RC:-0}"; }
        run_prune() { step prune; }
        run() { step "$2:$3"; }
        rm() {
            case "$*" in
                *machines.target.wants*) step unlink ;;
                *"$box/dropin"*) step dropin ;;
            esac
        }
        cd() { :; }
        # shellcheck source=/dev/null
        source "$REPO/modules/containers/commands/retire-ve.sh"
        exit 0
    ) < /dev/null
}

ALL="backup dkim put:domain_only=true unlink dropin mask:srvctl-nspawn@site.example.service tree prune exit 0"

echo "retirement"
ok "the order of the steps" "$(steps)" "$ALL"
ok "the DKIM key is in the host-side folder" "$(cat "$box/ds/opendkim/site.example/default.private")" key
ok "mapped ports are cleared, prune closes them" "$(FIELDS="mapped_ports=[1]" steps)" "backup dkim put:domain_only=true unlink dropin mask:srvctl-nspawn@site.example.service tree put:mapped_ports prune exit 0"
ok "no-web is accepted without a web_ve, with no terminal" "$(FIELDS="web_ve=" OPA=no-web steps)" "$ALL"
ok "a missing mail_ve still retires" "$(FIELDS="mail_ve=" steps)" "$ALL"
ok "and is reported loudly" "$(grep -c '^MAIL: site.example has no mail_ve' "$box/errors")" 1

echo "nothing changes when"
ok "the caller is not root" "$(ROOT_RC=44 steps)" "exit 44"
ok "the backup fails" "$(BACKUP_RC=23 steps)" "backup exit 23"
ok "the DKIM key cannot be preserved" "$(DKIM_RC=1 steps)" "backup dkim exit 1"
ok "the files cannot be removed: marked, then 16" "$(TREE_RC=16 steps)" "backup dkim put:domain_only=true unlink dropin mask:srvctl-nspawn@site.example.service tree exit 16"
ok "the recovery asks to unmount and verify first" "$(grep -c "Unmount everything listed above, check that 'findmnt -R" "$box/errors")" 1
ok "there is no web_ve and no no-web" "$(FIELDS="web_ve=" steps)" "exit 22"
ok "an unknown option is given" "$(OPA=yes steps)" "exit 22"
ok "the record is domain-only already" "$(FIELDS="domain_only=true" steps)" "exit 22"
ok "the rootfs is not on this host" "$(NO_ROOTFS=1 steps)" "exit 22"
ok "it is a bridge container" "$(FIELDS="bridge=br-x" steps)" "exit 22"
ok "its ip belongs to another host's network" "$(HOST=node2 steps)" "exit 22"
ok "the web_ve is unknown" "$(FIELDS="web_ve=gone.example" steps)" "exit 22"
ok "the web_ve is domain-only" "$(FIELDS="web_ve=retired.example" steps)" "exit 22"
ok "the web_ve is itself" "$(FIELDS="web_ve=site.example" steps)" "exit 22"
ok "the mail_ve is domain-only" "$(FIELDS="mail_ve=retired.example" steps)" "exit 22"
ok "another VE hands its web to it" "$(OTHERS=$'other.example\tsite.example\t-\n' steps)" "exit 22"
ok "another VE hands its mail to it" "$(OTHERS=$'other.example\t-\tsite.example\n' steps)" "exit 22"

echo "preserve_dkim_keys"
(
    SRVCTL=selftest
    msg() { :; }
    ntc() { :; }
    # shellcheck source=/dev/null
    source "$REPO/modules/containers/libs/domainonlylib.sh"
    d="$box/dk"
    command rm -rf "$d"
    mkdir -p "$d/src" "$d/mailsrc" "$d/dest" "$d/empty"
    echo private > "$d/src/default.private"
    echo txt > "$d/src/default.txt"
    echo mailkey > "$d/mailsrc/mail.private"
    preserve_dkim_keys a.test "$d/src" "$d/dest"; echo "rc $?"
    cat "$d/dest/a.test/default.private" "$d/dest/a.test/default.txt"
    preserve_dkim_keys mail.a.test "$d/mailsrc" "$d/dest"; echo "rc $?"
    cat "$d/dest/mail.a.test/mail.private"
    preserve_dkim_keys a.test "$d/empty" "$d/dest"; echo "kept rc $?"
    preserve_dkim_keys none.test "$d/empty" "$d/dest"; echo "none rc $?"
    touch "$d/blocked"
    preserve_dkim_keys b.test "$d/src" "$d/blocked" 2> /dev/null; echo "unwritable rc $?"
) > "$box/dkim.out"
ok "copies and verifies the key and its txt, the mail selector, keeps an existing copy, and fails when the copy fails" \
    "$(tr '\n' ' ' < "$box/dkim.out")" "rc 0 private txt rc 0 mailkey kept rc 0 none rc 0 unwritable rc 1 "

echo "the command file"
f="$REPO/modules/containers/commands/retire-ve.sh"
ok "the hint is in the first 10 lines" "$(head -10 "$f" | grep -c '^## @en ')" 1
root_line="$(grep -n '^root_only$' "$f" | cut -d: -f1)"
first_call="$(grep -nE '^(argument|existing_container|retire_ve_preflight|retire_ve) ' "$f" | head -1 | cut -d: -f1)"
ok "root_only is a line of its own, before every other call" "$(( ${root_line:-999} < ${first_call:-0} ))" 1
ok "the srvctl guard" "$(grep -c '^\[\[ \$SRVCTL \]\] || exit 4$' "$f")" 1

echo ""
echo "retire-ve.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
