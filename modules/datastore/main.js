#!/bin/node

/*srvctl */
//
// v4 CUTOVER SHIM. The datastore verb API is now implemented in main.mjs
// (ESM, on the pure v4 modules derive/generators/mutators). This CommonJS
// entry stays so bashlib.sh's `/bin/node .../main.js` and the verb-golden
// harness keep working unchanged. The v3 CommonJS dispatcher + lib.js logic
// is preserved in git history (pre-cutover commit) and lib.js remains for the
// selftest --record paths.

const path = require("node:path");
const { pathToFileURL } = require("node:url");
import(pathToFileURL(path.join(__dirname, "main.mjs")).href);
