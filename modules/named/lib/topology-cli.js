#!/bin/node
"use strict";

/* Stable shell bridge for the pure DNS-topology election helper. */

const fs = require("fs");
const { electDnsTopology } = require("./topology.js");

function hasDnsConfiguration(clusters) {
    if (!clusters || typeof clusters !== "object" || Array.isArray(clusters)) {
        throw new Error("clusters configuration must be an object");
    }
    return Object.keys(clusters).some(function(cluster) {
        const hosts = clusters[cluster];
        if (!hosts || typeof hosts !== "object" || Array.isArray(hosts)) {
            throw new Error("cluster " + cluster + " must contain a host object");
        }
        return Object.keys(hosts).some(function(hostname) {
            const host = hosts[hostname];
            return host && (host.dns_server === "master" || host.dns_server === "slave" ||
                host.dns_primary === true);
        });
    });
}

function fail(message) {
    console.error("DATA-ERROR:", message);
    process.exit(111);
}

const clustersPath = process.argv[2];
if (!clustersPath) fail("usage: topology-cli.js CLUSTERS_JSON");

let clusters;
try {
    clusters = JSON.parse(fs.readFileSync(clustersPath, "utf8"));
} catch (error) {
    fail("cannot read " + clustersPath + ": " + error.message);
}

// Non-DNS installations are valid consumers of generic `regenerate
// all-hosts`: emit an empty topology instead of inventing a DNS failure.
try {
    if (!hasDnsConfiguration(clusters)) process.exit(0);
} catch (error) {
    fail("DNS topology: " + error.message);
}

let topology;
try {
    topology = electDnsTopology(clusters);
} catch (error) {
    fail("DNS topology: " + error.message);
}

const rows = [["primary", topology.primary.hostname]];
topology.replicas.forEach(function(host) {
    rows.push(["replica", host.hostname]);
});
process.stdout.write(rows.map(function(row) { return row.join("\t"); }).join("\n") + "\n");
