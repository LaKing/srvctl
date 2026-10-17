#!/bin/bash

##
##   modules/opendkim/hooks/update-install-host.sh — install opendkim.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh). Installs the opendkim
##   and opendkim-tools packages, writes /etc/opendkim.conf (sign+verify
##   milter on 127.0.0.1:8891, consumed by the postfix module's host
##   main.cf), and enables/starts opendkim.service via add_service. The
##   key and table files the config points at under /var/opendkim are
##   produced later by the regenerate hook (libs/opendkimlib.sh).
##

msg "Install opendkim, to sign e-mails."

sc_install opendkim
sc_install opendkim-tools

## Unquoted heredoc on purpose: $SRVCTL expands into the header comment
## of the generated file. Overwrites /etc/opendkim.conf unconditionally.
cat > /etc/opendkim.conf << EOF
#### srvctl $SRVCTL tuned opendkim.conf

## CONFIGURATION OPTIONS
PidFile        /var/run/opendkim/opendkim.pid

##  Selects operating modes. Valid modes are s (sign) and v (verify). Default is v.
Mode        vs


Syslog        yes
SyslogSuccess        yes
LogWhy        yes
UserID        opendkim:opendkim
Socket        inet:8891@127.0.0.1
Umask        002

SendReports        yes
# ReportAddress        "Example.com Postmaster" <postmaster@example.com>

SoftwareHeader        yes

## SIGNING OPTIONS
Canonicalization        relaxed/relaxed

Selector        default
MinimumKeyBits        1024

KeyTable        /var/opendkim/KeyTable
SigningTable        refile:/var/opendkim/SigningTable
ExternalIgnoreList        refile:/var/opendkim/TrustedHosts
InternalHosts        refile:/var/opendkim/TrustedHosts

EOF

#regenerate_opendkim
## FIXME(v4): low — regenerate_opendkim above is commented out, but
## add_service below enables and restarts the daemon while the
## /var/opendkim/{KeyTable,SigningTable,TrustedHosts} files referenced by
## /etc/opendkim.conf do not exist yet on a fresh host; opendkim.service
## fails to start until the first 'sc regenerate', and outgoing mail is
## meanwhile unsigned (postfix milter_default_action accept).

add_service opendkim
