#!/bin/bash

##
##   modules/ftp/hooks/update-install-host.sh — install the FTP daemon.
##
##   Fired by "run_hooks update-install-host" during "sc update-install"
##   on a host. Installs the vsftpd package (sc_install, srvctl module's
##   fedoralib.sh: dnf -y -q install); a no-op when already installed.
##   dnf's exit status propagates as the hook's return value.
##

## FIXME(v4): vsftpd is installed but never configured, enabled or started —
## the module opens port 21 (hooks/firewalld.sh) yet delivers no running FTP
## service; documentation.md claims it "installs and configures vsftpd".
## FIXME(v4): a transient dnf/repo failure here aborts the entire
## "sc update-install" run via run_hook's exif, for a nonessential package.
sc_install vsftpd
