#!/bin/bash

## @@@ ls
## @en List files sorted by update
## &en List all files recursive, sorted by last modified date
## &en


run 'find . -type f -exec ls -lt {} +'

