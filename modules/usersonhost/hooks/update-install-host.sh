#!/bin/bash

##
##   modules/usersonhost/hooks/update-install-host.sh — sudo wiring and
##   host user tools.
##
##   Fired by "run_hooks update-install-host" from modules/srvctl/
##   commands/update-install.sh on cluster hosts. Writes the srvctl
##   sudoers drop-in, then installs the interactive tools users expect
##   on a host (vnc, mercurial, mail, firefox, ...); each install is
##   guarded by a /usr/bin binary check so re-runs are cheap no-ops.
##

## srvctl3 sudo functions
sc_install sudo
## FIXME(v4): security review — "ALL ALL=(ALL) NOPASSWD: srvctl.sh *" lets
## every account on the host run srvctl as root with arbitrary arguments;
## srvctl's own authorization (authlib) is the only remaining boundary.
echo "## srvctl v3 sudo file" > /etc/sudoers.d/srvctl
echo "ALL ALL=(ALL) NOPASSWD: $SC_INSTALL_DIR/srvctl.sh *" >> /etc/sudoers.d/srvctl

msg "installing User tools"

## maintenance system tools
#sc_install dnf-plugin-system-upgrade

## vncserver
[[ ! -f /usr/bin/vncserver ]] && sc_install tigervnc-server

## hg
[[ ! -f /usr/bin/hg ]] && sc_install hg

## fdupes
[[ ! -f /usr/bin/fdupes ]] && sc_install fdupes

## mail
[[ ! -f /usr/bin/mailx ]] && sc_install mailx

## ratpoison
[[ ! -f /usr/bin/ratpoison ]] && sc_install ratpoison

## firefox
[[ ! -f /usr/bin/firefox ]] && sc_install firefox

[[ ! -f /usr/bin/shellcheck ]] && sc_install ShellCheck

[[ ! -f /usr/bin/7z ]] && sc_install p7zip-plugins

## template for further tools:
## [[ ! -f ]] && sc_install

## the last guard above evaluates false when the tool is already present;
## return 0 keeps that from becoming the hook's exit status
return 0
