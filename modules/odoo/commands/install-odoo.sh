#!/bin/bash

## @@@ install-odoo
## @en Run scripts that install odoo community and it's basic dependencies.
## &en Install the odoo ERP and CRM system.
## &en Community version, installer by m1r0.

root_only

msg "Starting the odoo installer"

#######################################################################
# Copyright: (C) hisi.hr 2019-2021
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
#######################################################################

## TO DO !!!

# -Implement database backup
# -Implement filestore backup
# -Implement addons backup
# -Test backup

### Changelog

###  v.1.14.1

# Rebase for Odoo 14
# Blocked WKHTML installation due to version mismatch
# Blocked M$Fonts for rebase

# Testing:
#f<32# dnf groupinstall @development-tools @development-libraries
#f=32# dnf groupinstall "Development Tools" "Development Libraries"

# Added:
# dnf install python3-PyPDF2
# dnf install make automake gcc gcc-c++ kernel-devel

# Removed:
#missing# nodejs-less

### v1.0.6

# +Reorganized script for core version 12.0

# v1.0.4

# +Added OCA addons git
# +Created addons/symlink to replace /srv/odoo10-core

# v1.0.2

# +Upgrade WKHTML to 0.12.5

# v1.0.0

# +Tested installation successfully
# +Clean script comments

# v0.0.5

# +Reorder services startup
# +Fix database role creation

# v0.0.4

# +Set user check for reinstall
# +Configured VE ssl.conf for HTTPS

# V0.0.3

# +Upgrading PIP as --user
# +Added Microsot Fonts and services

# v0.0.2

# +Configured automaticly database templates to UTF-8
# +Added system startup services and software configurations

# v0.0.1

# +Added GNU LGPL license
# +Configured software stack
# +Prepared automated installation

#######################################################################
# Stack installation for Fedora linux
#######################################################################
# Version:1.14.1
# Fedora Linux  https://getfedora.org
# PostgreSQL    https://postgresql.org/
# Apache        https://httpd.apache.org/
# Node.js       https://nodejs.org/en/
# Python        https://www.python.org/
# Wkhtml	https://wkhtmltopdf.org/
# Odoo 		https://odoo-community.org/
#######################################################################

### Colorize
WARNING="$(tput setaf 1)WARNING$(tput sgr0)"

### Root required
if [[ $USER != "root" ]];
then
    echo "* $WARNING: $(tput setaf 3)This script must be run as root!$(tput sgr0)"
    exit 1
fi

### Error Trap
tempfiles=( )
cleanup() {
    rm -f "${tempfiles[@]}"
}
trap cleanup 0

error() {
    local parent_lineno="$1"
    local message="$2"
    local code="${3:-1}"
    if [[ -n "$message" ]] ; then
        echo "Error on or near line ${parent_lineno}: ${message}; exiting
        with status ${code}"
    else
        echo "Error on or near line ${parent_lineno}; exiting with status
        ${code}"
    fi
    exit "${code}"
}

### Error exit
set -e

clear

#--------------------------------------------------
### System locale setup
#--------------------------------------------------
export LANGUAGE="hr_HR.UTF-8"
export LANG="hr_HR.UTF-8"
export LC_ALL="hr_HR.UTF-8"

#--------------------------------------------------
### Install packages
#--------------------------------------------------
echo -e "$(tput setaf 3)*$(tput sgr0) $(tput setaf 2)Preparing system for installation$(tput sgr0)"
echo -e "* $(tput setaf 2)Installing dependencies$(tput sgr0)"
dnf update -y
dnf install gcc libxml2-devel openldap-devel libxslt-devel node npm git libXrender libpng15 libjpeg-turbo libjpeg-devel libXext freetype-devel xorg-x11-fonts-Type1 xorg-x11-fonts-75dpi postgresql-server postgresql-devel postgresql-contrib python3-virtualenv cabextract python3-gevent automake gcc gcc-c++ kernel-devel -y >/dev/null 2>&1;
dnf groupinstall "Development Tools" "Development Libraries" -y >/dev/null 2>&1;
npm install -g less less-plugin-clean-css >/dev/null 2>&1;
#if [ -f /usr/local/bin/wkhtmltopdf ]
#then
#echo -e "* $WARNING: $(tput setaf 1)Print services present$(tput sgr0)"
#else
#echo -e "* $(tput setaf 2)Download and install Print services"
#rpm -ivh https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox-0.12.5-1.centos7.x86_64.rpm
#ln -s /usr/local/bin/wkhtmltopdf /usr/bin
#ln -s /usr/local/bin/wkhtmltoimage /usr/bin
#echo -e "* $(tput setaf 2)Download and install Microsoft system fonts$(tput sgr0)"
#rpm -ivh https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
#fi

