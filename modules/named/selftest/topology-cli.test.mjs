// Run: node modules/named/selftest/topology-cli.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const cli = new URL("../lib/topology-cli.js", import.meta.url).pathname;
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "srvctl-dns-topology-cli-"));

function run(config) {
    const configPath = path.join(temporaryRoot, "clusters.json");
    fs.writeFileSync(configPath, JSON.stringify(config));
    return spawnSync(process.execPath, [cli, configPath], { encoding: "utf8" });
}

try {
    const elected = run({
        one: {
            ordinary: { host_ip: "192.0.2.1" },
            old: { host_ip: "192.0.2.2", dns_server: "master" },
        },
        two: {
            canonical: {
                host_ip: "192.0.2.3",
                dns_server: "master",
                dns_primary: true,
            },
            secondary: { host_ip: "192.0.2.4", dns_server: "slave" },
        },
    });
    assert.equal(elected.status, 0);
    assert.equal(elected.stderr, "");
    assert.equal(elected.stdout,
        "primary\tcanonical\nreplica\told\nreplica\tsecondary\n");

    const noDns = run({ cluster: { app: { host_ip: "192.0.2.5" } } });
    assert.equal(noDns.status, 0);
    assert.equal(noDns.stdout, "");
    assert.equal(noDns.stderr, "");

    const misplacedMarker = run({ cluster: {
        app: { host_ip: "192.0.2.50", dns_primary: true },
    } });
    assert.equal(misplacedMarker.status, 111);
    assert.match(misplacedMarker.stderr, /dns_primary=true requires dns_server=master/);
    assert.equal(misplacedMarker.stdout, "");

    const invalid = run({ cluster: {
        a: { host_ip: "192.0.2.6", dns_server: "slave" },
    } });
    assert.equal(invalid.status, 111);
    assert.match(invalid.stderr, /^DATA-ERROR: DNS topology:/);
    assert.equal(invalid.stdout, "",
        "invalid topology must not emit a partial ordering");

    const ambiguous = run({ cluster: {
        a: { host_ip: "192.0.2.7", dns_server: "master" },
        b: { host_ip: "192.0.2.8", dns_server: "master" },
    } });
    assert.equal(ambiguous.status, 111);
    assert.match(ambiguous.stderr, /multiple DNS masters require exactly one dns_primary=true/);
    assert.equal(ambiguous.stdout, "");
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("topology-cli.test: passed");
