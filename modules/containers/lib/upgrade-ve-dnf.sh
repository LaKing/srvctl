#!/bin/bash

## Runs INSIDE a throwaway nspawn of the stopped container, as its root:
## 'systemd-nspawn ... bash -c "<this>" upgrade-ve-dnf FROM TO', from upgrade_ve_upgrade
## (libs/upgradelib.sh). Not on stdin: dnf or a scriptlet reading it would eat the rest.
## No systemd runs there; SYSTEMD_OFFLINE=1 is set by the caller.

from="$1" to="$2"

## the new release's signing key first; a third-party repo without a build for it is skipped, not fatal
dnf -y upgrade --refresh fedora-gpg-keys
dnf -y --releasever="$to" --setopt=skip_if_unavailable=True distro-sync --allowerasing || exit 1

## Fedora's unversioned nodejs became nodejs<major> (F44: nodejs22). distro-sync keeps the old
## build, which no repo updates any more (seen on r2: mindtalk.hu, nktrust.ch). Same major, so
## the same ABI: native modules stay valid. One transaction: both sets own the same files.
mapfile -t old < <(rpm -qa --qf '%{NAME} %{RELEASE}\n' 'nodejs*' | awk -v rel="fc$to" '$1 ~ /^nodejs(-|$)/ && $2 !~ rel "$" {print $1}')
if ((${#old[@]}))
then
    major="$(node -p 'process.versions.node.split(".")[0]')"
    if [[ $major ]] && dnf -y "do" --action=remove "${old[@]}" --action=install "${old[@]/#nodejs/nodejs$major}"
    then echo "== nodejs moved to nodejs$major: $(node --version)"
    else echo "== NOTE: the old nodejs stays, nodejs$major did not install"
    fi
fi

echo "== packages still built for fedora $from: $(rpm -qa --qf '%{RELEASE}\n' | grep -c "fc$from\$")"
