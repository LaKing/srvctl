#!/bin/bash

#[[ $SRVCTL ]] || exit
#[[ $SC_ROOTFS_DIR ]] || exit

function create_codepad_certificate() { #rootfs
    
    local rootfs
    rootfs="$1"
    
    ## Create a certificate
    ssl_password="no_password"
    ssl_days=365
    ssl_key="$rootfs"/var/codepad/localhost.key
    ssl_csr="$rootfs"/var/codepad/localhost.csr
    ssl_org="$rootfs"/var/codepad/localhost.org.pem
    ssl_crt="$rootfs"/var/codepad/localhost.crt
    ssl_config="$rootfs"/var/codepad/localhost-cert-config.txt
    
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
        
        msg "Created certificate $ssl_key $ssl_crt"
        
    fi
    
}

function mkrootfs_fedora_install_codepad {
    
    ## run dnf -y install gcc-c++
    
    msg "mkrootfs_fedora_install_codepad"
    
    ## function from containers module
    mkrootfs_fedora_base codepad "systemd-container httpd mod_ssl gzip git-core curl python openssl-devel postgresql-devel mariadb-server ShellCheck make"
    
    msg "mkrootfs_fedora_install_codepad - base installation complete"
    
    ## this is my own version for rootfs creation
    local rootfs
    
    #rootfs_name=codepad
    rootfs="$SC_ROOTFS_DIR/codepad"
    
    if [[ ! -d $rootfs ]]
    then
        err "Missing directory: $rootfs"
        exit
    fi
    
    msg "create directories"
    
    run mkdir -p "$rootfs"/var/codepad/.ssh
    #run mkdir -p "$rootfs"/etc/codepad
    run mkdir -p "$rootfs"/srv/codepad-project
    run chroot "$rootfs" chown codepad:codepad "$rootfs"/srv/codepad-project
    
    echo '' > "$rootfs"/var/codepad/project.log
    
    
    
    run mkdir -p "$rootfs"/etc/systemd/system/multi-user.target.wants/
    run ln -s /usr/lib/systemd/system/mongod.service "$rootfs"/etc/systemd/system/multi-user.target.wants/mongod.service
    
    create_codepad_certificate "$rootfs"
    
    msg "init git configs"
    
    run mkdir -p "$rootfs"/var/git
    run cd "$rootfs"/var/git
    run git init --bare -q
    run git clone "$rootfs"/var/git "$rootfs"/srv/codepad-project -q
    #&> /dev/null
    
	cat > "$rootfs"/var/codepad/.gitconfig << EOF
[user]
        email = codepad@$CDN
        name = codepad
[push]
        default = simple
EOF
    
    msg "Create default key"
    ## create an access key, however, this should propably differ for each container
    ssh-keygen -b 4096 -f "$rootfs"/var/codepad/.ssh/id_rsa -N '' -C "codepad"
    cat "$rootfs"/var/codepad/.ssh/id_rsa.pub > "$rootfs"/var/codepad/.ssh/authorized_keys
    
    echo "cd /srv/codepad-project" > "$rootfs"/var/codepad/.profile
    echo "mc" >> "$rootfs"/var/codepad/.profile
    
    msg "Create codepad service"
    
cat > "$rootfs"/etc/systemd/system/codepad.service << EOF
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
# Environment variables:
Environment=NODE_ENV=production
[Install]
WantedBy=multi-user.target
EOF
    
    run ln -s /etc/systemd/system/codepad.service "$rootfs"/etc/systemd/system/multi-user.target.wants/codepad.service
    
cat > "$rootfs"/var/codepad/server.js << EOF
#!/bin/node

// to configure our server, we create the ß object now.
if (!global.ß) global.ß = {};

// @DOC To enter debug mode, pass debug as argument to server.js, then ß.DEBUG will be true.
// or uncomment this line
// ß.DEBUG = true;

ß.theme = "cobalt";

require("./boilerplate");

/*
THEMES:

3024-day    ambiance-mobile  blackboard  dracula        elegant       icecoder     liquibyte  mdn-like  neo           paraiso-dark    rubyblue   ssms                     ttcn         xq-light
3024-night  base16-dark      cobalt      duotone-dark   erlang-dark   idea         lucario    midnight  night         paraiso-light   seti       the-matrix               twilight     yeti
abcdef      base16-light     colorforth  duotone-light  gruvbox-dark  isotope      material   monokai   oceanic-next  pastel-on-dark  shadowfox  tomorrow-night-bright    vibrant-ink  zenburn
ambiance    bespin           darcula     eclipse        hopscotch     lesser-dark  mbo        neat      panda-syntax  railscasts      solarized  tomorrow-night-eighties  xq-dark

*/

EOF
    
    run ln -s /usr/local/share/boilerplate/@codepad-modules "$rootfs"/var/codepad/@codepad-modules
    run ln -s /usr/local/share/boilerplate/boilerplate "$rootfs"/var/codepad/boilerplate
    
    #run chroot "$rootfs" chown -R codepad:codepad /etc/codepad
    run chroot "$rootfs" chown -R codepad:codepad /var/codepad
}


function init_codepad_project { ## Container
    
    local C C_uid codepad_uid
    C="$1"
    
    C_uid="$(get container "$C" uid)"
    
    msg "init_codepad_project $C with uid $C_uid"
    
    rm -fr /srv/"$C"/rootfs/var/codepad/.ssh/*
    ssh-keygen -b 4096 -f /srv/"$C"/rootfs/var/codepad/.ssh/id_rsa -N '' -C "codepad@$C $NOW"
    cat /srv/"$C"/rootfs/var/codepad/.ssh/id_rsa.pub > /srv/"$C"/rootfs/var/codepad/.ssh/authorized_keys
    
    codepad_uid=$(( C_uid + 104 ))
    
    run chown -R "$codepad_uid:$codepad_uid" /srv/"$C"/rootfs/var/codepad
    
    run ln -s /var/srvctl3/share/containers/"$C"/users /srv/"$C"/rootfs/var/codepad/users
    
    msg "Codepad @ https://$C:9001"
}
