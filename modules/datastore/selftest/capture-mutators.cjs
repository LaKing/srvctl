// modules/datastore/selftest/capture-mutators.cjs — v3 REFERENCE capturer for
// the datastore MUTATORS. Requires the live v3 lib.js against $SC_DATASTORE_DIR,
// performs ONE mutation (named in argv), and prints the resulting record/value
// as the FINAL line of stdout (v3 new_container/update_ip emit stray debug/msg
// output first, so the test parses the last non-empty line).
//
//   node capture-mutators.cjs new_user <name>
//   node capture-mutators.cjs new_reseller <name>
//   node capture-mutators.cjs new_container <C> <T> [B]
//   node capture-mutators.cjs update_ip <C>

const lib = require("../lib.js");

const [, , op, a, b, c] = process.argv;
let result;
switch (op) {
  case "new_user":
    lib.new_user(a);
    result = lib.users[a];
    break;
  case "new_reseller":
    lib.new_reseller(a);
    result = lib.users[a];
    break;
  case "new_container":
    lib.new_container(a, b, c);
    result = lib.containers[a];
    break;
  case "update_ip":
    lib.container_update_ip(a);
    result = lib.containers[a].ip;
    break;
  default:
    console.error("unknown op " + op);
    process.exit(2);
}
// Final line = the JSON result (earlier lines may be v3 stray console.log/msg).
process.stdout.write("\n@@RESULT@@" + JSON.stringify(result) + "\n");
