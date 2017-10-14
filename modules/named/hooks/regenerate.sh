#!/bin/bash

msg "Regenerate bind/named DNS server configuration"

namedcfg

restart_named
