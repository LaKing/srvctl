// modules/datastore/selftest/derive.test.mjs — snapshot test for the pure
// datastore derivations (derive.mjs) against hand-computed v3 expected values.
// Run:  node modules/datastore/selftest/derive.test.mjs   (exit != 0 on fail)

import assert from "node:assert/strict";
import { derivations } from "../lib/derive.mjs";

const ctx = {
  users: {
    root: { user_id: 0, uid: 0 },
    a: { user_id: 1, uid: 1001, reseller_id: 1 },
    b: { user_id: 2, uid: 1002, reseller: "a" },
  },
  hosts: {
    node1: { hostnet: 20, host_ip: "10.16.20.1" },
    node2: { hostnet: 21, host_ip: "10.16.21.1" },
  },
  containers: {
    "site.example.com": { user: "a", ip: "10.20.1.5" },
    custom: { user: "b", bridge: "br-x", ip: "10.20.2.6" },
    explicit: {
      user: "a", ip: "10.20.1.7", br: "br-lo", gateway: "10.20.1.254",
      interface: "eth9", http_port: 8080, https_port: 8443,
    },
    one92: { user: "a", ip: "192.168.5.9" },
    one72: { user: "a", ip: "172.16.4.8" },
    noip: { user: "a" }, // custom-bridge-to-be, no ip yet
  },
  SC_HOSTNET: 20,
  HOSTNAME: "node1",
  hasLocalRootfs: () => false, // deterministic: no container rootfs present here
};

const d = derivations(ctx);
let passed = 0;
const failures = [];
function eq(label, got, want) {
  try {
    assert.deepEqual(got, want);
    passed++;
  } catch {
    failures.push(`${label}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
  }
}

// site.example.com (ip 10.20.1.5, user a user_id=1)
eq("uid site", d.container_uid("site.example.com"), 65536 * (1 * 255 + 5)); // 17039360
eq("br site", d.container_br("site.example.com"), "10.20.1.x");
eq("gw site", d.container_gw("site.example.com"), "10.20.1.1");
eq("iface site", d.container_interface("site.example.com"), "20-1-5");
eq("br_host_ip site", d.container_br_host_ip("site.example.com"), "10.20.1.1");
eq("bridge site", d.container_bridge("site.example.com"), false);
eq("user_id site", d.container_user_id("site.example.com"), 1);
eq("user_ip_match site", d.container_user_ip_match("site.example.com"), true);
eq("hostnet site", d.container_hostnet("site.example.com"), "20"); // STRING (v3)
eq("host site", d.container_host("site.example.com"), "node1");
eq("host_ip site", d.container_host_ip("site.example.com"), "10.16.20.1");
eq("reseller site", d.container_reseller("site.example.com"), "a"); // has reseller_id
eq("http_port site", d.container_http_port("site.example.com"), 80);
eq("https_port site", d.container_https_port("site.example.com"), 443);

// custom (bridge br-x, ip 10.20.2.6, user b user_id=2 reseller a)
eq("uid custom", d.container_uid("custom"), 65536 * (2 * 255 + 6)); // 33816576
eq("br custom", d.container_br("custom"), "10.20.2.x"); // no `br`, has `bridge`
eq("bridge custom", d.container_bridge("custom"), "br-x");
eq("user_ip_match custom", d.container_user_ip_match("custom"), true); // bridge → true
eq("hostnet custom", d.container_hostnet("custom"), 20); // bridge → SC_HOSTNET
eq("host custom", d.container_host("custom"), "node1"); // hostnet 20 == node1
eq("reseller custom", d.container_reseller("custom"), "a"); // reseller field

// explicit overrides win
eq("br explicit", d.container_br("explicit"), "br-lo");
eq("gw explicit", d.container_gw("explicit"), "10.20.1.254");
eq("iface explicit", d.container_interface("explicit"), "eth9");
eq("http_port explicit", d.container_http_port("explicit"), 8080);
eq("https_port explicit", d.container_https_port("explicit"), 8443);

// interface separators by network class
eq("iface 192", d.container_interface("one92"), "168_5_9");
eq("iface 172", d.container_interface("one72"), "16+4+8");

// no-ip container: uid octet defaults to 1
eq("uid noip", d.container_uid("noip"), 65536 * (1 * 255 + 1)); // 16777216

console.log(`derive.test: ${passed} passed, ${failures.length} failed`);
for (const f of failures) console.log("  FAIL " + f);
process.exit(failures.length ? 1 : 0);
