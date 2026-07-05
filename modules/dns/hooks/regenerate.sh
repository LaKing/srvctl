#!/bin/bash

##
##   modules/dns/hooks/regenerate.sh — refresh public-DNS data.
##
##   Runs via 'run_hook regenerate' from 'sc regenerate', from
##   regenerate_all_hosts (modules/containers/libs/regenlib.sh), and
##   after add-ve / add-ve-user / add-network-ve / add-codepad. Calls
##   dns_scan (libs/bashlib.sh), which runs dns-scan.js synchronously
##   over every domain of every container and stores the results under
##   containers[name].dns in the datastore containers.json (consumed by
##   the letsencrypt module). A nonzero exit from the scanner aborts the
##   whole srvctl run via exif in run_hook.
##

## FIXME(v4): medium — the scan runs synchronously inside every regenerate
## (and thus inside add-ve and friends); with many domains the resolver
## timeouts make container creation noticeably slower for no per-container
## benefit. Candidate for a timer or post-regenerate background job in v4.
dns_scan
