#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function mkrootfs_fedora_install_codepad {
    
    ## run dnf -y install gcc-c++
    
    ## function from containers module
    mkrootfs_fedora_base codepad "mc httpd mod_ssl openssl postfix mailx sendmail unzip rsync dovecot gzip git-core curl python openssl-devel postgresql-devel wget mariadb-server ShellCheck nodejs"
    
    msg "mkrootfs_fedora_install_codepad"
    
    ## this is my own version for rootfs creation
    local install_root
    
    #rootfs_name=codepad
    install_root="$SC_ROOTFS_DIR/codepad"
    
    if [[ ! -d $install_root ]]
    then
        err "Missing directory: $install_root"
        exit
    fi
    
    dir="$install_root"/usr/share/etherpad-lite
    
    run git clone git://github.com/ether/etherpad-lite.git "$dir"
    run mkdir -p "$dir/node_modules"
    run ln -s ../src "$dir/node_modules/ep_etherpad-lite"
    run npm install --prefix "$dir/node_modules/ep_etherpad-lite" --loglevel warn
    
    run git clone git://github.com/spcsser/ep_adminpads "$dir/node_modules/ep_adminpads"
    run npm install --prefix "$dir/node_modules/ep_adminpads" --loglevel warn
    
    run git clone git://github.com/LaKing/ep_codepad "$dir/node_modules/ep_codepad"
    run npm install --prefix "$dir/node_modules/ep_codepad" --loglevel warn
    
    msg "Configuring codepad"
    
    ### increase import filesize limitation
    sed_file "$dir/src/node/db/PadManager.js" '    if(text.length > 100000)' '    if(text.length > 1000000) /* srvctl customization for file import via webAPI*/'
    
    ### The line containing:  return /^(g.[a-zA-Z0-9]{16}\$)?[^$]{1,50}$/.test(padId); .. but mysql is limited to 100 chars, so patch it.
    sed_file "$dir/src/node/db/PadManager.js" '{1,50}$/.test(padId);' '{1,100}$/.test(padId); /* srvctl customization for file import via webAPI*/'
    
    cp "$dir/src/static/custom/js.template" "$dir/src/static/custom/index.js"
    cp "$dir/src/static/custom/css.template" "$dir/src/static/custom/index.css"
    cp "$dir/src/static/custom/js.template" "$dir/src/static/custom/pad.js"
    cp "$dir/src/static/custom/css.template" "$dir/src/static/custom/pad.css"
    cp "$dir/src/static/custom/js.template" "$dir/src/static/custom/timeslider.js"
    cp "$dir/src/static/custom/css.template" "$dir/src/static/custom/timeslider.css"
    
    msg "Create codepad.service"
    
    mkdir -p "$install_root"/lib/systemd/system
    cat > "$install_root/lib/systemd/system/codepad.service" << EOF
## srvctl generated
[Unit]
Description=Codepad, the etherpad-lite based collaborative code editor.
After=syslog.target network.target
After=mariadb.service

[Service]
Type=simple
ExecStartPre=/bin/mysql -u root -e "CREATE DATABASE IF NOT EXISTS codepad"
WorkingDirectory=/usr/share/etherpad-lite
ExecStart=/bin/node /usr/share/etherpad-lite/node_modules/ep_etherpad-lite/node/server.js --settings /etc/codepad/settings.json
User=codepad
Group=codepad

[Install]
WantedBy=multi-user.target

EOF
    
    
    run mkdir -p "$install_root"/var/etherpad-lite
    run rm -rf "$install_root"/usr/share/etherpad-lite/var
    run ln -s /var/etherpad-lite "$install_root"/usr/share/etherpad-lite/var
    run chmod 774 "$install_root"/var/etherpad-lite
    run chroot "$install_root" chown codepad:codepad /var/etherpad-lite
    
    run mkdir -p "$install_root"/var/codepad
    run mkdir -p "$install_root"/etc/codepad
    run mkdir -p "$install_root"/srv/codepad-project
    run chroot "$install_root" chown codepad:codepad /srv/codepad-project
    
    #mkdir -p "$install_root"/var/lib/mysql
    #chroot "$install_root" chown -R mysql:mysql /var/lib/mysql
    #mkdir -p "$install_root"/var/log/mysql
    #chroot "$install_root" chown -R mysql:mysql /var/log/mysql
    
    run mkdir -p "$install_root"/var/codepad
    
    msg "Add gitconfig"
cat > "$install_root"/var/codepad/.gitconfig << EOF
[user]
        email = codepad@$CDN
        name = codepad
[push]
        default = simple
EOF
    
    run chroot "$install_root" chown -R codepad:codepad /var/codepad
    
    echo 'done' > "$dir/node_modules/ep_adminpads/.ep_initialized"
    echo 'done' > "$dir/node_modules/ep_codepad/.ep_initialized"
    echo 'done' > "$dir/node_modules/ep_etherpad-lite/.ep_initialized"
    
    run chroot "$install_root" chown -R codepad:codepad /etc/codepad
    
    msg "create default settings.json"
    
