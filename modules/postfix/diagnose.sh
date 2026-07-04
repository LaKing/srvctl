#!/bin/bash

run openssl s_client -showcerts -connect localhost:465

run systemctl status amavisd.service  --no-pager -n 30