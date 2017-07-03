#!/bin/bash

## Pound is a reverse Proxy for http / https

msg "Installing Pound reverse proxy"


mkdir -p /var/www/html

local branding_lib
branding_lib="$SC_INSTALL_DIR/modules/branding/update-install-lib.sh"
source "$branding_lib"

setup_varwwwhtml_error 414 "Request URI too long!"
setup_varwwwhtml_error 500 "An internal server error occurred. Please try apgain later."
setup_varwwwhtml_error 501 "This method may not be used."
setup_varwwwhtml_error 503 "The service is not available. Please try again later."

sc_install Pound

firewalld_add_service http
firewalld_add_service https

run mkdir -p /var/pound
run mkdir -p "$SC_DATASTORE_DIR/cert"

msg "write /etc/pound.cfg"
cat > /etc/pound.cfg << EOF
## srvctl pound.cfg
User "pound"
Group "pound"
Control "/var/lib/pound/pound.cfg"

## Default loglevel is 1
LogFacility local0
LogLevel    2

Alive 1

ListenHTTP

    Address 0.0.0.0
    Port    80

    Err414 "/var/www/html/414.html"
    Err500 "/var/www/html/500.html"
    Err501 "/var/www/html/501.html"
    Err503 "/var/www/html/503.html"

    Include "/var/pound/http.cfg"

End
ListenHTTPS

    Address 0.0.0.0
    Port    443

    xHTTP 1

    Err414 "/var/www/html/414.html"
    Err500 "/var/www/html/500.html"
    Err501 "/var/www/html/501.html"
    Err503 "/var/www/html/503.html"

    Include "/var/pound/cert.cfg"
    Include "/var/pound/https.cfg"

End

## Include the default host here, as a fallback.
# Include "/srv/default-host/pound"

EOF


## Pound logging. By default pound is logging to systemd-journald.
## To work with logs, use rsyslog to export to /var/log/pound

sc_install rsyslog

add_conf /etc/rsyslog.conf 'local0.*                         -/var/log/pound'

run systemctl restart rsyslog.service

create_selfsigned_domain_certificate "$HOSTNAME" "/etc/srvctl/cert/$HOSTNAME"
regenerate_pound_conf
add_service pound

## install pound
