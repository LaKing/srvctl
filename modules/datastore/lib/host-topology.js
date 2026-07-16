"use strict";

/*
 * Static host topology belongs exclusively to /etc/srvctl/clusters.json.
 * Datastore host rows are allowed to carry only the explicitly enumerated
 * runtime fields below.  Every reader overlays those dynamic values onto the
 * local cluster selected from the canonical file, so a stale/read-only
 * datastore can never override host membership, host_ip, hostnet, or roles.
 */

const os = require("os");
const clusterConfig = require("../../containers/lib/cluster-config.js");

const CANONICAL_CLUSTERS_FILE = "/etc/srvctl/clusters.json";
const DYNAMIC_HOST_FIELDS = Object.freeze([
  "host_key",
  "host-key",
  "host-key-rsa",
  "host-key-ed25519",
  "host-key-ecdsa",
  "host-key-dsa",
]);
const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

class HostTopologyError extends Error {
  constructor(message) {
    super(message);
    this.name = "HostTopologyError";
  }
}

function assertHostMap(value, label) {
  if (!clusterConfig.isPlainObject(value)) {
    throw new HostTopologyError(`${label} must be a {hostname: record} object`);
  }
  return value;
}

function extractDynamicHostFields(record, label = "datastore host record") {
  if (record === null || record === undefined) return {};
  if (!clusterConfig.isPlainObject(record)) {
    throw new HostTopologyError(`${label} must be an object`);
  }

  const dynamic = {};
  for (const field of DYNAMIC_HOST_FIELDS) {
    if (!hasOwn(record, field)) continue;
    const value = record[field];
    if (typeof value !== "string" || value.includes("\0")) {
      throw new HostTopologyError(`${label} field ${field} must be a NUL-free string`);
    }
    dynamic[field] = value;
  }
  return dynamic;
}

function readCanonicalHostTopology(options = {}) {
  const clusterFile = options.clusterFile || CANONICAL_CLUSTERS_FILE;
  const hostname = options.hostname || os.hostname();
  let parsed;
  let local;
  try {
    parsed = clusterConfig.readClusters(clusterFile);
    local = clusterConfig.requireLocalHost(parsed.records, hostname);
  } catch (error) {
    throw new HostTopologyError(error.message);
  }

  // init.sh pins the generation it dispatched under. The cluster lock was
  // released back then, so this dynamic reread must prove it still sees the
  // same generation; mixing pre-publication shell/module state with a newer
  // topology is refused, and the retried invocation reads coherently.
  const pinned = process.env.SC_CANONICAL_CLUSTERS_SHA256;
  if (pinned && /^[0-9a-f]{64}$/.test(pinned) && parsed.sha256 !== pinned) {
    throw new HostTopologyError(
      "canonical cluster generation changed during this invocation " +
        `(dispatched under ${pinned}, read ${parsed.sha256}); retry`,
    );
  }

  // The shared schema already rejects host_key and shell-unsafe host-key-*
  // names. Keep this guard at the ownership boundary as defense in depth.
  for (const [host, record] of Object.entries(local.hosts)) {
    for (const field of DYNAMIC_HOST_FIELDS) {
      if (hasOwn(record, field)) {
        throw new HostTopologyError(
          `canonical host ${host} contains datastore-owned field ${field}`,
        );
      }
    }
  }

  return {
    clusterFile,
    clusterName: local.clusterName,
    hostname,
    hosts: local.hosts,
    sha256: parsed.sha256,
  };
}

function overlayStoredHosts(storedHosts, options = {}) {
  assertHostMap(storedHosts, "datastore hosts");
  const topology = readCanonicalHostTopology(options);
  const hosts = {};

  for (const hostname of Object.keys(topology.hosts)) {
    const staticRecord = topology.hosts[hostname];
    const dynamicRecord = extractDynamicHostFields(
      storedHosts[hostname],
      `datastore host ${hostname}`,
    );
    hosts[hostname] = { ...staticRecord, ...dynamicRecord };
  }

  return { hosts, topology };
}

function dynamicHostMap(hosts, options = {}) {
  assertHostMap(hosts, "hosts");
  const topology = readCanonicalHostTopology(options);
  const dynamic = {};

  for (const hostname of Object.keys(topology.hosts)) {
    const record = extractDynamicHostFields(hosts[hostname], `host ${hostname}`);
    if (Object.keys(record).length > 0) dynamic[hostname] = record;
  }

  return { hosts: dynamic, topology };
}

// Production is intentionally not path-configurable: there is one canonical
// topology pathname. Isolated tests may inject a temporary canonical file and
// hostname only when they explicitly opt into the selftest mode.
function runtimeTopologyOptions(env = process.env) {
  if (env.SRVCTL_SELFTEST === "true") {
    if (!env.SRVCTL_SELFTEST_CLUSTERS_FILE || !env.SRVCTL_SELFTEST_HOSTNAME) {
      throw new HostTopologyError(
        "SRVCTL_SELFTEST requires SRVCTL_SELFTEST_CLUSTERS_FILE and SRVCTL_SELFTEST_HOSTNAME",
      );
    }
    return {
      clusterFile: env.SRVCTL_SELFTEST_CLUSTERS_FILE,
      hostname: env.SRVCTL_SELFTEST_HOSTNAME,
    };
  }

  if (env.SC_CLUSTER_HOSTNAME_BOOTSTRAP === "true") {
    if (!env.SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME) {
      throw new HostTopologyError(
        "cluster hostname bootstrap is missing its validated target hostname",
      );
    }
    return { hostname: env.SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME };
  }
  return {};
}

module.exports = {
  CANONICAL_CLUSTERS_FILE,
  DYNAMIC_HOST_FIELDS,
  HostTopologyError,
  dynamicHostMap,
  extractDynamicHostFields,
  overlayStoredHosts,
  readCanonicalHostTopology,
  runtimeTopologyOptions,
};
