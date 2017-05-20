#!/bin/bash

msg "Diagnose for gluster - the cloud filesystem."
run gluster peer status
run gluster volume status all