#--------------------------------------------------
### Create user
#--------------------------------------------------
if [ -f "/srv/odoo/.bashrc" ]
then
    echo -e "* $WARNING: $(tput setaf 3)System user present$(tput sgr0)"
else
    echo -e "* $(tput setaf 2)Create system user$(tput sgr0)"
    useradd -m -U -r -d /srv/odoo -s /bin/bash odoo
fi

#--------------------------------------------------
# Install database server
#--------------------------------------------------
if [ -f /var/lib/pgsql/data/pg_hba.conf ]
then
    echo -e "* $WARNING: $(tput setaf 3)Database present$(tput sgr0)"
else
    echo -e "* $(tput setaf 2)Initialise database$(tput sgr0)";
    postgresql-setup --initdb --unit postgresql #&> /dev/null
    sed -i "/^host/s/ident/md5/g" /var/lib/pgsql/data/pg_hba.conf
    echo -e "* $(tput setaf 2)Starting database$(tput sgr0)";
    systemctl enable postgresql.service
    systemctl start postgresql.service
    echo -e "* $(tput setaf 2)Configuring database$(tput sgr0)";
su - postgres -c "psql -d postgres -U postgres" <<'EOF'
update pg_database set encoding = 6, datcollate = 'hr_HR.UTF-8', datctype = 'hr_HR.UTF-8' where datname = 'template0';
update pg_database set encoding = 6, datcollate = 'hr_HR.UTF-8', datctype = 'hr_HR.UTF-8' where datname = 'template1';
create role odoo with login createdb;
EOF
fi

#--------------------------------------------------
### Creating directory structure
#--------------------------------------------------
if [ -d /srv/odoo/odoo14 ]
then
    echo -e "* $WARNING: $(tput setaf 3)Installation directory structure present$(tput sgr0)"
