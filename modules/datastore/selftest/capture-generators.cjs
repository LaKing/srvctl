// modules/datastore/selftest/capture-generators.cjs — v3 REFERENCE capturer.
//
// Requires the live v3 modules/datastore/lib.js against the fixture pointed at
// by $SC_DATASTORE_DIR and prints, as JSON on stdout, the RETURN VALUES of the
// pure generators for every fixture container/user + the cluster generators.
// generators.test.mjs runs the v4 port (generators.mjs) over the same fixture
// and asserts equality against this reference.
//
// NOTE: container_resolv_conf is intentionally NOT captured here — v3 reads
// os.hostname() (line 69) and dereferences hosts[HOSTNAME], which is undefined
// unless the test machine happens to be named after a fixture host. resolv_conf
// is covered separately in generators.test.mjs with a controlled ctx.HOSTNAME.

const lib = require("../lib.js");

const CONTAINER_GENS = [
  "container_hosts",
  "container_ethernet",
  "container_ethernet_network",
  "container_quota",
  "container_nspawn",
  "container_br_netdev",
  "container_br_network",
  "container_firewall_commands",
  "container_mx",
  "container_domains",
];
const CLUSTER_GENS = [
  "cluster_etc_hosts",
  "cluster_postfix_relaydomains",
  "cluster_host_keys",
  "cluster_user_list",
  "cluster_container_list",
  "cluster_host_list",
  "cluster_host_ip_list",
];

const out = {};
for (const C of Object.keys(lib.containers)) {
  for (const g of CONTAINER_GENS) out[`${g}:${C}`] = lib[g](C);
}
for (const g of CLUSTER_GENS) out[g] = lib[g]();
for (const u of Object.keys(lib.users)) out[`user_uid:${u}`] = lib.user_uid(u);
// user_container_list reads SC_USER from env (set by the harness).
out["user_container_list"] = lib.user_container_list();

process.stdout.write(JSON.stringify(out));
