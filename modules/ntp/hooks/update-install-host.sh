#!/bin/bash

sc_install ntpsec

run systemctl enable ntpd
run systemctl start ntpd
