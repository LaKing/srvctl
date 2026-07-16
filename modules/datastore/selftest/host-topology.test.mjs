// Canonical host topology + dynamic-only datastore ownership tests.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { createStore } from "../lib/store.mjs";
import { reconcileHostRows } from "../lib/reconcile-hosts.mjs";

const require = createRequire(import.meta.url);
const hostTopology = require("../lib/host-topology.js");
const HERE = path.dirname(fileURLToPath(import.meta.url));
const MAIN = path.join(HERE, "..", "main.mjs");
const LEGACY_LIB = path.join(HERE, "..", "lib.js");

let passed = 0;
const failures = [];

function test(name, fn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sc-host-topology-"));
  try {
    fn(root);
    passed++;
    console.log(`  ok  ${name}`);
  } catch (error) {
    failures.push({ name, error });
    console.log(`FAIL  ${name}\n      ${error.stack || error}`);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function fixture(root, topology = undefined) {
  const clusterFile = path.join(root, "cluster-topology.fixture.json");
  const datastoreDir = path.join(root, "datastore");
  const clusters = topology || {
    farm: {
      "alpha.test": {
        hostnet: 40,
        host_ip: "192.0.2.40",
        dns_server: "master",
      },
      "beta.test": {
        hostnet: 41,
        host_ip: "192.0.2.41",
      },
    },
    other: {
      "other.test": { hostnet: 90, host_ip: "192.0.2.90" },
    },
  };
  fs.writeFileSync(clusterFile, JSON.stringify(clusters, null, 2) + "\n");
  fs.mkdirSync(path.join(datastoreDir, "hosts"), { recursive: true });
  fs.mkdirSync(path.join(datastoreDir, "users"), { recursive: true });
  fs.mkdirSync(path.join(datastoreDir, "containers"), { recursive: true });
  fs.writeFileSync(path.join(datastoreDir, ".per-entity"), "");
  return { clusterFile, datastoreDir };
}

function topologyOptions(clusterFile) {
  return { clusterFile, hostname: "alpha.test" };
}

function childEnv(clusterFile, datastoreDir, readOnly = false) {
  return {
    ...process.env,
    SC_DATASTORE_DIR: datastoreDir,
    SC_DATASTORE_RO_USE: readOnly ? "true" : "false",
    SC_HOSTNET: "40",
    SC_USER: "root",
    USER: "root",
    SRVCTL_SELFTEST: "true",
    SRVCTL_SELFTEST_CLUSTERS_FILE: clusterFile,
    SRVCTL_SELFTEST_HOSTNAME: "alpha.test",
  };
}

test("canonical add/update/remove wins while explicit dynamic keys survive", (root) => {
  const { clusterFile } = fixture(root);
  const stored = {
    "alpha.test": {
      hostnet: 7,
      host_ip: "198.51.100.7",
      gateway: "stale",
      host_key: "RUNTIME",
      "host-key-rsa": "RSA",
      "host-key-future": "must-not-survive",
    },
    "removed.test": {
      hostnet: 8,
      host_ip: "198.51.100.8",
      host_key: "REMOVED",
    },
  };

  const result = hostTopology.overlayStoredHosts(stored, topologyOptions(clusterFile)).hosts;
  assert.deepEqual(Object.keys(result), ["alpha.test", "beta.test"]);
  assert.deepEqual(result["alpha.test"], {
    hostnet: 40,
    host_ip: "192.0.2.40",
    dns_server: "master",
    host_key: "RUNTIME",
    "host-key-rsa": "RSA",
  });
  assert.deepEqual(result["beta.test"], {
    hostnet: 41,
    host_ip: "192.0.2.41",
  });
});

test("read-only stale datastore is overlaid without mutation", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  const store = createStore(datastoreDir, { git: false });
  store.write("hosts", "alpha.test", {
    hostnet: 1,
    host_ip: "203.0.113.1",
    host_key: "KEY",
  });
  store.write("hosts", "removed.test", { hostnet: 2, host_ip: "203.0.113.2" });
  const before = fs.readFileSync(path.join(datastoreDir, "hosts", "alpha.test.json"), "utf8");

  const main = spawnSync(process.execPath, [MAIN, "get", "host", "alpha.test", "host_ip"], {
    env: childEnv(clusterFile, datastoreDir, true),
    encoding: "utf8",
  });
  assert.equal(main.status, 0, main.stderr);
  assert.equal(main.stdout, "192.0.2.40\n");

  const added = spawnSync(process.execPath, [MAIN, "get", "host", "beta.test", "hostnet"], {
    env: childEnv(clusterFile, datastoreDir, true),
    encoding: "utf8",
  });
  assert.equal(added.status, 0, added.stderr);
  assert.equal(added.stdout, "41\n");

  const removed = spawnSync(process.execPath, [MAIN, "get", "host", "removed.test", "host_ip"], {
    env: childEnv(clusterFile, datastoreDir, true),
    encoding: "utf8",
  });
  assert.equal(removed.status, 110);
  assert.match(removed.stderr, /HOST removed\.test DONT EXISTS/);
  assert.equal(
    fs.readFileSync(path.join(datastoreDir, "hosts", "alpha.test.json"), "utf8"),
    before,
  );
});

test("read-only pre-migration monolith is also only a dynamic overlay", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  fs.rmSync(path.join(datastoreDir, ".per-entity"));
  fs.rmSync(path.join(datastoreDir, "hosts"), { recursive: true });
  fs.writeFileSync(path.join(datastoreDir, "hosts.json"), JSON.stringify({
    "alpha.test": {
      hostnet: 3,
      host_ip: "203.0.113.3",
      host_key: "MONOLITH-KEY",
    },
    "removed.test": { hostnet: 4, host_ip: "203.0.113.4" },
  }));

  const child = spawnSync(process.execPath, [MAIN, "out", "host", "alpha.test"], {
    env: childEnv(clusterFile, datastoreDir, true),
    encoding: "utf8",
  });
  assert.equal(child.status, 0, child.stderr);
  assert.match(child.stdout, /SC_HOST_IP='192\.0\.2\.40'/);
  assert.match(child.stdout, /SC_HOSTNET='40'/);
  assert.match(child.stdout, /SC_HOST_KEY='MONOLITH-KEY'/);
  assert.doesNotMatch(child.stdout, /203\.0\.113\.3/);
});

