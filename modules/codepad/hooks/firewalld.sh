#!/bin/bash

## codepad
firewalld_add_service http9000 tcp 9000
firewalld_add_service https9001 tcp 9001
