#!/bin/bash

##
##   modules/static/libs/regenerate.sh — static docroot seeding.
##
##   Sourced by load_libs when the module is enabled. Defines
##   regenerate_static_server, called from hooks/regenerate.sh (also
##   reachable via 'sc exec-function regenerate_static_server').
##

## Seed /var/srvctl3/storage/static/<container>/html for every container
## in the cluster: create the directory and, only when index.html is
## missing, a branded placeholder page (setup_index_html, branding
## module) — user-placed content is never overwritten.
## FIXME(v4): iterates the cluster-wide container list, so every host
## seeds docroots for remote containers too — only sensible with shared
## gluster storage; after G4 (gluster removal) scope to local containers.
function regenerate_static_server() {
    local dir
    msg "regenerate static server index files"
    for dir in $(get cluster container_list)
    do
        mkdir -p "/var/srvctl3/storage/static/$dir/html"
        if [[ ! -f "/var/srvctl3/storage/static/$dir/html/index.html" ]]
        then
            setup_index_html "$dir (static)" "/var/srvctl3/storage/static/$dir/html"
        fi
    done
}