else
    echo -e "* $(tput setaf 2)Pulling installation$(tput sgr0)"
    su - odoo -c "git clone https://github.com/OCA/OCB.git --depth 1 --branch 14.0 --single-branch /srv/odoo/odoo14"
    
    ##### START MODULES SETUP #####
    
    ### Addons symlink and system structure
    echo -e "* $(tput setaf 2)Installing addons$(tput sgr0)"
    mkdir /srv/odoo/addons
    mkdir /srv/odoo/addons/symlink
    mkdir /srv/odoo/addons/OCA
    chown -R odoo:odoo /srv/*
    
    ### OCA - git pull addons
    #su - odoo -c "git clone https://github.com/OCA/web.git --depth 1 --branch 12.0 --single-branch /srv/odoo/addons/OCA/web"
    #su - odoo -c "git clone https://github.com/OCA/website.git --depth 1 --branch 12.0 --single-branch /srv/odoo/addons/OCA/website"
    #su - odoo -c "git clone https://github.com/OCA/social.git --depth 1 --branch 12.0 --single-branch /srv/odoo/addons/OCA/social"
    #su - odoo -c "git clone https://github.com/OCA/l10n-croatia.git --depth 1 --branch 12.0 --single-branch /srv/odoo/addons/OCA/l10n-croatia"
    #su - odoo -c "git clone https://github.com/OCA/l10n-germany.git --depth 1 --branch 12.0 --single-branch /srv/odoo/addons/OCA/l10n-germany"
    
    ### OCA/web
    #su - odoo -c "ln -s /srv/odoo/addons/OCA/web/web_responsive /srv/odoo/addons/symlink/"
    #su - odoo -c "ln -s /srv/odoo/addons/OCA/web/web_notify /srv/odoo/addons/symlink/"
    
    ### OCA/website
    #su - odoo -c "ln -s /srv/odoo/addons/OCA/website/website_cookie_notice /srv/odoo/addons/symlink/"
    #su - odoo -c "ln -s /srv/odoo/addons/OCA/website/website_legal_page /srv/odoo/addons/symlink/"
    #su - odoo -c "ln -s /srv/odoo/addons/OCA/website/website_odoo_debranding /srv/odoo/addons/symlink/"
    
    ### OCA/social
    #su - odoo -c "ln -s /srv/odoo/addons/OCA/social/mail_debrand /srv/odoo/addons/symlink/"
    
    ### OCA/l10n-croatia
    
    ### OCA/l10n-germany
    
    ##### END MODULES SETUP #####
fi

#--------------------------------------------------
### Configuration
#--------------------------------------------------
echo -e "* $(tput setaf 2)Configure installation$(tput sgr0)"
cat > /srv/odoo/odoo14.conf << EOF
[options]
; This is the password that allows database operations:
; admin_passwd = admin
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = /srv/odoo/odoo14/addons,/srv/odoo/addons/symlink
xmlrpc_port = 8069
longpolling_port = 8072
xmlrpc_interface = 127.0.0.1
netrpc_interface = 127.0.0.1
proxy_mode = True
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
max_cron_threads = 1
workers = 5
# DB filtering for multi-site instances
#dbfilter=^%h$
EOF

#--------------------------------------------------
### Setup virtualenv
#--------------------------------------------------
echo -e "* $(tput setaf 2)Setup virtual enviroment$(tput sgr0)"
if [ ! -d /srv/venv ]
then
    mkdir /srv/venv
    chown -R odoo:odoo /srv/*
    su - odoo -c "python3 -m venv /srv/venv $1;
$1 source /srv/venv/bin/activate;
python3 -m pip install --upgrade pip;
#pip install --user --upgrade pip;
pip3 install wheel;
pip3 install phonenumbers;
pip3 install PyPDF2;
pip3 install passlib
pip3 install -r /srv/odoo/odoo14/requirements.txt;
    deactivate"
fi

#--------------------------------------------------
### Setup HTTPS
#--------------------------------------------------
if [ -f /var/www/html/favicon.ico ]
then
    rm /var/www/html/favicon.ico
    rm /var/www/html/index.html
else
    echo " " > /var/www/html/index.html
fi
if [ -f /etc/httpd/conf.d/ssl.conf.org ]
then
    echo -e "* $WARNING: $(tput setaf 3)HTTPS present$(tput sgr0)"
else
    echo -e "* $(tput setaf 2)Installing HTTPS$(tput sgr0)"
    cp /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.org
    sed -i -e '218d' /etc/httpd/conf.d/ssl.conf
cat >> /etc/httpd/conf.d/ssl.conf <<EOF
ProxyRequests Off
ProxyPreserveHost On
ProxyPass /longpolling/        http://localhost:8072/longpolling/ retry=0
ProxyPassReverse /longpolling/	http://localhost:8072/longpolling/ retry=0
ProxyPass /                    http://localhost:8069/ retry=0
ProxyPassReverse /             http://localhost:8069/ retry=0

</VirtualHost>
EOF
fi

#--------------------------------------------------
### Setup system service
#--------------------------------------------------
echo -e "* $(tput setaf 2)Installing systemd services$(tput sgr0)"
cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo14
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo14
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/srv/venv/bin/python3 /srv/odoo/odoo14/odoo-bin -c /srv/odoo/odoo14.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

#--------------------------------------------------
### Restart server
#--------------------------------------------------
echo -e "* $(tput setaf 2)Restarting stack services$(tput sgr0)"
systemctl enable postgresql
systemctl enable odoo
systemctl enable httpd

systemctl stop httpd
systemctl stop odoo
systemctl stop postgresql

systemctl restart postgresql
systemctl restart odoo
systemctl restart httpd

trap 'error ${LINENO}' ERR

echo -e "* $(tput setaf 2)System succsesfully installed and services started!$(tput sgr0)"