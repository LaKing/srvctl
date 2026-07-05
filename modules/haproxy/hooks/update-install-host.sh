#!/bin/bash

## HAproxy is a reverse Proxy for http / https

##
##   haproxy/hooks/update-install-host.sh — host provisioning.
##
##   Runs on hosts during 'sc update-install'. Installs haproxy, socat
##   (stats socket) and rsyslog; creates /var/haproxy (the certificate
##   directory the generated config binds to); routes haproxy's local2
##   syslog facility to /var/log/haproxy.log; and seeds /var/haproxy with
##   any pre-provisioned /etc/srvctl/cert/<domain>/<domain>.pem.
##
##   Note: /etc/rsyslog.conf is replaced wholesale (stock Fedora content
##   plus the UDP 514 input haproxy logs to) — the heredoc below is
##   unquoted so the "srvctl modification" line embeds $SRVCTL; keep its
##   content byte-identical.
##

msg "Installing HAproxy as the reverse proxy"

sc_install haproxy
sc_install socat
sc_install rsyslog

mkdir -p /var/haproxy

echo 'local2.*        /var/log/haproxy.log' > /etc/rsyslog.d/haproxy.conf

cat > /etc/rsyslog.conf << EOF
# rsyslog configuration file

# For more information see /usr/share/doc/rsyslog-*/rsyslog_conf.html
# or latest version online at http://www.rsyslog.com/doc/rsyslog_conf.html
# If you experience problems, see http://www.rsyslog.com/doc/troubleshoot.html

#### MODULES ####

module(load="imuxsock"           # provides support for local system logging (e.g. via logger command)
       SysSock.Use="off") # Turn off message reception via local log socket;
                          # local messages are retrieved through imjournal now.
module(load="imjournal"             # provides access to the systemd journal
       StateFile="imjournal.state") # File to store the position in the journal
#module(load="imklog") # reads kernel messages (the same are read from journald)
#module(load"immark") # provides --MARK-- message capability

# Provides UDP syslog reception
# for parameters see http://www.rsyslog.com/doc/imudp.html

## srvctl modification $SRVCTL

module(load="imudp") # needs to be done just once
input(type="imudp" port="514")

# Provides TCP syslog reception
# for parameters see http://www.rsyslog.com/doc/imtcp.html
#module(load="imtcp") # needs to be done just once
#input(type="imtcp" port="514")

#### GLOBAL DIRECTIVES ####

# Where to place auxiliary files
global(workDirectory="/var/lib/rsyslog")

# Use default timestamp format
module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat")

# Include all config files in /etc/rsyslog.d/
include(file="/etc/rsyslog.d/*.conf" mode="optional")

#### RULES ####

# Log all kernel messages to the console.
# Logging much else clutters up the screen.
#kern.*                                                 /dev/console

# Log anything (except mail) of level info or higher.
# Don't log private authentication messages!
*.info;mail.none;authpriv.none;cron.none                /var/log/messages

# The authpriv file has restricted access.
authpriv.*                                              /var/log/secure

# Log all the mail messages in one place.
mail.*                                                  -/var/log/maillog


# Log cron stuff
cron.*                                                  /var/log/cron

# Everybody gets emergency messages
*.emerg                                                 :omusrmsg:*

# Save news errors of level crit and higher in a special file.
uucp,news.crit                                          /var/log/spooler

# Save boot messages also to boot.log
local7.*                                                /var/log/boot.log


# ### sample forwarding rule ###
#action(type="omfwd"
# An on-disk queue is created for this action. If the remote host is
# down, messages are spooled to disk and sent when it is up again.
#queue.filename="fwdRule1"       # unique name prefix for spool files
#queue.maxdiskspace="1g"         # 1gb space limit (use as much as possible)
#queue.saveonshutdown="on"       # save messages to disk on shutdown
#queue.type="LinkedList"         # run asynchronously
#action.resumeRetryCount="-1"    # infinite retries if host is down
# Remote Logging (we use TCP for reliable delivery)
# remote_host is: name/ip, e.g. 192.168.0.1, port optional e.g. 10514
#Target="remote_host" Port="XXX" Protocol="tcp")
EOF

run systemctl enable rsyslog
run systemctl restart rsyslog



## Import wildcard and host-specific certificates from /etc/srvctl/cert

for dir in /etc/srvctl/cert/*
do
    ## strip the '/etc/srvctl/cert/' prefix (17 chars) to get the domain;
    ## on an empty dir the unmatched glob fails the -f test harmlessly
    d="${dir:17}"

    if [[ -f $dir/$d.pem ]]
    then
        msg "Import Haproxy certificate $d"
        cat "$dir/$d.pem" > "/var/haproxy/$d.pem"
    fi

done