test("RW reconciliation removes static and orphan rows transactionally", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  const store = createStore(datastoreDir, { git: false });
  store.write("hosts", "alpha.test", {
    hostnet: 7,
    host_ip: "198.51.100.7",
    interface: "stale0",
    host_key: "KEY",
    "host-key-rsa": "RSA",
    "host-key-future": "DROP",
  });
  store.write("hosts", "beta.test", { hostnet: 8, host_ip: "198.51.100.8" });
  store.write("hosts", "removed.test", { host_key: "ORPHAN" });

  reconcileHostRows({
    clusterFile,
    datastoreDir,
    hostname: "alpha.test",
  });

  assert.deepEqual(store.readAll("hosts"), {
    "alpha.test": { host_key: "KEY", "host-key-rsa": "RSA" },
  });
  const visible = hostTopology.overlayStoredHosts(
    store.readAll("hosts"),
    topologyOptions(clusterFile),
  ).hosts;
  assert.equal(visible["alpha.test"].host_ip, "192.0.2.40");
  assert.equal(visible["beta.test"].hostnet, 41);
});

test("dynamic merge is locked, additive, and never persists static input", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  const store = createStore(datastoreDir, { git: false });
  store.write("hosts", "alpha.test", {
    host_ip: "stale",
    "host-key-rsa": "RSA",
  });

  reconcileHostRows({
    operation: "merge",
    clusterFile,
    datastoreDir,
    hostname: "alpha.test",
    incomingHosts: {
      "alpha.test": {
        hostnet: 999,
        host_ip: "stale-again",
        host_key: "NEW",
        "host-key-future": "DROP",
      },
      "beta.test": {
        hostnet: 999,
        "host-key-ed25519": "ED25519",
      },
      "removed.test": { host_key: "DROP" },
    },
  });

  assert.deepEqual(store.readAll("hosts"), {
    "alpha.test": { host_key: "NEW", "host-key-rsa": "RSA" },
    "beta.test": { "host-key-ed25519": "ED25519" },
  });
});

test("invalid owned dynamic value aborts without partial cleanup", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  const store = createStore(datastoreDir, { git: false });
  store.write("hosts", "alpha.test", { host_key: 42, host_ip: "stale" });
  store.write("hosts", "removed.test", { host_key: "KEEP-ON-FAIL" });
  const before = store.readAll("hosts");

  assert.throws(() => reconcileHostRows({
    clusterFile,
    datastoreDir,
    hostname: "alpha.test",
  }), /host_key must be a NUL-free string/);
  assert.deepEqual(store.readAll("hosts"), before);
});

