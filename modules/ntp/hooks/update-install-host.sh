#!/bin/bash

sc_install ntp

run systemctl enable ntpd
run systemctl start ntpd
