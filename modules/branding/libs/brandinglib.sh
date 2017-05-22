#!/bin/bash

function setup_index_html { ## name rootfs
    
    local _index _name rootfs
    ## set default index page
    # shellcheck disable=SC2154
    _name="$1"
    _rootfs="$2"
    _index="$rootfs/var/www/html/index.html"
    
    
cat > "$_index" << EOF
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>$_name</title>
  </head>
<body style="background-color:#333;">
    <div id="header" style="background-color:#222;">
        <p align="center">
            "$(cat "$SC_INSTALL_DIR/modules/branding/logo.svg")"
        </p>
    </div>
        <p align="center">
                <font style="margin-left: auto; margin-right: auto; color: #AAA" size="6px" face="Arial">
                "$_name @ $HOSTNAME"
            </font>
        </p>
</body>
</html>
EOF
    
    cp "$SC_INSTALL_DIR/modules/branding/favicon.ico" "$_rootfs/var/www/html"
    
}
