#!/bin/bash

## ve pre-init hook: sourced into the MAIN shell on every srvctl invocation
## inside a container (run_hook pre-init). Detects virtualization and
## defaults the rootfs/mounts dirs when /etc/srvctl/*.conf (sourced earlier)
## did not set them — verbatim duplicates of the containers module's
## defaults; inside a VE only set_permissions reads them (-d guarded).

## FIXME(v4): missing the standard "[[ $SRVCTL ]] || exit 10" guard.

## detect virtualization
## FIXME(v4): dead code — nothing in the main shell reads SC_VIRT (other
## consumers re-detect inside condition subshells); it forks on every VE
## invocation, the readonly-with-assignment form masks the command's exit
## status, and the readonly mark makes any later SC_VIRT assignment in this
## shell fatal.
readonly SC_VIRT=$(systemd-detect-virt -c)

## containers dir is /srv - fixed

# shellcheck disable=SC2034
[[ $SC_ROOTFS_DIR ]] || SC_ROOTFS_DIR=/var/srvctl3/rootfs

# shellcheck disable=SC2034
[[ $SC_MOUNTS_DIR ]] || SC_MOUNTS_DIR=/var/srvctl3/mounts
