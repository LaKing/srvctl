// Run: node modules/named/selftest/topology.test.mjs

import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { dnsRoleForHost, electDnsTopology } = require("../lib/topology.js");

function host(ip, role, extra = {}) {
    return { host_ip: ip, dns_server: role, ...extra };
}

const legacy = electDnsTopology({
    first: {
        "primary.test": host("192.0.2.10", "master"),
        "secondary.test": host("192.0.2.11", "slave"),
    },
    second: {
        "application.test": { host_ip: "192.0.2.20" },
    },
});

assert.equal(legacy.primary.hostname, "primary.test",
    "the first declared legacy master is the compatible fallback");
assert.equal(legacy.primaryIp, "192.0.2.10");
assert.equal(legacy.usedLegacyFallback, true);
assert.deepEqual(legacy.replicas.map((entry) => entry.hostname), [
    "secondary.test",
]);
assert.deepEqual(legacy.replicaIps, ["192.0.2.11"]);
assert.equal(dnsRoleForHost(legacy, "primary.test"), "primary");
assert.equal(dnsRoleForHost(legacy, "application.test"), null);

assert.throws(() => electDnsTopology({ cluster: {
    first: host("192.0.2.30", "master"),
    second: host("192.0.2.31", "master"),
} }), /multiple DNS masters require exactly one dns_primary=true/,
"ambiguous legacy order must fail instead of creating split primaries");

const pinned = electDnsTopology({
    cluster: {
        "first.test": host("198.51.100.10", "master"),
        "pinned.test": host("198.51.100.11", "master", { dns_primary: true }),
        "slave.test": host("198.51.100.12", "slave"),
    },
});
assert.equal(pinned.primary.hostname, "pinned.test");
assert.equal(pinned.usedLegacyFallback, false);
assert.deepEqual(pinned.replicas.map((entry) => entry.hostname), ["first.test", "slave.test"]);
assert.equal(dnsRoleForHost(pinned, "first.test"), "replica",
    "an additional explicitly demoted legacy master is a replica");

assert.throws(() => electDnsTopology({
    cluster: {
        a: host("203.0.113.1", "master", { dns_primary: true }),
        b: host("203.0.113.2", "master", { dns_primary: true }),
    },
}), /more than one DNS host has dns_primary=true/);

assert.throws(() => electDnsTopology({
    cluster: {
        replica: host("203.0.113.3", "slave", { dns_primary: true }),
        master: host("203.0.113.4", "master"),
    },
}), /dns_primary=true requires dns_server=master/);

assert.throws(() => electDnsTopology({
    cluster: {
        ignored: { host_ip: "203.0.113.30", dns_primary: true },
        master: host("203.0.113.31", "master"),
    },
}), /dns_primary=true requires dns_server=master/,
"a marker on a non-DNS host must not be silently ignored");

assert.throws(() => electDnsTopology({ cluster: {
    replica: host("203.0.113.5", "slave"),
} }), /could not locate a DNS master/);

assert.throws(() => electDnsTopology({ cluster: {
    master: { dns_server: "master" },
} }), /DNS master master has no host_ip/);

assert.throws(() => electDnsTopology({ cluster: {
    master: host("203.0.113.40", "master"),
    replica: { dns_server: "slave" },
} }), /DNS slave replica has no host_ip/);

assert.throws(() => electDnsTopology({ cluster: {
    master: host("203.0.113.50", "master"),
    replica: host("203.0.113.50", "slave"),
} }), /share host_ip 203\.0\.113\.50/,
"transfer endpoints must be unique");

assert.throws(() => electDnsTopology({
    first: {
        duplicate: { host_ip: "203.0.113.60" },
        master: host("203.0.113.61", "master"),
    },
    second: {
        duplicate: { host_ip: "203.0.113.62" },
    },
}), /host duplicate is declared more than once/,
"snapshot cache keys require globally unique hostnames");

const explicitSources = electDnsTopology({ cluster: {
    primary: host("203.0.113.70", "master", {
        dns_primary: true,
        dns_replication_source: "10.0.0.70",
        dns_replication_acl_ip: "198.51.100.70",
    }),
    replica: host("203.0.113.71", "slave", {
        dns_replication_source: "10.0.0.71",
        dns_replication_acl_ip: "198.51.100.71",
    }),
} });
assert.equal(explicitSources.primaryAclIp, "198.51.100.70");
assert.deepEqual(explicitSources.replicaAclIps, ["198.51.100.71"]);

assert.throws(() => electDnsTopology({ cluster: {
    primary: host("203.0.113.80", "master"),
    replica: host("203.0.113.81", "slave", {
        dns_replication_source: "2001:db8::81",
    }),
} }), /replication source family does not match primary host_ip/);

assert.throws(() => electDnsTopology({ cluster: {
    primary: host("not-an-ip", "master"),
} }), /invalid host_ip not-an-ip/);

console.log("topology.test: passed");
