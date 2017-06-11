#!/bin/bash

## @en List container status parameters

msg "$HOSTNAME running."
msg "connected users:"
w
msg "Disk usage:"
du -hs /home
du -hs /srv
du -hs /var

