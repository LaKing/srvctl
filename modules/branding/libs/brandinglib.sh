#!/bin/bash

function setup_index_html { ## needs rootfs and some name as argument
    
    ## set default index page
    # shellcheck disable=SC2154
    local _index="$rootfs/var/www/html/index.html"
    local _name="$1"
    
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
            "$(cat "$SC_INSTALL_DIR/modules/logo.svg")"
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
    
    cp "$SC_INSTALL_DIR/modules/favicon.ico" "$rootfs/var/www/html"
    
}
