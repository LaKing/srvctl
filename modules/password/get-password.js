#!/bin/node

/*srvctl */

// CLI shim run by new_password (libs/bashlib.sh): prints one password
// from lib.js to stdout. Command-line arguments are ignored.

const password_lib = require('../password/lib.js');
console.log(password_lib.get_password());
