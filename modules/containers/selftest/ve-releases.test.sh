#!/bin/bash
# lib/ve-releases.mjs (sc list-ve-releases) against fake rootfs trees: release parsing by key,
# no symlink escape out of a rootfs, dns/class derivation, oldest-first order.

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

srv="$tmp/srv" ds="$tmp/datastore"
mkdir -p "$ds/containers"

## old.example: F27 layout (no RELEASE_TYPE line), WordPress, DNS points here
r="$srv/old.example/rootfs"
mkdir -p "$r/usr/lib" "$r/etc" "$r/var/www/html" "$r/var/lib/mysql/mysql" "$r/etc/systemd/system/multi-user.target.wants"
printf 'NAME=Fedora\nVERSION="27 (Twenty Seven)"\nID=fedora\nVERSION_ID=27\n' > "$r/usr/lib/os-release"
ln -s ../usr/lib/os-release "$r/etc/os-release"
touch -d 2024-03-01 "$r/var/www/html/wp-config.php"
ln -s /usr/lib/systemd/system/httpd.service "$r/etc/systemd/system/multi-user.target.wants/httpd.service"
echo '{"user":"alice","du":2097152,"dns":{"old.example":{"A":["192.0.2.10"]}}}' > "$ds/containers/old.example.json"

## new.example: F44 layout, a custom unit, DNS points elsewhere
r="$srv/new.example/rootfs"
mkdir -p "$r/usr/lib" "$r/var/www/html" "$r/etc/systemd/system/multi-user.target.wants"
printf 'NAME="Fedora Linux"\nVERSION="44 (Forty Four)"\nRELEASE_TYPE=stable\nID=fedora\nVERSION_ID=44\n' > "$r/usr/lib/os-release"
ln -s /usr/lib/systemd/system/myapp.service "$r/etc/systemd/system/multi-user.target.wants/myapp.service"
echo '{"user":"bob","dns":{"new.example":{"A":["198.51.100.7"]}}}' > "$ds/containers/new.example.json"

## evil.example: absolute os-release symlinks and a /srv escaping to the host; not in the datastore
r="$srv/evil.example/rootfs"
mkdir -p "$r/usr/lib" "$r/etc"
ln -s /etc/os-release "$r/usr/lib/os-release"
ln -s /usr/lib/os-release "$r/etc/os-release"
ln -s /etc "$r/srv"

## old.example is registered with machined while its srvctl-nspawn@ unit is inactive: machinectl wins
mkdir -p "$tmp/bin"
printf '#!/bin/bash\necho "old.example container systemd-nspawn - -"\n' > "$tmp/bin/machinectl"
printf '#!/bin/bash\necho inactive\nexit 3\n' > "$tmp/bin/systemctl"
chmod +x "$tmp/bin/machinectl" "$tmp/bin/systemctl"
PATH="$tmp/bin:$PATH"

out="$(SC_VE_RELEASES_SRV="$srv" SC_DATASTORE_DIR="$ds" SC_HOST_IP=192.0.2.10 /bin/node "$REPO/modules/containers/lib/ve-releases.mjs" tsv)"
ok "exit status" "$?" 0
col() { awk -F'\t' -v ve="$1" -v n="$2" '$1 == ve { print $n }' <<< "$out"; }

ok "F27 release" "$(col old.example 2)" "fedora 27"
ok "F44 release, RELEASE_TYPE line ignored" "$(col new.example 2)" "fedora 44"
ok "absolute symlink does not report the host release" "$(col evil.example 2)" "? ?"
ok "escaping /srv symlink is not walked" "$(col evil.example 6)" "-"
ok "dns here" "$(col old.example 4)" "here"
ok "dns away" "$(col new.example 4)" "away"
ok "no datastore record" "$(col evil.example 4)" "orphan"
ok "last file change" "$(col old.example 6)" "2024-03-01"
ok "size from du" "$(col old.example 7)" "2.0G"
ok "owner" "$(col old.example 8)" "alice"
ok "custom unit listed, baseline httpd not" "$(col new.example 10)" "myapp"
ok "wordpress detected" "$(col old.example 10)" "wp,mysql"
ok "running machine with inactive unit" "$(col old.example 3)" "running,unit:inactive"
ok "wordpress class" "$(col old.example 9)" "wordpress"
ok "stopped and disabled" "$(col new.example 3)" "inactive,disabled"
ok "class is content only, not liveness" "$(col new.example 9)" "custom"
ok "header first, oldest release first" "$(cut -f1 <<< "$out" | tr '\n' ' ')" "VE evil.example old.example new.example "

echo "ve-releases: $pass passed, $fail failed"
((fail == 0))
