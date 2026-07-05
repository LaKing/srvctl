// modules/datastore/selftest/generators.test.mjs — golden test for the v4
// pure generator port (generators.mjs) against a frozen v3 capture.
//
// Group A (golden): compare generators.mjs against a checked-in v3 capture
//   produced by capture-generators.cjs over a rich fixture. Normalizes
//   os.hostname()→<HOST> and SC_INSTALL_DIR→<INSTALL>.
// Group B: container_resolv_conf with a CONTROLLED ctx.HOSTNAME (v4 only — v3
//   can't be driven here, see capture note). Exact expected output.
// Group C: container_useruids over injected passwd/group content (v4 only).
//
// Run: node modules/datastore/selftest/generators.test.mjs  (exit != 0 on fail)
// Re-record while v3 lib.js still exists:
//      node modules/datastore/selftest/generators.test.mjs --record
//
// NOTE: --record depends on modules/datastore/lib.js. Normal verification does
// not, so WP-C can replace lib.js after this golden exists.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { generators, container_useruids } from "../lib/generators.mjs";
import { derivations } from "../lib/derive.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CAPTURE = path.join(HERE, "capture-generators.cjs");
const GOLDEN_FILE = path.join(HERE, "golden", "generators.json");
const HOSTNAME = os.hostname();
const INSTALL_DIR = "/opt/srvctl-test";

// Rich fixture exercising aliases, altnames, subdomains, mapped_ports, dotless
// names, gsuite, mail. prefix, and host-key fields.
const HOSTS = {
  node1: { hostnet: 20, host_ip: "10.16.20.1", "host-key-rsa": "KEYA", dns1: "1.1.1.1", dns2: "1.0.0.1" },
  node2: { hostnet: 21, host_ip: "10.16.21.1", "host-key-ed25519": "KEYB" },
};
const USERS = {
  root: { reseller_id: 0, user_id: 0, uid: 0, name: "root" },
  alice: { reseller_id: 1, user_id: 1, uid: 1001, name: "Alice" },
  bob: { user_id: 2, uid: 1002, reseller: "alice", name: "Bob" },
};
const CONTAINERS = {
  "site.example.com": { user: "alice", ip: "10.20.1.5" },
  "shop.example.com": { user: "bob", ip: "10.20.2.6", aliases: ["store.example.com"], altnames: ["shop-alt.example.com"] },
  "mail.site.example.com": { user: "alice", ip: "10.20.1.9" },
  "ports.example.com": { user: "alice", ip: "10.20.1.7", mapped_ports: [{ proto: "tcp", host_port: 2222, container_port: 22, comment: "ssh" }] },
  sub: { user: "alice", ip: "10.20.1.8", subdomains: ["fox", "api"] },
  "gsuite.example.com": { user: "alice", ip: "10.20.1.10", use_gsuite: true },
};

const ENV = {
  ...process.env,
  SC_HOSTNET: "20",
  SC_USER: "root",
  USER: "root",
  NOW: "2026-01-01T00:00:00.000Z",
  SC_COMPANY_DOMAIN: "example.com",
  SC_INSTALL_DIR: INSTALL_DIR,
  SRVCTL: "srvctl-4.0.0.2",
};

function norm(v) {
  if (typeof v !== "string") return v;
  let out = v.split(HOSTNAME).join("<HOST>");
  const short = HOSTNAME.split(".")[0];
  if (short && short !== HOSTNAME) out = out.split(short).join("<HOST>");
  out = out.split(INSTALL_DIR).join("<INSTALL>");
  return out;
}
function normAll(obj) {
  const out = {};
  for (const k of Object.keys(obj)) out[k] = norm(obj[k]);
  return out;
}

let passed = 0;
const failures = [];
function check(name, got, want) {
  try {
    assert.deepEqual(got, want);
    passed++;
  } catch {
    failures.push({ name, got, want });
  }
}

