#!/bin/bash

##
##   mkrootfs_fedora_install_codepad — build the codepad template rootfs
##   ($SC_ROOTFS_DIR/codepad) that every codepad container is created
##   from. Installs the package set via mkrootfs_fedora_base (containers
##   module), then adds the codepad home (/var/codepad: keys, cert,
##   server.js stub, .profile, .gitconfig), a bare git repo (/var/git)
##   with a working clone in /srv/codepad-project, the codepad.service
##   unit, and symlinks to the out-of-repo boilerplate application.
##   Used only by the regenerate_rootfs hook ('sc regenerate rootfs').
##   gcc-c++ for native node builds is installed on the host separately
##   (hooks/update-install-host.sh).
##

function mkrootfs_fedora_install_codepad {

    msg "mkrootfs_fedora_install_codepad"

    ## function from containers module
    mkrootfs_fedora_base codepad "systemd-container httpd mod_ssl gzip git-core curl python openssl-devel postgresql-devel mariadb-server ShellCheck make"

    msg "mkrootfs_fedora_install_codepad - base installation complete"

    ## this is my own version for rootfs creation
    local rootfs

    rootfs="$SC_ROOTFS_DIR/codepad"

    if [[ ! -d $rootfs ]]
    then
        ## mkrootfs_fedora_base removes the directory when its dnf
        ## bootstrap fails; nothing to install into.
        err "Missing directory: $rootfs"
        ## bugfix(v4-polish): was a bare 'exit', which inherited status 0
        ## from err — 'sc regenerate rootfs' reported success on a failed
        ## codepad template build.
        exit 1
    fi

    msg "create directories"

    run mkdir -p "$rootfs"/var/codepad/.ssh
    run mkdir -p "$rootfs"/srv/codepad-project
    ## FIXME(v4): host-absolute path inside the chroot (doubles to
    ## $rootfs$rootfs/srv/codepad-project), so this chown always fails
    ## (eyif warning only) and the template dir stays root-owned.
    run chroot "$rootfs" chown codepad:codepad "$rootfs"/srv/codepad-project

    ## FIXME(v4): single quotes without -e write a literal \n into project.log
    echo '# Init\n' > "$rootfs"/var/codepad/project.log

    run mkdir -p "$rootfs"/etc/systemd/system/multi-user.target.wants/
    ## FIXME(v4): dangling symlink — no mongodb package is in the install
    ## list above; the unit fails to load at every container boot.
    run ln -s /usr/lib/systemd/system/mongod.service "$rootfs"/etc/systemd/system/multi-user.target.wants/mongod.service

    create_codepad_certificate "$rootfs"

    msg "init git configs"

    run mkdir -p "$rootfs"/var/git
    ## FIXME(v4): changes the srvctl process CWD and never restores it;
    ## every later hook in this run executes from inside the template.
    run cd "$rootfs"/var/git
    run git init --bare -q
    ## FIXME(v4): bakes the host template path as the clone's origin URL
    ## in every container's /srv/codepad-project/.git/config; in-container
    ## push/pull to origin always fails (intended remote is /var/git).
    run git clone "$rootfs"/var/git "$rootfs"/srv/codepad-project -q

    ## FIXME(v4): $CDN is defined nowhere in the repo or example-conf
    ## (only in live host config, if at all) — a bare value yields the
    ## malformed git identity 'codepad@'.
    cat > "$rootfs"/var/codepad/.gitconfig << EOF
[user]
        email = codepad@$CDN
        name = codepad
[push]
        default = simple
EOF

    msg "Create default key"
    ## create an access key, however, this should propably differ for each container
    ssh-keygen -t ecdsa -f "$rootfs"/var/codepad/.ssh/id_ecdsa -N '' -C "codepad"
    cat "$rootfs"/var/codepad/.ssh/id_ecdsa.pub > "$rootfs"/var/codepad/.ssh/authorized_keys

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

    ## server.js stub: the boilerplate app (bind-mounted from the host,
    ## not in this repo) depends on the global ß object and its theme
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

    run chroot "$rootfs" chown -R codepad:codepad /var/codepad
}
