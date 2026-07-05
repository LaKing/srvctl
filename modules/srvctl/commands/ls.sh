#!/bin/bash

## @@@ ls
## @en List all files recursive, sorted by last modified date
## &en List all files recursive, sorted by last modified date
## &en

##
##   Recursive file listing of the current directory, newest first.
##   The quoted string is word-split by run's unquoted expansion.
##

run 'find . -type f -exec ls -lt {} +'

