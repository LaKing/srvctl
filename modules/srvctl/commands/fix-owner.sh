#!/bin/bash

## @@@ fix-owner
## @en Set user and group on all content to parent owner.
## &en Useful for transfers of files across systems.
## &en Recursive chown based on parent directory.

# run chown -R $(stat -c '%U' .):$(stat -c '%G' .) .