cat > "$install_root"/etc/codepad/settings.json << EOF
{
  "ep_codepad": {
    "theme": "Cobalt",
    "project_path": "/srv/codepad-project",
    "log_path": "/var/codepad/project.log",
    "push_action": "/bin/bash /etc/codepad/push.sh"
  },
  "title": "codepad",
  "favicon": "favicon.ico",
  "ip": "0.0.0.0",
  "port" : 9001,
  "dbType" : "mysql",
  "dbSettings" : {
    "user"    : "root",
    "host"    : "localhost",
    "password": "",
    "database": "codepad"
  },
  "defaultPadText" : "// codepad",
  "requireSession" : false,
  "editOnly" : false,
  "minify" : true,
  "maxAge" : 21600,
  "abiword" : null,
  "requireAuthentication": true,
  "requireAuthorization": false,
  "trustProxy": false,
  "disableIPlogging": true,
  "socketTransportProtocols" : ["xhr-polling", "jsonp-polling", "htmlfile"],
  "loglevel": "INFO",
  "logconfig" :
    { "appenders": [
        { "type": "console"}
      ]
    },
   "users": {
    "admin": {
      "password": "$(new_password)",
      "is_admin": true
    }
  }
}

EOF
    
    msg "Create push.sh"
    cat "$SC_INSTALL_DIR/modules/codepad/codepad-project/push.sh" > "$install_root"/etc/codepad/push.sh
    run chmod 744 "$install_root"/etc/codepad/push.sh
    
    run mkdir -p "$install_root"/etc/systemd/system/multi-user.target.wants/
    run ln -s /usr/lib/systemd/system/postfix.service "$install_root"/etc/systemd/system/multi-user.target.wants/postfix.service
    run ln -s /usr/lib/systemd/system/mariadb.service "$install_root"/etc/systemd/system/multi-user.target.wants/mariadb.service
    run ln -s /usr/lib/systemd/system/codepad.service "$install_root"/etc/systemd/system/multi-user.target.wants/codepad.service
    
    msg "Create sessionkey and apikey"
    date +%s | sha256sum | base64 | head -c 64 > "$install_root"/etc/codepad/SESSIONKEY.txt
    date +%s | sha256sum | base64 | head -c 64 > "$install_root"/etc/codepad/APIKEY.txt
    
    run ln -s /etc/codepad/settings.json "$dir/settings.json"
    run ln -s /etc/codepad/SESSIONKEY.txt "$dir/SESSIONKEY.txt"
    run ln -s /etc/codepad/APIKEY.txt "$dir/APIKEY.txt"
    
    run chroot "$install_root" chmod 666 /usr/share/etherpad-lite/SESSIONKEY.txt
    
    #make /var/codepad/users
    
}

function init_codepad_project { ## Container
    
    local rootfs
    rootfs=''
    
    if [[ ! -z $1 ]]
    then
        rootfs="/srv/$1/rootfs"
    fi
    
    msg "Create sessionkey and apikey"
    date +%s | sha256sum | base64 | head -c 64 > "$rootfs"/etc/codepad/SESSIONKEY.txt
    date +%s | sha256sum | base64 | head -c 64 > "$rootfs"/etc/codepad/APIKEY.txt
    
    msg "Create git repo"
    run mkdir -p "$rootfs"/var/git
    run cd "$rootfs"/var/git
    run git init --bare -q
    run git clone "$rootfs"/var/git "$rootfs"/srv/codepad-project -q
    #&> /dev/null
    
cat > "$rootfs"/srv/codepad-project/.git/config << EOF
[core]
        repositoryformatversion = 0
        filemode = true
        bare = false
        logallrefupdates = true
[remote "origin"]
        url = /var/git
        fetch = +refs/heads/*:refs/remotes/origin/*
[branch "master"]
        remote = origin
        merge = refs/heads/master
EOF
    
cat > "$rootfs"/var/codepad/.gitconfig << EOF
[user]
        email = codepad@$HOSTNAME
        name = codepad
[push]
        default = simple
EOF
    
    run rsync -a "$SC_INSTALL_DIR"/modules/codepad/codepad-project "$rootfs"/srv
    
    msg "npm install"
    # shellcheck disable=SC2091
    $(cd "$rootfs"/srv/codepad-project && npm install >> /dev/null)
    
    cat "$rootfs"/etc/pki/tls/certs/localhost.crt > "$rootfs"/var/codepad/localhost.crt
    cat "$rootfs"/etc/pki/tls/private/localhost.key > "$rootfs"/var/codepad/localhost.key
    
cat > "$rootfs"/etc/codepad/settings.json << EOF
{
  "ep_codepad": {
    "theme": "Cobalt",
    "project_path": "/srv/codepad-project",
    "log_path": "/var/codepad/project.log",
    "push_action": "/bin/bash /etc/codepad/push.sh"
  },
  "title": "codepad",
  "favicon": "favicon.ico",
  "ip": "0.0.0.0",
  "port" : 9001,
  "dbType" : "mysql",
  "dbSettings" : {
    "user"    : "root",
    "host"    : "localhost",
    "password": "",
    "database": "codepad"
  },
  "defaultPadText" : "// codepad",
  "requireSession" : false,
  "editOnly" : false,
  "minify" : true,
  "maxAge" : 21600,
  "abiword" : null,
  "requireAuthentication": true,
  "requireAuthorization": false,
  "trustProxy": false,
  "disableIPlogging": true,
  "socketTransportProtocols" : ["xhr-polling", "jsonp-polling", "htmlfile"],
  "loglevel": "INFO",
  "logconfig" :
    { "appenders": [
        { "type": "console"}
      ]
    },
   "users": {
    "admin": {
      "password": "$(new_password)",
      "is_admin": true
    }
  }
}

EOF
    
    run ln -s "$rootfs"/var/srvctl3/share/containers/"$1"/users "$rootfs"/var/codepad/users
    
    msg "init codepad instance complete"
}