// Run: node modules/letsencrypt/selftest/http01-cap.test.mjs
// A full letsencrypt.js run over 15 placeholder domains that point at this
// host: self-issued placeholders go on to issuance, at most
// SC_ACME_HTTP01_MAX_PER_RUN certbot calls run per run (default 10), and the
// random container order gives every domain a turn across runs. certbot is a
// stub; the DNS-01 phases run against empty fixture dirs.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { REPO, tmpdir, makeCert } from "./fixtures.mjs";

const dir = tmpdir("http01-cap-");
let checks = 0;
const ok = (actual, expected, what) => { assert.equal(actual, expected, what); checks++; };
try {
    const ds = path.join(dir, "ds");
    fs.mkdirSync(path.join(ds, "cert"), { recursive: true });
    // this host, as the datastore topology sees it (the selftest override)
    fs.writeFileSync(path.join(dir, "clusters.json"), JSON.stringify({ c1: { [os.hostname()]: { host_ip: "192.0.2.1" } } }));
    fs.writeFileSync(path.join(ds, "users.json"), "{}");
    const placeholder = makeCert({ cn: "placeholder.test", daysAfter: 3650 });
    const containers = {};
    for (let i = 0; i < 15; i++) {
        const name = "c" + i + ".cap.test";
        containers[name] = { dns: { [name]: { A: ["192.0.2.1"], NS: [] } } };
        fs.writeFileSync(path.join(ds, "cert", name + ".pem"), placeholder.key + placeholder.cert);
    }
    fs.writeFileSync(path.join(ds, "containers.json"), JSON.stringify(containers));
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    for (const b of ["letsencrypt", "dig", "rsync"]) fs.writeFileSync(path.join(bin, b), "#!/bin/sh\nexit 1\n", { mode: 0o755 });

    const run = (extra) => execFileSync("node", [path.join(REPO, "modules/letsencrypt/letsencrypt.js")], {
        encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
        env: {
            ...process.env, PATH: bin + ":" + process.env.PATH, SC_DATASTORE_DIR: ds,
            SRVCTL_SELFTEST: "true", SRVCTL_SELFTEST_CLUSTERS_FILE: path.join(dir, "clusters.json"),
            SRVCTL_SELFTEST_HOSTNAME: os.hostname(),
            SC_ACME_DIR: path.join(dir, "acme"), SC_CLUSTERS_FILE: path.join(dir, "clusters.json"),
            SC_LE_LIVE_DIR: path.join(dir, "live"), SC_SRV_ROOT: path.join(dir, "srv"),
            SC_ACME_HOOK_LOCK: path.join(dir, "hook.lock"), SC_LETSENCRYPT_BIN: path.join(bin, "letsencrypt"),
            SC_DIG_BIN: path.join(bin, "dig"), SC_RSYNC_BIN: path.join(bin, "rsync"),
            SC_ACME_HTTP01_MAX_PER_RUN: "", ...extra,
        },
    });
    const attempted = (out) => out.split("\n").filter((l) => l.includes("-->")).map((l) => l.match(/c\d+\.cap\.test/)[0]);
    const deferred = (out) => (out.match(/deferred: /g) || []).length;

    let out = run({});
    ok(attempted(out).length, 10, "default cap: 10 certbot calls");
    ok(deferred(out), 5, "the other 5 due domains are deferred");
    out = run({ SC_ACME_HTTP01_MAX_PER_RUN: "3" });
    ok(attempted(out).length, 3, "configured cap is honoured");
    ok(deferred(out), 12, "the rest is deferred");
    out = run({ SC_ACME_HTTP01_MAX_PER_RUN: "junk" });
    ok(attempted(out).length, 10, "an invalid cap falls back to 10");
    const seen = new Set();
    for (let r = 0; r < 25; r++) attempted(run({ SC_ACME_HTTP01_MAX_PER_RUN: "3" })).forEach((n) => seen.add(n));
    ok(seen.size, 15, "every domain gets a turn across runs");
    console.log("http01-cap: " + checks + " checks passed");
} finally {
    fs.rmSync(dir, { recursive: true, force: true });
}
