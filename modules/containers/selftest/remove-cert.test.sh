#!/bin/bash
# Exercise both removal commands with host mutations stubbed.
set -eu
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'command rm -rf "$TMP"' EXIT
export SC_DATASTORE_DIR="$TMP/custom datastore"
mkdir -p "$SC_DATASTORE_DIR/cert/wildcard"
for command in remove-ve destroy-ve; do
    (
        SRVCTL=selftest
        ARG=srvctl-removal-selftest.invalid
        hs_only() { :; }
        argument() { :; }
        authorize() { :; }
        owner_only() { :; }
        msg() { :; }
        get() { echo true; }
        container_limits_dropin() { echo "$TMP/dropin"; }
        backup_ve() { :; }
        deleted=false
        del() { deleted=true; }
        run() { return 1; }
        rm() {
            if [[ $* == *"$SC_DATASTORE_DIR/cert/"* ]]; then
                [[ $deleted == true ]]
                command rm "$@"
            fi
        }
        touch "$SC_DATASTORE_DIR/cert/$ARG.pem" "$SC_DATASTORE_DIR/cert/other.pem" "$SC_DATASTORE_DIR/cert/wildcard/base.pem"
        # Source without set -e, matching the command dispatcher; run is a
        # no-op failure so machinectl status never triggers host operations.
        set +e
        source "$REPO/modules/containers/commands/$command.sh"
        set -e
        [[ ! -e "$SC_DATASTORE_DIR/cert/$ARG.pem" ]]
        [[ -f "$SC_DATASTORE_DIR/cert/other.pem" ]]
        [[ -f "$SC_DATASTORE_DIR/cert/wildcard/base.pem" ]]
    )
done
echo 'remove-cert: both commands remove only the container certificate'
