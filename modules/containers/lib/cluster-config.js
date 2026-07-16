"use strict";

const crypto = require("crypto");
const fs = require("fs");

class ClusterConfigError extends Error {}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) &&
        (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function sha256(content) {
    return crypto.createHash("sha256").update(content).digest("hex");
}

function validateClusterName(name) {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(name)) {
        throw new ClusterConfigError("invalid cluster name " + JSON.stringify(name));
    }
}

function validateHostname(hostname) {
    if (hostname.length > 253 || hostname !== hostname.toLowerCase()) {
        throw new ClusterConfigError("invalid hostname " + JSON.stringify(hostname));
    }
    const labels = hostname.split(".");
    if (labels.some(function(label) {
        return label.length < 1 || label.length > 63 ||
            !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label);
    })) {
        throw new ClusterConfigError("invalid hostname " + JSON.stringify(hostname));
    }
}

function validateHostConfig(hostname, config) {
    if (!isPlainObject(config)) {
        throw new ClusterConfigError("host " + hostname + " configuration must be an object");
    }

    const generated = new Set(["HOSTNAME", "CLUSTERNAME", "CLUSTERS_SHA256", "HOSTS_SHA256"]);
    const runtimeOwned = new Set(["HOST_KEY"]);
    Object.keys(config).forEach(function(key) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
            throw new ClusterConfigError("host " + hostname + " has shell-unsafe key " + JSON.stringify(key));
        }
        const normalized = key.toUpperCase();
        if (runtimeOwned.has(normalized)) {
            throw new ClusterConfigError("host " + hostname +
                " has datastore-owned key " + JSON.stringify(key));
        }
        if (generated.has(normalized)) {
            throw new ClusterConfigError("host " + hostname + " has duplicate/reserved key " + JSON.stringify(key));
        }
        generated.add(normalized);
        if (typeof config[key] === "string" && config[key].includes("\0")) {
            throw new ClusterConfigError("host " + hostname + " key " + key + " contains NUL");
        }
    });
}

function validateClusters(clusters) {
    if (!isPlainObject(clusters)) {
        throw new ClusterConfigError("clusters configuration must be an object");
    }

    const records = [];
    const seenHosts = new Map();
    Object.keys(clusters).forEach(function(clusterName) {
        validateClusterName(clusterName);
        const hosts = clusters[clusterName];
        if (!isPlainObject(hosts)) {
            throw new ClusterConfigError("cluster " + clusterName + " host map must be an object");
        }
        Object.keys(hosts).forEach(function(hostname) {
            validateHostname(hostname);
            if (seenHosts.has(hostname)) {
                throw new ClusterConfigError("hostname " + hostname + " appears in both " +
                    seenHosts.get(hostname) + " and " + clusterName);
            }
            validateHostConfig(hostname, hosts[hostname]);
            seenHosts.set(hostname, clusterName);
            records.push({
                clusterName: clusterName,
                hostname: hostname,
                config: hosts[hostname],
                hosts: hosts
            });
        });
    });
    return records;
}

function parseClusters(content, label) {
    let clusters;
    try {
        clusters = JSON.parse(content.toString("utf8"));
    } catch (error) {
        throw new ClusterConfigError("cannot parse " + label + ": " + error.message);
    }
    const records = validateClusters(clusters);
    return { clusters: clusters, records: records };
}

function readClusters(filename) {
    let content;
    try {
        content = fs.readFileSync(filename);
    } catch (error) {
        throw new ClusterConfigError("cannot read " + filename + ": " + error.message);
    }
    const parsed = parseClusters(content, filename);
    parsed.content = content;
    parsed.sha256 = sha256(content);
    return parsed;
}

function requireLocalHost(records, hostname) {
    const matches = records.filter(function(record) { return record.hostname === hostname; });
    if (matches.length !== 1) {
        throw new ClusterConfigError("local hostname " + hostname + " must appear exactly once (found " +
            matches.length + ")");
    }
    return matches[0];
}

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function buildProjection(parsed, hostname) {
    const record = requireLocalHost(parsed.records, hostname);
    const hostsContent = JSON.stringify(record.hosts, null, 2);
    const hostsSha256 = sha256(Buffer.from(hostsContent, "utf8"));
    const lines = [
        "#!/bin/bash",
        "SC_HOSTNAME=" + shellQuote(hostname),
        "SC_CLUSTERNAME=" + shellQuote(record.clusterName),
        "SC_CLUSTERS_SHA256=" + shellQuote(parsed.sha256),
        "SC_HOSTS_SHA256=" + shellQuote(hostsSha256)
    ];

    Object.keys(record.config).forEach(function(key) {
        const value = record.config[key];
        if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
            lines.push("SC_" + key.toUpperCase() + "=" + shellQuote(value));
        }
    });

    return {
        hostConfContent: lines.join("\n") + "\n",
        hostsContent: hostsContent,
        hostsSha256: hostsSha256,
        record: record
    };
}

// The v3 generator renders host.conf as UNQUOTED shell assignments
// (SC_KEY=value). v4 accepts any NUL-free string because it shell-quotes,
// but a rollback hands the topology back to v3: on the next v3
// update-install, whitespace splits the assignment into a command and
// $(...), backticks, quotes, ~, or ; would be evaluated by root bash.
// Values must therefore stay within a charset that is inert unquoted.
const V3_UNQUOTED_SAFE = /^[A-Za-z0-9._:/@+,=-]*$/;

function assertLegacyRenderSafe(parsed) {
    parsed.records.forEach(function(record) {
        Object.keys(record.config).forEach(function(key) {
            const value = record.config[key];
            if (typeof value !== "string") return;
            if (!V3_UNQUOTED_SAFE.test(value)) {
                throw new ClusterConfigError("host " + record.hostname + " key " + key +
                    " has a value the v3 generator cannot render safely as an unquoted" +
                    " shell assignment: " + JSON.stringify(value));
            }
        });
    });
}

function verifyProjection(clusterFile, hostConfFile, hostsFile, hostname) {
    const parsed = readClusters(clusterFile);
    const projection = buildProjection(parsed, hostname);
    let actualHostConf;
    let actualHosts;
    try {
        actualHostConf = fs.readFileSync(hostConfFile, "utf8");
        actualHosts = fs.readFileSync(hostsFile, "utf8");
    } catch (error) {
        throw new ClusterConfigError("cannot read derived cluster configuration: " + error.message);
    }
    if (actualHostConf !== projection.hostConfContent) {
        throw new ClusterConfigError(hostConfFile + " is stale for canonical generation " + parsed.sha256);
    }
    if (actualHosts !== projection.hostsContent || sha256(Buffer.from(actualHosts, "utf8")) !== projection.hostsSha256) {
        throw new ClusterConfigError(hostsFile + " is stale for canonical generation " + parsed.sha256);
    }
    return parsed.sha256;
}

module.exports = {
    ClusterConfigError,
    assertLegacyRenderSafe,
    buildProjection,
    isPlainObject,
    parseClusters,
    readClusters,
    requireLocalHost,
    sha256,
    validateClusters,
    verifyProjection
};
