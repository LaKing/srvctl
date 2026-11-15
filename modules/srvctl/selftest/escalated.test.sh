#!/bin/bash
#
# modules/srvctl/selftest/escalated.test.sh — the caller who reached uid 0
# through sudo. The sudoers entry gives that to every account, so srvctl must
# not take code from the caller's home and must not start a command that does
# not check who is asking. Also: users_only, and the list of shipped commands
# that carry no identity guard.
# Run: bash modules/srvctl/selftest/escalated.test.sh

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

## Run SNIPPET as SC_USER / SC_UID0 with commonlib and authlib loaded; the
## output is what the snippet prints, the status its exit code.
probe() { ## SC_USER SC_UID0 SNIPPET
    (
        SRVCTL=1
        SC_USER="$1"
        SC_UID0="$2"
        SC_INSTALL_DIR="$REPO"
        CMD=probe
        # shellcheck source=/dev/null
        source "$REPO/commonlib.sh"
        # shellcheck source=/dev/null
        source "$REPO/modules/srvctl/libs/authlib.sh"
        err() { :; }
        debug() { :; }
        getent() { echo "$2:x:0:0::/home-of/$2:/bin/bash"; }
        get() {
            case "$*" in
                "user alice exist") echo true ;;
                "user ghost exist") echo false ;;
                "user broken exist") return 112 ;;
            esac
        }
        eval "$3"
    )
}

echo "sc_escalated"
ok "a user at uid 0 is escalated" "$(probe alice true 'sc_escalated; echo $?')" 0
ok "root at uid 0 is not" "$(probe root true 'sc_escalated; echo $?')" 1
ok "a user without sudo is not" "$(probe alice false 'sc_escalated; echo $?')" 1

echo "the home srvctl takes code from"
ok "a user without sudo: his own home" "$(probe alice false sc_code_home)" /home-of/alice
ok "a user at uid 0: root's home" "$(probe alice true sc_code_home)" /home-of/root
ok "root: root's home" "$(probe root true sc_code_home)" /home-of/root

echo "the dispatcher's gate"
cmdfile() { ## NAME LINE...
    local name="$1"
    shift
    printf '%s\n' '#!/bin/bash' '## @en test' "$@" > "$box/$name.sh"
}
cmdfile bare 'echo ran'
cmdfile sudo-only 'sudomize' 'echo ran'
cmdfile commented '## root_only' '# owner_only container "$C"' 'echo "users_only"' 'echo ran'
cmdfile root '    root_only   # with a comment'
cmdfile operators 'operators_only'
cmdfile users 'users_only'
cmdfile owner 'owner_only container "$ARG"'
cmdfile owner-bare 'owner_only'
gate() { probe "$1" "$2" "command_may_run '$box/$3.sh'; echo passed" > /dev/null; echo $?; }
ok "an unguarded command is refused for an escalated caller" "$(gate alice true bare)" 44
ok "sudomize is no guard" "$(gate alice true sudo-only)" 44
ok "a guard in a comment or a string is no guard" "$(gate alice true commented)" 44
ok "owner_only without a record is no guard" "$(gate alice true owner-bare)" 44
for guard in root operators users owner
do
    ok "a $guard guard lets the command start" "$(gate alice true "$guard")" 0
done
ok "root starts an unguarded command" "$(gate root true bare)" 0
ok "a user without sudo starts an unguarded command" "$(gate alice false bare)" 0

echo "raw datastore reads"
verbs() { probe "$1" "$2" 'OPAS="user x"; get() { echo value; }; exif() { :; }; CMD=get; run_command'; }
ok "an escalated caller gets no read verb" "$(verbs alice true > /dev/null; echo $?)" 44
ok "a user without sudo reads" "$(verbs alice false)" value

echo "users_only"
ok "root passes" "$(probe root true 'users_only; echo $?')" 0
ok "a user with a record passes" "$(probe alice true 'users_only; echo $?')" 0
ok "an account without a record is refused" "$(probe ghost true 'users_only' > /dev/null; echo $?)" 44
ok "a failed lookup ends with its own code, not with a denial" "$(probe broken true 'users_only' > /dev/null; echo $?)" 112
ok "the name root without uid 0 is no root" "$(probe root false 'get() { echo false; }; users_only' > /dev/null; echo $?)" 44

echo "shipped commands without an identity guard"
## Every other command file calls root_only, operators_only, users_only or
## owner_only, so it can be started through sudo. These cannot, and each is a
## read that needs no uid 0. A new name here needs that same answer.
unguarded="$(cd "$REPO/modules" && grep -LE '^[[:space:]]*(root_only|operators_only|users_only|owner_only[[:space:]]+[^#]+)[[:space:]]*(#.*)?$' ./*/commands/*.sh ./*/command.sh | sort | tr '\n' ' ')"
ok "the list is the known one" "$unguarded" "./containers/commands/status.sh ./srvctl/commands/diagnose.sh ./srvctl/commands/ls.sh ./srvctl/commands/version.sh ./ve/commands/status.sh "
ok "no command calls the removed guards" "$(cd "$REPO/modules" && grep -lE '^[[:space:]]*(authorize|reseller_only)\b' ./*/commands/*.sh ./*/command.sh | wc -l)" 0

echo ""
echo "escalated.test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
