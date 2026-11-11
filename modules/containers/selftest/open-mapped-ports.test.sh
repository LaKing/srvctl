#!/bin/bash
# lib/open-mapped-ports.sh with systemd-run stubbed as the container's firewall-cmd:
# the container-side ports of the Port= lines, added once, a reload only after a change,
# nothing without an enabled firewalld.
# shellcheck disable=SC2329

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0 fail=0
ok() {
    if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "  FAIL $1: got '$2' want '$3'"
    fi
}

mkdir -p "$tmp/bin" "$tmp/srv/app.example"
## systemd-run -q -M C --pipe --wait CMD...: firewalld state in $tmp/state (up, enabled, off)
cat > "$tmp/bin/systemd-run" << EOF
#!/bin/bash
shift 5
echo "\$*" >> "$tmp/calls"
state="\$(cat "$tmp/state")"
case "\$1 \$2" in
    "firewall-cmd --state") [[ \$state == up ]] ;;
    "systemctl is-enabled") [[ \$state != off ]] ;;
    "firewall-cmd --permanent") case "\$3" in
        --query-port=*) grep -qx "\${3#*=}" "$tmp/open" 2> /dev/null && echo yes || echo no ;;
        --add-port=*) echo "\${3#*=}" >> "$tmp/open" ;;
        esac ;;
esac
EOF
cat > "$tmp/bin/sleep" << 'EOF'
#!/bin/bash
EOF
chmod +x "$tmp/bin/systemd-run" "$tmp/bin/sleep"
cat > "$tmp/srv/app.example/app.example.nspawn" << 'EOF'
[Network]
## 2993 mobile_imaps
Port=tcp:2993:2993
Port=tcp:1465:1465
Port=tcp:2994:2993
Port=udp:5000
EOF

opm() { PATH="$tmp/bin:$PATH" SC_PORTS_SRV="$tmp/srv" SC_PORTS_WAIT=10 bash "$REPO/modules/containers/lib/open-mapped-ports.sh" app.example 2>&1; }

echo up > "$tmp/state"
out="$(opm)"
ok "container-side ports, deduplicated" "$(sort "$tmp/open" | tr '\n' ' ')" "1465/tcp 2993/tcp 5000/udp "
ok "reported" "$out" "[open-mapped-ports] app.example: opened in the container's firewalld: 1465/tcp 2993/tcp 5000/udp"
ok "reloaded" "$(grep -c -- '--reload' "$tmp/calls")" 1

rm -f "$tmp/calls"
ok "second start silent" "$(opm)" ""
ok "no reload without a change" "$(grep -c -- '--reload' "$tmp/calls")" 0

rm -f "$tmp/calls" "$tmp/open"
echo off > "$tmp/state"
ok "no firewalld: nothing" "$(opm; echo $?)" 0
ok "no firewalld: nothing added" "$(grep -c -- '--add-port' "$tmp/calls")" 0

echo enabled > "$tmp/state"
ok "firewalld never up" "$(opm | grep -c 'did not come up')" 1

echo "open-mapped-ports: $pass passed, $fail failed"
((fail == 0))
