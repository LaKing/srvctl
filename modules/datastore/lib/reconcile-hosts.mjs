#!/bin/node

/*
 * Reconcile persisted host rows with the ownership split enforced by
 * host-topology.js. Static fields and membership come from the canonical
 * clusters.json at read time; this command transactionally leaves only the
 * explicit runtime fields in the writable datastore.
 *
 *   reconcile CLUSTERS_FILE DATASTORE_DIR HOSTNAME
 *     prune static/orphan fields while preserving stored dynamic fields
 *
 *   merge CLUSTERS_FILE DATASTORE_DIR HOSTNAME
 *     additionally merge dynamic fields from a JSON host map on stdin
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hostTopology from "./host-topology.js";
import { createStore } from "./store.mjs";

function usage() {
  throw new Error(
    "usage: reconcile-hosts.mjs {reconcile|merge} CLUSTERS_FILE DATASTORE_DIR HOSTNAME",
  );
}

function sameRecord(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function readIncomingHostMap() {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch (error) {
    throw new Error(`cannot parse dynamic host map from stdin: ${error.message}`);
  }
  return parsed;
}

export function reconcileHostRows({
  operation = "reconcile",
  clusterFile,
  datastoreDir,
  hostname,
  incomingHosts,
}) {
  if (operation !== "reconcile" && operation !== "merge") usage();
  if (!clusterFile || !datastoreDir || !hostname) usage();
  if (!fs.existsSync(path.join(datastoreDir, ".per-entity"))) {
    throw new Error(`datastore ${datastoreDir} is not an authoritative per-entity store`);
  }

  const options = { clusterFile, hostname };
  const canonical = hostTopology.readCanonicalHostTopology(options);
  const canonicalIds = new Set(Object.keys(canonical.hosts));
  const incomingDynamic = operation === "merge"
    ? hostTopology.dynamicHostMap(incomingHosts, options).hosts
    : {};
  const store = createStore(datastoreDir, { git: false });
  const stats = { removed: 0, written: 0, dynamicRecords: 0 };

  store.transaction(`reconcile hosts from clusters ${canonical.sha256}`, (tx) => {
    const current = tx.readAll("hosts");

    for (const storedId of Object.keys(current)) {
      if (!canonicalIds.has(storedId)) {
        if (tx.remove("hosts", storedId)) stats.removed++;
      }
    }

    for (const id of canonicalIds) {
      const currentRecord = current[id];
      const storedDynamic = hostTopology.extractDynamicHostFields(
        currentRecord,
        `datastore host ${id}`,
      );
      const desired = operation === "merge"
        ? hostTopology.extractDynamicHostFields(
          { ...storedDynamic, ...(incomingDynamic[id] || {}) },
          `merged host ${id}`,
        )
        : storedDynamic;

      if (Object.keys(desired).length === 0) {
        if (currentRecord !== undefined && tx.remove("hosts", id)) stats.removed++;
        continue;
      }

      stats.dynamicRecords++;
      if (!sameRecord(currentRecord, desired)) {
        tx.write("hosts", id, desired);
        stats.written++;
      }
    }
  });

  return { ...stats, sha256: canonical.sha256 };
}

function main(argv) {
  if (argv.length !== 6) usage();
  const operation = argv[2];
  const incomingHosts = operation === "merge" ? readIncomingHostMap() : undefined;
  const result = reconcileHostRows({
    operation,
    clusterFile: argv[3],
    datastoreDir: argv[4],
    hostname: argv[5],
    incomingHosts,
  });
  console.log(
    `host topology ${result.sha256}: ${result.dynamicRecords} dynamic, ` +
    `${result.written} written, ${result.removed} removed`,
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  try {
    main(process.argv);
  } catch (error) {
    console.error("DATA-ERROR: HOST-TOPOLOGY " + error.message);
    process.exit(113);
  }
}
