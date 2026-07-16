"use strict";

const net = require("net");

/*
 * Pure DNS-topology selection for named.js.
 *
 * Historical configurations may contain more than one
 * `dns_server: "master"`.  Independently generated primary zones are unsafe:
 * a later serial from a stale host can supersede the correct data.  Elect one
 * publication primary and treat every other DNS host as a transfer replica.
 * A sole legacy master remains compatible; multiple masters require an
 * explicit `dns_primary: true` so JSON/config drift cannot split the election.
 */

function electDnsTopology(clusters) {
    if (!clusters || typeof clusters !== "object" || Array.isArray(clusters)) {
        throw new Error("clusters configuration must be an object");
    }

    const dnsHosts = [];
    const explicitMarkers = [];
    const seenHostnames = new Set();

    Object.keys(clusters).forEach(function(cluster) {
        const hosts = clusters[cluster];
        if (!hosts || typeof hosts !== "object" || Array.isArray(hosts)) {
            throw new Error("cluster " + cluster + " must contain a host object");
        }

        Object.keys(hosts).forEach(function(hostname) {
            const config = hosts[hostname];
            if (!config || typeof config !== "object" || Array.isArray(config)) return;
            if (seenHostnames.has(hostname)) {
                throw new Error("host " + hostname + " is declared more than once");
            }
            seenHostnames.add(hostname);
            if (config.dns_primary === true) {
                explicitMarkers.push({ cluster: cluster, hostname: hostname, config: config });
            }
            if (config.dns_server !== "master" && config.dns_server !== "slave") return;
            if (!config.host_ip) {
                throw new Error("DNS " + config.dns_server + " " + hostname + " has no host_ip");
            }
            if (net.isIP(config.host_ip) === 0) {
                throw new Error("DNS host " + hostname + " has invalid host_ip " + config.host_ip);
            }
            ["dns_replication_source", "dns_replication_acl_ip"].forEach(function(field) {
                if (config[field] !== undefined && net.isIP(config[field]) === 0) {
                    throw new Error("DNS host " + hostname + " has invalid " + field +
                        " " + config[field]);
                }
            });
            dnsHosts.push({ cluster: cluster, hostname: hostname, config: config });
        });
    });

    const explicit = explicitMarkers;
    if (explicit.length > 1) {
        throw new Error("more than one DNS host has dns_primary=true: " +
            explicit.map(function(host) { return host.hostname; }).join(", "));
    }
    if (explicit.length === 1 && explicit[0].config.dns_server !== "master") {
        throw new Error("dns_primary=true requires dns_server=master on " + explicit[0].hostname);
    }

    const legacyMasters = dnsHosts.filter(function(host) {
        return host.config.dns_server === "master";
    });
    if (explicit.length === 0 && legacyMasters.length > 1) {
        throw new Error("multiple DNS masters require exactly one dns_primary=true: " +
            legacyMasters.map(function(host) { return host.hostname; }).join(", "));
    }
    const primary = explicit[0] || legacyMasters[0];
    if (!primary) throw new Error("could not locate a DNS master in the cluster configuration");

    const replicas = dnsHosts.filter(function(host) {
        return host.hostname !== primary.hostname;
    });
    const dnsIpOwners = new Map([[primary.config.host_ip, primary.hostname]]);
    const replicaIps = [];
    const replicaAclIps = [];
    replicas.forEach(function(host) {
        const existingOwner = dnsIpOwners.get(host.config.host_ip);
        if (existingOwner) {
            throw new Error("DNS hosts " + existingOwner + " and " + host.hostname +
                " share host_ip " + host.config.host_ip);
        }
        dnsIpOwners.set(host.config.host_ip, host.hostname);
        replicaIps.push(host.config.host_ip);
        const aclIp = host.config.dns_replication_acl_ip || host.config.host_ip;
        if (!replicaAclIps.includes(aclIp)) replicaAclIps.push(aclIp);
        if (host.config.dns_replication_source &&
            net.isIP(host.config.dns_replication_source) !== net.isIP(primary.config.host_ip)) {
            throw new Error("DNS replica " + host.hostname + " replication source family " +
                "does not match primary host_ip " + primary.config.host_ip);
        }
    });

    return {
        primary: primary,
        replicas: replicas,
        primaryIp: primary.config.host_ip,
        primaryAclIp: primary.config.dns_replication_acl_ip || primary.config.host_ip,
        replicaIps: replicaIps,
        replicaAclIps: replicaAclIps,
        usedLegacyFallback: explicit.length === 0,
    };
}

function dnsRoleForHost(topology, hostname) {
    if (topology.primary.hostname === hostname) return "primary";
    if (topology.replicas.some(function(host) { return host.hostname === hostname; })) return "replica";
    return null;
}

module.exports = {
    dnsRoleForHost: dnsRoleForHost,
    electDnsTopology: electDnsTopology,
};