function captureV3Golden() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sc-gen-"));
  try {
    fs.writeFileSync(path.join(dir, "hosts.json"), JSON.stringify(HOSTS));
    fs.writeFileSync(path.join(dir, "users.json"), JSON.stringify(USERS));
    fs.writeFileSync(path.join(dir, "containers.json"), JSON.stringify(CONTAINERS));

    const r = spawnSync(process.execPath, [CAPTURE], {
      env: { ...ENV, SC_DATASTORE_DIR: dir },
      encoding: "utf8",
    });
    if (r.error) throw new Error(`spawn capture: ${r.error.message}`);
    if (r.status !== 0) throw new Error(`capture exited ${r.status}: ${r.stderr}`);
    return normAll(JSON.parse(r.stdout));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// ---- Group A: checked-in v3 capture ---------------------------------------

{
  const record = process.argv.includes("--record");
  if (record) {
    const captured = captureV3Golden();
    fs.mkdirSync(path.dirname(GOLDEN_FILE), { recursive: true });
    fs.writeFileSync(GOLDEN_FILE, JSON.stringify(captured, null, 2) + "\n");
    console.log(`recorded ${Object.keys(captured).length} generator entries -> ${path.relative(process.cwd(), GOLDEN_FILE)}`);
  }
  if (!fs.existsSync(GOLDEN_FILE)) {
    throw new Error("missing generator golden; run generators.test.mjs --record while v3 lib.js exists");
  }
  const v3 = JSON.parse(fs.readFileSync(GOLDEN_FILE, "utf8"));

  // Build the v4 result set with the SAME iteration as capture-generators.cjs.
  const ctx = {
    containers: CONTAINERS, users: USERS, hosts: HOSTS,
    HOSTNAME, SC_HOSTNET: 20, SC_COMPANY_DOMAIN: "example.com", SC_INSTALL_DIR: INSTALL_DIR,
    hasLocalRootfs: () => false,
  };
  const g = generators(ctx);
  const CONTAINER_GENS = ["container_hosts", "container_ethernet", "container_ethernet_network",
    "container_quota", "container_nspawn", "container_br_netdev", "container_br_network",
    "container_firewall_commands", "container_mx", "container_domains"];
  const CLUSTER_GENS = ["cluster_etc_hosts", "cluster_postfix_relaydomains", "cluster_host_keys",
    "cluster_user_list", "cluster_container_list", "cluster_host_list", "cluster_host_ip_list"];
  const v4raw = {};
  for (const C of Object.keys(CONTAINERS)) for (const gen of CONTAINER_GENS) v4raw[`${gen}:${C}`] = g[gen](C);
  for (const gen of CLUSTER_GENS) v4raw[gen] = g[gen]();
  for (const u of Object.keys(USERS)) v4raw[`user_uid:${u}`] = g.user_uid(u);
  v4raw["user_container_list"] = g.user_container_list("root");
  const v4 = normAll(v4raw);

  // Compare every captured v3 key against v4 (and flag any v4-only keys).
  for (const k of Object.keys(v3)) check(`v3~v4 ${k}`, v4[k], v3[k]);
  for (const k of Object.keys(v4)) if (!(k in v3)) failures.push({ name: `v4-only ${k}`, got: v4[k], want: "(missing in v3)" });
}

// ---- Group B: resolv_conf with a controlled HOSTNAME (v4-only) ------------

{
  const ctx = {
    containers: { "c.example.com": { user: "alice", ip: "10.20.1.5" } },
    users: USERS,
    hosts: { node1: { hostnet: 20, host_ip: "10.16.20.1", dns1: "1.1.1.1", dns2: "1.0.0.1" } },
    HOSTNAME: "node1", SC_HOSTNET: 20, SC_COMPANY_DOMAIN: "example.com", hasLocalRootfs: () => false,
  };
  const g = generators(ctx);
  const expect =
    "## srvctl generated\n" +
    "nameserver 10.20.1.1\n" +   // container_gw of 10.20.1.5
    "nameserver 1.1.1.1\n" +      // hosts.node1.dns1
    "nameserver 1.0.0.1\n" +      // hosts.node1.dns2
    "nameserver 8.8.8.8\n" +
    "nameserver 8.8.4.4\n";
  check("resolv_conf (controlled HOSTNAME)", g.container_resolv_conf("c.example.com"), expect);
}

// ---- Group C: container_useruids over injected passwd/group ---------------

{
  const passwd = "root:x:0:0::/root:/bin/bash\napache:x:48:48::/usr/share/httpd:/sbin/nologin\njoe:x:1000:1000::/home/joe:/bin/bash\n";
  const group = "root:x:0:\napache:x:48:\njoe:x:1000:\n";
  const root_uid = 17039360; // container_uid for a user_id=1, octet 5 container
  const out = container_useruids("site.example.com", root_uid, passwd, group);
  // apache present → real chown line; mysql/mongod/codepad absent → "## no user"
  check("useruids has apache chown", out.includes("chown -R " + (root_uid + 48) + ":" + (root_uid + 48)), true);
  check("useruids missing mysql noted", out.includes("## no user mysql"), true);
  check("useruids joe home chown (uid>=1000)", out.includes("/home/joe"), true);
  // Faithful v3 quirk: root has uid 0, and `!users[user]` is truthy for 0, so
  // root is skipped as "## no user root" (see the FIXME in generators.mjs).
  check("useruids skips uid-0 root (v3 quirk)", out.includes("## no user root"), true);
  check("useruids root_uid header", out.includes("root_uid=" + root_uid), true);
}

console.log(`generators.test: ${passed} passed, ${failures.length} failed`);
for (const f of failures) {
  console.log(`  FAIL ${f.name}`);
  console.log(`    want: ${JSON.stringify(f.want)}`);
  console.log(`    got:  ${JSON.stringify(f.got)}`);
}
process.exit(failures.length ? 1 : 0);
