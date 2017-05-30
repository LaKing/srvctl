#!/bin/bash

## srvctl3 sudo functions
sc_install sudo
echo '## srvctl v3 sudo file' > /etc/sudoers.d/srvctl
echo 'ALL ALL=(ALL) NOPASSWD: /usr/share/srvctl/srvctl.sh *' >> /etc/sudoers.d/srvctl

msg "installing User tools"

## maintenance system tools
sc_install dnf-plugin-system-upgrade

## vncserver
sc_install tigervnc-server

## hg
sc_install hg

## fdupes
sc_install fdupes

## mail
sc_install mailx

## ratposion
sc_install ratpoison

## firefox
sc_install firefox

sc_install ShellCheck