test("legacy lib consumer overlays canonical and persists host keys only", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  const store = createStore(datastoreDir, { git: false });
  store.write("hosts", "alpha.test", { hostnet: 1, host_ip: "stale" });

  const program = [
    `const lib = require(${JSON.stringify(LEGACY_LIB)});`,
    `if (lib.hosts["alpha.test"].host_ip !== "192.0.2.40") process.exit(21);`,
    `if (lib.hosts["beta.test"].hostnet !== 41) process.exit(22);`,
    `lib.hosts["alpha.test"].host_key = "SCANNED";`,
    `lib.save_type("hosts", lib.hosts);`,
  ].join("\n");
  const child = spawnSync(process.execPath, ["-e", program], {
    env: childEnv(clusterFile, datastoreDir, false),
    encoding: "utf8",
  });
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(store.readAll("hosts"), {
    "alpha.test": { host_key: "SCANNED" },
  });
});

test("legacy host-key save never mutates an effective RO datastore", (root) => {
  const { clusterFile, datastoreDir } = fixture(root);
  const store = createStore(datastoreDir, { git: false });
  store.write("hosts", "alpha.test", { host_key: "OLD", host_ip: "stale" });
  const before = fs.readFileSync(path.join(datastoreDir, "hosts", "alpha.test.json"), "utf8");
  const program = [
    `const lib = require(${JSON.stringify(LEGACY_LIB)});`,
    `lib.hosts["alpha.test"].host_key = "MUST-NOT-PERSIST";`,
    `lib.save_type("hosts", lib.hosts);`,
  ].join("\n");
  const child = spawnSync(process.execPath, ["-e", program], {
    env: childEnv(clusterFile, datastoreDir, true),
    encoding: "utf8",
  });
  assert.equal(child.status, 0, child.stderr);
  assert.equal(
    fs.readFileSync(path.join(datastoreDir, "hosts", "alpha.test.json"), "utf8"),
    before,
  );
});

test("canonical host_key is rejected as datastore-owned", (root) => {
  const topology = {
    farm: {
      "alpha.test": {
        hostnet: 40,
        host_ip: "192.0.2.40",
        host_key: "MUST-NOT-BE-STATIC",
      },
    },
  };
  const { clusterFile } = fixture(root, topology);
  assert.throws(
    () => hostTopology.readCanonicalHostTopology(topologyOptions(clusterFile)),
    /datastore-owned key "host_key"/,
  );
});

test("validated hostname bootstrap target replaces the transient OS hostname", () => {
  assert.deepEqual(hostTopology.runtimeTopologyOptions({
    SC_CLUSTER_HOSTNAME_BOOTSTRAP: "true",
    SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME: "future.test",
  }), { hostname: "future.test" });
  assert.throws(() => hostTopology.runtimeTopologyOptions({
    SC_CLUSTER_HOSTNAME_BOOTSTRAP: "true",
  }), /missing its validated target hostname/);
});

test("generation pin: matching invocation pin is accepted", (root) => {
  const { clusterFile } = fixture(root);
  const options = { clusterFile, hostname: "alpha.test" };
  const unpinned = hostTopology.readCanonicalHostTopology(options);
  process.env.SC_CANONICAL_CLUSTERS_SHA256 = unpinned.sha256;
  try {
    const pinned = hostTopology.readCanonicalHostTopology(options);
    assert.equal(pinned.sha256, unpinned.sha256);
  } finally {
    delete process.env.SC_CANONICAL_CLUSTERS_SHA256;
  }
});

test("generation pin: canonical replaced after dispatch is refused", (root) => {
  const { clusterFile } = fixture(root);
  const options = { clusterFile, hostname: "alpha.test" };
  const unpinned = hostTopology.readCanonicalHostTopology(options);
  process.env.SC_CANONICAL_CLUSTERS_SHA256 = unpinned.sha256;
  try {
    fs.appendFileSync(clusterFile, "\n");
    assert.throws(
      () => hostTopology.readCanonicalHostTopology(options),
      /generation changed during this invocation/,
    );
  } finally {
    delete process.env.SC_CANONICAL_CLUSTERS_SHA256;
  }
});

test("generation pin: non-hex pin values are ignored", (root) => {
  const { clusterFile } = fixture(root);
  const options = { clusterFile, hostname: "alpha.test" };
  process.env.SC_CANONICAL_CLUSTERS_SHA256 = "none";
  try {
    const topology = hostTopology.readCanonicalHostTopology(options);
    assert.equal(topology.clusterName, "farm");
  } finally {
    delete process.env.SC_CANONICAL_CLUSTERS_SHA256;
  }
});

console.log(`host-topology.test: ${passed} passed, ${failures.length} failed`);
for (const failure of failures) {
  console.log(`  FAIL ${failure.name}: ${failure.error.stack || failure.error}`);
}
process.exit(failures.length ? 1 : 0);
