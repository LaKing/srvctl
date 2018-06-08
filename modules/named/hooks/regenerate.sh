#!/bin/bash

msg "Regenerate bind/named DNS server configuration"

namedcfg

restart_named

## if there are several master name servers, each should be restarted here after a regenerate namedcfg locally
