#!/bin/bash

##
##   modules/branding/libs/brandinglib.sh — default placeholder page.
##
##   Sourced into the CLI shell via load_libs whenever the module is
##   enabled. Cross-module API: setup_index_html is called by the
##   containers module (add-ve, into /srv/$C/rootfs/var/www/html) and by
##   the static module (regenerate, into the static storage docroot) —
##   keep the function name and its positional-argument contract.
##

## setup_index_html <name> <dir>
## Write a branded placeholder <dir>/index.html (dark page with the
## inlined logo.svg and "<name> @ $HOSTNAME") and copy favicon.ico into
## <dir>. Silently does nothing when <dir> does not exist — callers rely
## on that (static regenerate loops over all containers).
function setup_index_html() { ## name dir

    local _index_html _name
    ## set default index page
    _name="$1"
    _index_html="$2/index.html"

    if [[ -d $2 ]]
    then

## FIXME(v4): the double quotes around the logo substitution and the
## title line sit inside an unquoted heredoc, so literal " characters
## are emitted into the generated HTML of every default index page.
cat > "$_index_html" << EOF
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

        cp "$SC_INSTALL_DIR/modules/branding/favicon.ico" "$2"

    fi

}
