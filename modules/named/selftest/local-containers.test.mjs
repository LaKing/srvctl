// modules/named/selftest/local-containers.test.mjs — regression coverage for
// get_conf's v4 datastore source selection.
// Run: node modules/named/selftest/local-containers.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import vm from "node:vm";
import net from "node:net";

const require = createRequire(import.meta.url);
const { SERIAL_PLACEHOLDER, planZoneUpdate } = require("../lib/zonefile.js");

const namedSource = fs.readFileSync(new URL("../named.js", import.meta.url), "utf8");
const getConfStart = namedSource.indexOf("function get_container_zone(");
const getConfEnd = namedSource.indexOf("\nfunction make_conf()", getConfStart);

assert.notEqual(getConfStart, -1, "get_container_zone must exist in named.js");
assert.notEqual(getConfEnd, -1, "get_conf source boundary must exist in named.js");

const getConfSource = namedSource.slice(getConfStart, getConfEnd);
const reads = [];
const errors = [];
const context = {
    HOSTNAME: "local.test",
    CDN: "company.test",
    br: "\n",
    clusters: {
        cluster: {
            "local.test": { host_ip: "192.0.2.10" },
            "peer.test": { host_ip: "192.0.2.11" },
        },
    },
    datastore: {
        containers: {
            "mindtalk.hu": {
                override_in_a_ip: "38.242.131.65",
                use_dmarc: false,
            },
        },
    },
    peer_container_snapshots: {
        "peer.test": { "peer-cache.example": {} },
    },
    fs: {
        readFileSync(path) {
            reads.push(path);
            if (path.startsWith("/var/named/srvctl/") && path.endsWith(".zone")) {
                const error = new Error("missing test zone: " + path);
                error.code = "ENOENT";
                throw error;
            }
            throw new Error("unexpected read: " + path);
        },
    },
    is_master: true,
    listed_domain_names: [],
    master_servers: "192.0.2.53;",
    replica_servers: "192.0.2.54;",
    replica_transfer_clients: "198.51.100.54;",
    dns_topology: {
        primaryAclIp: "198.51.100.53",
        primary: { config: { dns_replication_source: "192.0.2.53" } },
    },
    local_dns_host: { config: { dns_replication_source: "192.0.2.54" } },
    soa_primary_name: "ns1.company.test",
    net,
    planZoneUpdate,
    SERIAL_PLACEHOLDER,
    tab: "\t",
    msg() {},
    err(message) { errors.push(message); },
};

vm.runInNewContext(getConfSource, context, { filename: "named.js#get_conf" });

const localConf = context.get_conf("cluster", "local.test");
assert.match(localConf, /zone "mindtalk\.hu"/,
    "local DNS config must use datastore.containers");
assert.match(localConf, /notify explicit; also-notify \{192\.0\.2\.54;\}/);
assert.match(localConf, /notify-source 192\.0\.2\.53;/);
assert.match(localConf, /allow-transfer \{198\.51\.100\.54;\}/);
assert.deepEqual(reads, ["/var/named/srvctl/mindtalk.hu.zone"],
    "local DNS config must not read legacy containers.json or a peer cache");
assert.equal(context.pending_zone_updates.length, 1);
assert.equal(context.pending_zone_updates[0].path, "/var/named/srvctl/mindtalk.hu.zone");
assert.match(context.pending_zone_updates[0].content,
    /^\*[ \t]+IN[ \t]+A[ \t]+38\.242\.131\.65$/m,
    "wildcard A must use the per-entity override");
assert.match(context.pending_zone_updates[0].content,
    /^@[ \t]+IN[ \t]+A[ \t]+38\.242\.131\.65$/m,
    "apex A must use the per-entity override");
assert.match(context.pending_zone_updates[0].content,
    /^@[ \t]+IN SOA[ \t]+ns1\.company\.test\./m,
    "SOA MNAME must remain the DNS authority when the apex A is overridden");
assert.doesNotMatch(context.pending_zone_updates[0].content,
    /^(?:\*|@)[ \t]+IN[ \t]+A[ \t]+192\.0\.2\.10$/m,
    "generated A records must not fall back to the host IP");

context.replica_servers = "";
context.replica_transfer_clients = "";
const standalonePrimary = context.primary_zone_statement(
    "standalone.example", "/var/named/srvctl/standalone.example.zone");
assert.match(standalonePrimary, /notify no;/,
    "a primary without replicas must disable NOTIFY explicitly");
assert.match(standalonePrimary, /allow-transfer \{none;\};/,
    "a primary without replicas must deny transfers with valid BIND syntax");
assert.doesNotMatch(standalonePrimary, /also-notify/,
    "an empty also-notify block must not be rendered");
context.replica_servers = "192.0.2.54;";
context.replica_transfer_clients = "198.51.100.54;";

context.listed_domain_names.length = 0;
const peerConf = context.get_conf("cluster", "peer.test");
assert.match(peerConf, /zone "peer-cache\.example"/,
    "peer DNS config must continue to use the fetched cache");
assert.deepEqual(reads, [
    "/var/named/srvctl/mindtalk.hu.zone",
    "/var/named/srvctl/peer-cache.example.zone",
]);
assert.deepEqual(errors, []);

context.is_master = false;
context.listed_domain_names.length = 0;
const replicaConf = context.get_conf("cluster", "local.test");
assert.match(replicaConf,
    /zone "mindtalk\.hu" \{type slave; masters \{192\.0\.2\.53;\};/,
    "replicas must transfer from only the elected canonical primary");
assert.match(replicaConf, /allow-notify \{198\.51\.100\.53;\};/);
assert.match(replicaConf, /transfer-source 192\.0\.2\.54;/);
assert.doesNotMatch(replicaConf, /masters \{[^}]*192\.0\.2\.54/,
    "replicas must not consult themselves or additional legacy masters");

console.log("local-containers.test: passed");
