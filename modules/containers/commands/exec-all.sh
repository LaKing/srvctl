#!/bin/bash

## @@@ exec-all COMMAND
## @en Execute a command on all running containers.
## &en In some cases it might come handy to run a single command on all containers.

sudomize

all_containers_execute "$OPAS"
