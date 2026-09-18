// modules/letsencrypt/selftest/distribute.test.mjs — serving hosts pull
// issued wildcards from the DNS primary (rsync over ssh, stubbed) and install
// them only after validation: sha256 against the index, the shared servable
// rule (key match, SAN name + *.name, validity) and a later expiry than the
// installed one. Failed pulls and a stale index hold the current state; a
// crash in the middle of an install is replayed on the next run.
// Run: node modules/letsencrypt/selftest/distribute.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { makeBundle, tmpdir, write, writeClusters, fakeRsync, sha256 } from "./fixtures.mjs";

const DRIVER = new URL("./acmerun-driver.mjs", import.meta.url).pathname;
let checks = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); checks++; };
const ok = (v, m) => { assert.ok(v, m); checks++; };

function world() {
    const dir = tmpdir("dist-");
    const env = {
        PATH: process.env.PATH,
        SC_ACME_DIR: path.join(dir, "acme"),
        SC_DATASTORE_DIR: path.join(dir, "ds"),
        SC_ADMIN_CERT_DIR: path.join(dir, "admin"),
        SC_LE_LIVE_DIR: path.join(dir, "live"),
        SC_SRV_ROOT: path.join(dir, "srv"),
        SC_CLUSTERS_FILE: writeClusters(dir),
        SC_RSYNC_BIN: fakeRsync(dir),
        FAKE_REMOTE: path.join(dir, "remote"),
        FAKE_RSYNC_LOG: path.join(dir, "rsync.log"),
        SC_COMPANY_DOMAIN: "cdn.test",
        SC_TEST_HOSTNAME: "h3.test",
        SC_TEST_SERVED: "x.test,www.x.test,y.test",
        SC_TEST_STEPS: "serve",
    };
    return { dir, env, ds: env.SC_DATASTORE_DIR, remote: path.join(env.FAKE_REMOTE, env.SC_ACME_DIR, "bundles") };
}

// publish on the fake primary: bundles + index (sha of what is listed)
function publish(w, bundles, { generatedAt, shaOverride } = {}) {
    const entries = {};
    for (const [name, text] of Object.entries(bundles)) {
        write(path.join(w.remote, name + ".pem"), text);
        entries[name] = { state: "issued", sha256: (shaOverride || {})[name] || sha256(text), kind: "zone" };
    }
    write(path.join(w.remote, "index.json"), JSON.stringify({ generatedAt: generatedAt || new Date().toISOString(), entries }));
}

function drive(w, extra) {
    const r = spawnSync("node", [DRIVER], { env: Object.assign({}, w.env, extra || {}), encoding: "utf8" });
    return { code: r.status, out: r.status === 0 ? JSON.parse(r.stdout) : null, stderr: r.stderr };
}
const installed = (w, name) => path.join(w.ds, "cert/wildcard", name + ".pem");
const alerts = (r, name) => (r.out.status.names[name] || { alerts: [] }).alerts.map((a) => a.text).join("|");

{   // valid bundle: pulled over ssh from the primary and installed 0600
    const w = world();
    const b = makeBundle("x.test");
    publish(w, { "x.test": b });
    const r = drive(w);
    eq(r.code, 0, "run ok " + r.stderr);
    eq(r.out.states["x.test"].state, "WILDCARD", "handover on the serving host");
    eq(sha256(fs.readFileSync(installed(w, "x.test"))), sha256(b), "installed the pulled bundle");
    eq((fs.statSync(installed(w, "x.test")).mode & 0o777).toString(8), "600", "installed 0600");
    const log = fs.readFileSync(w.env.FAKE_RSYNC_LOG, "utf8");
    ok(log.includes("ssh -o BatchMode=yes -o ConnectTimeout=5") && log.includes("root@r2.test:"), "pull from the elected primary over ssh");
    eq(r.out.suppressed["www.x.test"], true, "covered names suppressed");
    eq(r.out.suppressed["y.test"], false, "unrelated name not suppressed");

    // a failed pull with a still-fresh index keeps everything
    let r2 = drive(w, { FAKE_RSYNC_FAIL: "1" });
    eq(r2.out.states["x.test"].state, "WILDCARD", "failed pull holds the state");
    ok(r2.out.status.alerts.some((a) => /could not pull index/.test(a.text)), "failed pull alert");
    // a stale index: unavailable -> hold, with an alert
    publish(w, { "x.test": b }, { generatedAt: new Date(Date.now() - 30 * 3600000).toISOString() });
    r2 = drive(w);
    eq(r2.out.states["x.test"].state, "WILDCARD", "stale index holds");
    ok(/holding WILDCARD/.test(alerts(r2, "x.test")), "holding alert");
    ok(fs.existsSync(installed(w, "x.test")), "wildcard kept during the outage");
}
{   // rejections: nothing installed, state unchanged
    const cases = {
        "sha mismatch": (w) => publish(w, { "x.test": makeBundle("x.test") }, { shaOverride: { "x.test": "0".repeat(64) } }),
        "foreign key": (w) => publish(w, { "x.test": makeBundle("x.test", { foreignKey: true }) }),
        "no *.name in SAN": (w) => publish(w, { "x.test": makeBundle("x.test", { sans: ["x.test"] }) }),
        "expired": (w) => publish(w, { "x.test": makeBundle("x.test", { daysBefore: 100, daysAfter: -1 }) }),
    };
    for (const [label, setup] of Object.entries(cases)) {
        const w = world();
        setup(w);
        const r = drive(w);
        ok(!fs.existsSync(installed(w, "x.test")), label + ": not installed");
        eq(r.out.states["x.test"] ? r.out.states["x.test"].state : "LEGACY", "LEGACY", label + ": no handover");
        eq(r.out.suppressed["x.test"], false, label + ": http-01 not suppressed");
    }
}
{   // an older bundle never replaces a newer installed one
    const w = world();
    const newer = makeBundle("x.test", { daysAfter: 89 });
    publish(w, { "x.test": newer });
    drive(w);
    publish(w, { "x.test": makeBundle("x.test", { daysAfter: 40 }) });
    drive(w);
    eq(sha256(fs.readFileSync(installed(w, "x.test"))), sha256(newer), "older bundle ignored");
}
{   // crash in the middle of the install: replayed on the next run
    const w = world();
    const b = makeBundle("x.test");
    publish(w, { "x.test": b });
    eq(drive(w, { SC_ACME_CRASH_AT: "install:copied" }).code, 86, "crashed mid-install");
    const r = drive(w, { FAKE_RSYNC_FAIL: "1" });
    eq(r.out.states["x.test"].state, "WILDCARD", "replayed from the journal even without a pull");
    eq(sha256(fs.readFileSync(installed(w, "x.test"))), sha256(b), "installed exactly once");
}

console.log("distribute.test: " + checks + " checks passed");
