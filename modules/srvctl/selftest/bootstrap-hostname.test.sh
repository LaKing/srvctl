#!/bin/bash
# End-to-end first-hostname bootstrap using the real init, module cache,
# datastore initialization/reconciliation, and update-install command. All
# mutable system paths are bind-shadowed inside an unprivileged namespace.

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
TARGET=bootstrap-node.test
pass=0
fail=0

ok() {
    if [[ $2 == "$3" ]]
    then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "  FAIL $1: got '$2' want '$3'"
    fi
}

if ! unshare -Urmu true 2> /dev/null
then
    echo "SKIP bootstrap-hostname.test: unprivileged namespaces unavailable" >&2
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
install="$tmp/install"
mkdir -p "$install/modules/containers/lib" \
    "$install/modules/srvctl/commands" "$install/modules/srvctl/libs" \
    "$install/modules/gluster" "$install/modules/probe/hooks" \
    "$tmp/etc/data" "$tmp/var-local" "$tmp/var-srvctl3" \
    "$tmp/root" "$tmp/var-log" "$tmp/selinux" "$tmp/run"

## Real core and the production pieces involved in this contract.
cp "$REPO/srvctl.sh" "$REPO/init.sh" "$REPO/commonlib.sh" \
    "$REPO/lablib.sh" "$REPO/version" "$install/"
[[ ! -f $REPO/lablib.js ]] || cp "$REPO/lablib.js" "$install/"
cp "$REPO/modules/containers/host-conf.js" \
    "$REPO/modules/containers/module-condition.sh" \
    "$install/modules/containers/"
cp "$REPO/modules/containers/lib/cluster-config.js" \
    "$REPO/modules/containers/lib/cluster-config-cli.js" \
    "$REPO/modules/containers/lib/cluster-config.sh" \
    "$install/modules/containers/lib/"
cp -r "$REPO/modules/datastore" "$install/modules/"
cp "$REPO/modules/srvctl/module-condition.sh" "$install/modules/srvctl/"
cp "$REPO/modules/srvctl/commands/update-install.sh" \
    "$install/modules/srvctl/commands/"
cp "$REPO/modules/srvctl/libs/authlib.sh" "$install/modules/srvctl/libs/"

## Keep the real update-install state machine while replacing package-manager
## work with observable no-ops. The command exits before set_permissions.
printf '%s\n' \
    '#!/bin/bash' \
    'sc_update() { printf "updated\n" > /var/srvctl3/bootstrap-update; }' \
    'sc_install() { :; }' \
    > "$install/modules/srvctl/libs/zz-bootstrap-stubs.sh"
printf '%s\n' '#!/bin/bash' 'echo false' \
    > "$install/modules/gluster/module-condition.sh"

## A post-init probe proves datastore really initialized before command
## dispatch while the future host.conf remained deliberately unsourced.
printf '%s\n' '#!/bin/bash' 'echo true' \
    > "$install/modules/probe/module-condition.sh"
# shellcheck disable=SC2016 # variables belong to the generated probe hook
printf '%s\n' \
    '#!/bin/bash' \
    '[[ $SC_USE_CONTAINERS == true ]] || exit 91' \
    '[[ $SC_USE_DATASTORE == true ]] || exit 92' \
    '[[ -n ${SC_DATASTORE_RW_DIR:-} && -n ${SC_DATASTORE_RO_DIR:-} ]] || exit 93' \
    '[[ ${SC_DATASTORE_DIR:-} == "$SC_DATASTORE_RW_DIR" ]] || exit 94' \
    '[[ ! -v SC_HOSTNAME ]] || exit 95' \
    '[[ ${SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME:-} == bootstrap-node.test ]] || exit 96' \
    '[[ $HOSTNAME == localhost.localdomain ]] || exit 97' \
    '[[ -f $SC_DATASTORE_RW_DIR/.per-entity ]] || exit 98' \
    'printf "datastore=%s future=%s current=%s\n" "$SC_DATASTORE_DIR" "$SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME" "$HOSTNAME" > /var/srvctl3/bootstrap-probe' \
    > "$install/modules/probe/hooks/post-init.sh"

printf '%s\n' \
    '{"production_cluster":{"bootstrap-node.test":{"host_ip":"192.0.2.10","hostnet":40}}}' \
    > "$tmp/etc/clusters.json"
printf 'original-host\n' > "$tmp/hostname"
printf 'SELINUX=enforcing\n' > "$tmp/selinux/config"

live_sum() {
    {
        sha256sum /etc/hostname /etc/selinux/config 2> /dev/null || true
        for path in /etc/srvctl /var/srvctl3
        do
            [[ ! -e $path ]] || find "$path" -type f -exec sha256sum {} + 2> /dev/null
        done
    } | sort | sha256sum
}

before="$(live_sum)"
output="$tmp/output"
set +e
unshare -Urmu bash -s -- "$tmp" "$install" "$TARGET" > "$output" 2>&1 <<'NAMESPACE'
set -e
sandbox="$1"
install="$2"
target="$3"
hostname localhost.localdomain
export HOSTNAME=localhost.localdomain USER=root HOME=/root
mount --bind "$sandbox/etc" /etc/srvctl
mount --bind "$sandbox/var-local" /var/local/srvctl
mount --bind "$sandbox/var-srvctl3" /var/srvctl3
mount --bind "$sandbox/root" /root
mount --bind "$sandbox/var-log" /var/log
mount --bind "$sandbox/run" /run
mount --bind "$sandbox/hostname" /etc/hostname
mount --bind "$sandbox/selinux" /etc/selinux
cd /tmp
bash "$install/srvctl.sh" update-install "$target"
NAMESPACE
rc=$?
set -e
after="$(live_sum)"

ok "update-install keeps reboot-required exit contract" "$rc" 5
ok "persistent hostname written by command branch" "$(<"$tmp/hostname")" "$TARGET"
ok "datastore initialized with validated future host" \
    "$(<"$tmp/var-srvctl3/bootstrap-probe")" \
    "datastore=/var/srvctl3/datastore future=$TARGET current=localhost.localdomain"
ok "package update path reached" "$([[ -f $tmp/var-srvctl3/bootstrap-update ]] && echo yes || echo no)" yes
ok "future projection rendered" \
    "$(bash -c 'source "$1"; printf "%s" "$SC_HOSTNAME"' _ "$tmp/var-srvctl3/host/host.conf")" "$TARGET"
ok "datastore module enabled" \
    "$(grep -qxF 'export SC_USE_DATASTORE=true' "$tmp/root/.srvctl/modules.conf" && echo yes || echo no)" yes
ok "transient module cache cannot survive reboot generation" \
    "$(grep -qxF 'export SC_MODULES_CLUSTERS_SHA256=none' "$tmp/root/.srvctl/modules.conf" && echo yes || echo no)" yes
ok "SELinux write stayed in sandbox" "$(<"$tmp/selinux/config")" SELINUX=disabled
ok "live system paths unchanged" "$after" "$before"

if [[ $rc != 5 ]]
then
    sed -n '1,160p' "$output"
fi
echo "bootstrap-hostname.test: $pass passed, $fail failed"
exit $((fail > 0 ? 1 : 0))
