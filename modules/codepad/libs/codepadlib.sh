#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function create_codepad_certificate() { #install_root
    
    local install_root
    install_root="$1"
    
    ## Create a certificate
    ssl_password="no_password"
    ssl_days=365
    ssl_key="$install_root"/var/codepad/localhost.key
    ssl_csr="$install_root"/var/codepad/localhost.csr
    ssl_org="$install_root"/var/codepad/localhost.org.pem
    ssl_crt="$install_root"/var/codepad/localhost.crt
    ssl_config="$install_root"/var/codepad/localhost-cert-config.txt
    
    if [[ ! -f "$ssl_key" ]] || [[ ! -f "$ssl_crt" ]]
    then
        
cat  <<EOF>> "$ssl_config"

        RANDFILE               = /tmp/ssl_random

        [ req ]
        prompt                 = no
        string_mask            = utf8only
        default_bits           = 2048
        default_keyfile        = keyfile.pem
        distinguished_name     = req_distinguished_name

        req_extensions         = v3_req

        output_password        = no_password

        [ req_distinguished_name ]
        CN                     = $HOSTNAME
        emailAddress           = webmaster@$HOSTNAME

        [ v3_req ]
        basicConstraints = critical,CA:FALSE
        keyUsage = keyEncipherment, dataEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt_names
        [alt_names]
        DNS.1 = $HOSTNAME
        DNS.2 = *.$HOSTNAME

EOF
        
        
        
        ## Generate a Private Key
        openssl genrsa -des3 -passout "pass:$ssl_password" -out "$ssl_key" 2048 #2> /dev/null
        
        ## Generate a CSR (Certificate Signing Request)
        openssl req -new -passin "pass:$ssl_password" -passout "pass:$ssl_password" -key "$ssl_key" -out "$ssl_csr" -days "$ssl_days" -config "$ssl_config" #2> /dev/null
        
        ## Remove Passphrase from Key
        cp "$ssl_key" "$ssl_org"
        openssl rsa -passin "pass:$ssl_password" -in "$ssl_org" -out "$ssl_key" #2> /dev/null
        
        ## Self-Sign Certificate
        openssl x509 -req -days "$ssl_days" -passin "pass:$ssl_password" -extensions v3_req -in "$ssl_csr" -signkey "$ssl_key" -out "$ssl_crt" #2> /dev/null
        
        chmod 600 "$ssl_key"
        chmod 644 "$ssl_crt"
        
        msg "Created certificate $ssl_key $ssl_cert"
        
    fi
    
}

function mkrootfs_fedora_install_codepad {
    
    ## run dnf -y install gcc-c++
    
    msg "mkrootfs_fedora_install_codepad"
    
    ## function from containers module
    mkrootfs_fedora_base codepad "systemd-container httpd mod_ssl gzip git-core curl python openssl-devel postgresql-devel mariadb-server ShellCheck mongodb mongodb-server"
    
    msg "mkrootfs_fedora_install_codepad - complete"
    
    ## this is my own version for rootfs creation
    local install_root home
    
    #rootfs_name=codepad
    install_root="$SC_ROOTFS_DIR/codepad"
    
    if [[ ! -d $install_root ]]
    then
        err "Missing directory: $install_root"
        exit
    fi
    
    msg "create directories"
    
    run mkdir -p "$install_root"/var/codepad/.ssh
    run mkdir -p "$install_root"/etc/codepad
    run mkdir -p "$install_root"/srv/codepad-project
    run chroot "$install_root" chown codepad:codepad "$install_root"/srv/codepad-project
    
    echo '' > "$install_root"/var/codepad/project.log
    
    firewalld_offline_add_service https9001 tcp 9001
    
    run mkdir -p "$install_root"/etc/systemd/system/multi-user.target.wants/
    run ln -s /usr/lib/systemd/system/mongod.service "$install_root"/etc/systemd/system/multi-user.target.wants/mongod.service
    
    create_codepad_certificate "$install_root"
    
    msg "init git configs"
    
    run mkdir -p "$install_root"/var/git
    run cd "$install_root"/var/git
    run git init --bare -q
    run git clone "$install_root"/var/git "$install_root"/srv/codepad-project -q
    #&> /dev/null
    
	cat > "$install_root"/var/codepad/.gitconfig << EOF
[user]
        email = codepad@$CDN
        name = codepad
[push]
        default = simple
EOF
    
    msg "Create default key"
    ## create an access key, however, this should propably differ for each container
    ssh-keygen -b 4096 -f "$install_root"/var/codepad/.ssh/id_rsa -N '' -C "codepad"
    cat "$install_root"/var/codepad/.ssh/id_rsa.pub > "$install_root"/var/codepad/.ssh/authorized_keys
    
    echo "cd /srv/codepad-project" > "$install_root"/var/codepad/.profile
    echo "mc" >> "$install_root"/var/codepad/.profile
    
    msg "Create codepad service"
    
cat > "$install_root/etc/systemd/system/codepad.service" << EOF
## srvctl generated
[Unit]
Description=Codepad, the collaborative code editor
After=syslog.target network.target
[Service]
PermissionsStartOnly=true
Type=simple
WorkingDirectory=/var/codepad
#ExecStartPre=/usr/sbin/setcap cap_net_bind_service=+ep /usr/bin/node
ExecStart=/bin/node /var/codepad/server.js
User=codepad
Group=codepad
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    
    run ln -s /etc/systemd/system/codepad.service "$install_root"/etc/systemd/system/multi-user.target.wants/codepad.service
    
    cat /var/codepad/boilerplate/scripts/server.js > "$install_root"/var/codepad/server.js
    
    
    run chroot "$install_root" chown -R codepad:codepad /etc/codepad
    run chroot "$install_root" chown -R codepad:codepad /var/codepad
}


function init_codepad_project { ## Container
    
    local C
    C="$1"
    
    msg "init_codepad_project $C"
    
    rm -fr /srv/"$C"/rootfs/var/codepad/.ssh/*
    ssh-keygen -b 4096 -f /srv/"$C"/rootfs/var/codepad/.ssh/id_rsa -N '' -C "codepad@$C $NOW"
    cat /srv/"$C"/rootfs/var/codepad/.ssh/id_rsa.pub > /srv/"$C"/rootfs/var/codepad/.ssh/authorized_keys
    run chown -R 104:104 /srv/"$C"/rootfs/var/codepad
    
    run ln -s /var/srvctl3/share/containers/"$C"/users /srv/"$C"/rootfs/var/codepad/users
    
    msg "Codepad @ https://$C:9001"
}
