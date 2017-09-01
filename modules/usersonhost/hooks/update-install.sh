#!/bin/bash

## srvctl3 sudo functions
sc_install sudo
echo "## srvctl v3 sudo file" > /etc/sudoers.d/srvctl
echo "ALL ALL=(ALL) NOPASSWD: $SC_INSTALL_DIR/srvctl.sh *" >> /etc/sudoers.d/srvctl

msg "installing User tools"

## maintenance system tools
#sc_install dnf-plugin-system-upgrade

## vncserver
[[ ! -f /usr/bin/vncserver ]] && sc_installl tigervnc-server

## hg
[[ ! -f /usr/bin/hg ]] && sc_install hg

## fdupes
[[ ! -f /usr/bin/fdupes ]] && sc_install fdupes

## mail
[[ ! -f /usr/bin/mailx ]] && sc_install mailx

## ratposion
[[ ! -f /usr/bin/ratpoison ]] && sc_install ratpoison

## firefox
[[ ! -f /usr/bin/firefox ]] && sc_install firefox

[[ ! -f /usr/bin/shellcheck ]] && sc_install ShellCheck

[[ ! -f /usr/bin/7z ]] && sc_install p7zip-plugins

## [[ ! -f ]] && sc_install

return 0
