// modules/letsencrypt/selftest/handover.test.mjs — the DNS-01 handover state
// machine and the primary: every combination of the rule inputs, the
// dedicated lineage and its explicit deploy on the primary, per-domain
// certificates never overwritten, migration of legacy lineages, issuance cap
// and backoff, leaving with replacement margins, the fallback, and crash
// recovery at every journal step (child processes killed at crash points).
// Run: node modules/letsencrypt/selftest/handover.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { makeBundle, makeCert, makeDomainPem, tmpdir, write, writeClusters, fakeCertbot, sha256 } from "./fixtures.mjs";

const require = createRequire(import.meta.url);
const plan = require("../acmeplan.js");
const DRIVER = new URL("./acmerun-driver.mjs", import.meta.url).pathname;
let checks = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); checks++; };
const ok = (v, m) => { assert.ok(v, m); checks++; };

// ===================================================== (a) every combination
// Independent oracle, written from the rule table: J, R1..R5 in order.
function oracle(c) {
    let s = c.state;
    let w = c.wildcard;
    let install = false;
    let ended = false;
    if (c.bundle) {
        install = true;
        w = c.bundle;
        const good = c.bundle.daysLeft >= c.bundle.lifetimeDays / 3;
        if (s === "LEGACY" && good) s = "WILDCARD";
        else if (s === "FALLBACK") { s = "WILDCARD"; ended = true; }
        else if (s === "LEAVING") s = "WILDCARD";
    }
    if (c.index === "not-dns01" && (s === "WILDCARD" || s === "FALLBACK")) s = "LEAVING";
    let reentered = false;
    if (c.fallback && s === "WILDCARD" && (!w.servable || w.daysLeft <= 7)) { s = "FALLBACK"; reentered = ended; }
    if (!c.fallback && s === "FALLBACK") s = "WILDCARD";
    return { state: s, install, http01: s === "FALLBACK" || s === "LEAVING" ? "bypass" : "gated", retire: s === "LEAVING", reentered };
}

const W = {
    good: { servable: true, daysLeft: 60, lifetimeDays: 90 },
    third: { servable: true, daysLeft: 25, lifetimeDays: 90 },
    d10: { servable: true, daysLeft: 10, lifetimeDays: 90 },
    d5: { servable: true, daysLeft: 5, lifetimeDays: 90 },
    bad: { servable: false, daysLeft: 0, lifetimeDays: 0 },
};
const B = { none: null, low: { servable: true, daysLeft: 5, lifetimeDays: 90 }, good: { servable: true, daysLeft: 89, lifetimeDays: 90 } };
let combos = 0;
for (const state of plan.STATES) {
    for (const index of ["issued", "not-dns01", "pending", "failed", "unavailable"]) {
        for (const bk of Object.keys(B)) {
            if (B[bk] && index !== "issued") continue; // a validated bundle requires an issued entry
            for (const wk of Object.keys(W)) {
                for (const fallback of [false, true]) {
                    const input = { state, index, bundle: B[bk], wildcard: W[wk], fallback };
                    const got = plan.evaluate(input);
                    const want = oracle(input);
                    const label = JSON.stringify({ state, index, bk, wk, fallback });
                    assert.equal(got.state, want.state, "state " + label);
                    assert.equal(got.install, want.install, "install " + label);
                    assert.equal(got.http01, want.http01, "http01 " + label);
                    assert.equal(got.retire, want.retire, "retire " + label);
                    // invariants
                    assert.ok(got.http01 === "gated" || got.http01 === "bypass", "never a hard block " + label);
                    if (!fallback) assert.notEqual(got.state, "FALLBACK", "no FALLBACK when disabled " + label);
                    if (index !== "issued" && index !== "not-dns01" && !fallback) {
                        const s = state === "FALLBACK" ? "WILDCARD" : state;
                        assert.equal(got.state, s, "an unavailable/pending index holds the state " + label);
                    }
                    if (got.state === "FALLBACK") assert.ok(got.alerts.some((a) => /fallback/.test(a.text)), "fallback alert " + label);
                    if (want.reentered) assert.ok(got.events.includes("fallback-re-entered"), "re-entered event " + label);
                    combos++;
                }
            }
        }
    }
}
checks += combos;
ok(combos === 4 * (5 * 1 + 2) * 5 * 2, "combination count " + combos);

// explicit rows of the table
const ev = (x) => plan.evaluate(Object.assign({ state: "WILDCARD", index: "issued", bundle: null, wildcard: W.good, fallback: false }, x));
eq(ev({ state: "LEGACY", bundle: B.good }).state, "WILDCARD", "handover needs a good bundle");
eq(ev({ state: "LEGACY", bundle: B.low }).state, "LEGACY", "a low bundle is installed without handover");
eq(ev({ state: "LEGACY", bundle: B.low }).install, true, "low bundle still installed");
eq(ev({ index: "unavailable", wildcard: W.d5, fallback: true }).state, "FALLBACK", "fallback fires without the index");
eq(ev({ state: "FALLBACK", bundle: B.good, fallback: true }).state, "WILDCARD", "any renewed bundle ends the fallback");
eq(ev({ state: "FALLBACK", bundle: B.low, fallback: true }).events, ["fallback-ended", "fallback-re-entered"], "low bundle: ended then re-entered");
eq(ev({ state: "LEAVING", bundle: B.good }).state, "WILDCARD", "leave cancelled by an issued bundle");
eq(ev({ index: "not-dns01" }).state, "LEAVING", "explicit not-dns01 leaves");
eq(ev({ index: "unavailable" }).state, "WILDCARD", "unavailable index holds");
ok(ev({ wildcard: W.d5 }).alerts.some((a) => /fallback is disabled/.test(a.text)), "expiring alert with fallback off");
ok(ev({ wildcard: W.bad }).alerts.some((a) => /not servable/.test(a.text)), "unservable alert");
eq(ev({ state: "FALLBACK", fallback: false }).state, "WILDCARD", "R4 fallback switched off");

// ===================================================== helpers for integration
function world(hostname, extra) {
    const dir = tmpdir("ho-");
    const env = Object.assign({
        PATH: process.env.PATH,
        SC_ACME_DIR: path.join(dir, "acme"),
        SC_DATASTORE_DIR: path.join(dir, "ds"),
        SC_ADMIN_CERT_DIR: path.join(dir, "admin"),
        SC_LE_LIVE_DIR: path.join(dir, "live"),
        SC_SRV_ROOT: path.join(dir, "srv"),
        SC_CLUSTERS_FILE: writeClusters(dir),
        SC_ACME_HOOK_CONF: path.join(dir, "hook.conf"),
        SC_ACME_HOOK_LOCK: path.join(dir, "hook.lock"),
        SC_ACME_KEY_FILE: path.join(dir, "acme.key"),
        SC_LETSENCRYPT_BIN: fakeCertbot(dir),
        SC_DIG_BIN: "/bin/false",
        SC_COMPANY_DOMAIN: "cdn.test",
        SC_ACME_COMMAND: "regenerate",
        FAKE_LE_LOG: path.join(dir, "le.log"),
        SC_TEST_HOSTNAME: hostname,
    }, extra || {});
    return { dir, env, acme: env.SC_ACME_DIR, ds: env.SC_DATASTORE_DIR };
}

function drive(w, extra) {
    const r = spawnSync("node", [DRIVER], { env: Object.assign({}, w.env, extra || {}), encoding: "utf8" });
    return { code: r.status, out: r.status === 0 ? JSON.parse(r.stdout) : null, stderr: r.stderr };
}

function manifest(w, zones, matching = true) {
    write(path.join(w.acme, "manifest.snapshot.json"), JSON.stringify({ confSha256: "c0ffee", active: true, zones }));
    write(path.join(w.acme, "manifest.live.sha256"), (matching ? "c0ffee" : "deadbeef") + "  -\n");
}

const OURS = ["ns1.cdn.test", "ns2.cdn.test"];
function certbotCalls(w) {
    return fs.existsSync(w.env.FAKE_LE_LOG) ? fs.readFileSync(w.env.FAKE_LE_LOG, "utf8").trim().split("\n").filter(Boolean) : [];
}
function readIndex(w) {
    return JSON.parse(fs.readFileSync(path.join(w.acme, "bundles/index.json"), "utf8")).entries;
}
function mode(file) {
    return (fs.statSync(file).mode & 0o777).toString(8);
}

// ===================================================== (e)(f)(g)(h) primary
{
    const w = world("r2.test", { SC_TEST_SERVED: "a.test,www.a.test,b.test", SC_TEST_STEPS: "primary,serve" });
    manifest(w, [
        { zone: "a.test", container: "a.test", dns01: true, ns: OURS },
        { zone: "b.test", container: "b.test", dns01: true, ns: OURS },
        { zone: "ext.test", container: "ext.test", dns01: true, ns: ["x.example"] },
        { zone: "cust.test", container: "cust.test", dns01: false, reason: "customer _acme-challenge record", ns: OURS },
        { zone: "und.test", container: "und.test", dns01: true, ns: [] },
    ]);
    // migration: a legacy http-01 lineage and a per-domain datastore cert
    write(path.join(w.env.SC_LE_LIVE_DIR, "a.test/fullchain.pem"), "legacy lineage\n");
    const perDomain = makeDomainPem("a.test", 40, ["a.test", "www.a.test"]);
    write(path.join(w.ds, "cert/a.test.pem"), perDomain);
    // container rootfs holding an older certificate
    const pki = path.join(w.env.SC_SRV_ROOT, "a.test/rootfs/etc/pki/tls");
    write(path.join(pki, "certs/localhost.crt"), makeDomainPem("a.test", 10).replace(/-----BEGIN PRIVATE KEY-----[\s\S]+?-----END PRIVATE KEY-----\n/, ""));
    fs.mkdirSync(path.join(pki, "private"), { recursive: true });

    const r = drive(w);
    eq(r.code, 0, "primary run exits 0: " + r.stderr);
    const calls = certbotCalls(w);
    eq(calls.length, 2, "DNS-01 issued for the two eligible zones");
    eq(calls[0], "certonly --non-interactive --agree-tos --manual --preferred-challenges dns --manual-auth-hook " +
        path.join(path.dirname(DRIVER), "../apps/acme-dns-hook.sh") + " auth --manual-cleanup-hook " +
        path.join(path.dirname(DRIVER), "../apps/acme-dns-hook.sh") + " cleanup --cert-name srvctl-wildcard-a.test " +
        "--keep-until-expiring -d a.test -d *.a.test", "exact certbot argv");
    const idx = readIndex(w);
    eq(idx["a.test"].state, "issued", "a.test issued");
    eq(idx["a.test"].sha256, sha256(fs.readFileSync(path.join(w.acme, "bundles/a.test.pem"))), "index sha256 of the bundle");
    eq(mode(path.join(w.acme, "bundles/a.test.pem")), "600", "bundle 0600");
    eq(idx["ext.test"], { state: "not-dns01", kind: "zone", reason: "served by external DNS" }, "external zone");
    eq(idx["cust.test"].state + "/" + idx["cust.test"].reason, "not-dns01/customer _acme-challenge record", "customer record zone");
    eq(idx["und.test"].state, "pending", "undetermined NS: pending, no issuance");
    eq(fs.readFileSync(path.join(w.env.SC_LE_LIVE_DIR, "a.test/fullchain.pem"), "utf8"), "legacy lineage\n", "legacy lineage untouched");
    ok(fs.existsSync(path.join(w.env.SC_LE_LIVE_DIR, "srvctl-wildcard-a.test/fullchain.pem")), "dedicated lineage");
    // explicit deploy on the primary from the dedicated lineage
    eq(r.out.states["a.test"].state, "WILDCARD", "primary hands over its own zone");
    eq(sha256(fs.readFileSync(path.join(w.ds, "cert/wildcard/a.test.pem"))), idx["a.test"].sha256, "installed from the bundle");
    eq(fs.readFileSync(path.join(w.ds, "cert/a.test.pem"), "utf8"), perDomain, "per-domain datastore cert byte-identical");
    eq(r.out.suppressed, { "a.test": true, "www.a.test": true, "b.test": true }, "gate closes for covered names");
    ok(fs.readFileSync(path.join(pki, "certs/a.test.pem"), "utf8").includes("PRIVATE KEY"), "rootfs deployed (later expiry)");
    const hookConf = fs.readFileSync(w.env.SC_ACME_HOOK_CONF, "utf8");
    ok(/^ACME_ZONE=_acme\.cdn\.test$/m.test(hookConf) && /^ACME_SECONDARIES=192\.0\.2\.3$/m.test(hookConf), "hook configuration");
    eq(mode(w.env.SC_ACME_HOOK_CONF), "600", "hook configuration 0600");

    // second run: nothing due, no new certbot call; the lineage is re-published only if newer
    drive(w);
    eq(certbotCalls(w).length, 2, "no re-issuance while more than a third is left");
}
{   // manifest not matching the active configuration: no DNS-01 at all
    const w = world("r2.test", { SC_TEST_STEPS: "primary" });
    manifest(w, [{ zone: "a.test", dns01: true, ns: OURS }], false);
    const r = drive(w);
    eq(certbotCalls(w).length, 0, "mismatch: no issuance");
    eq(r.out.status.dns01.skipped, "manifest mismatch", "mismatch reported");
}
{   // only the primary issues, only on regenerate
    const w = world("h3.test", { SC_TEST_STEPS: "primary", SC_RSYNC_BIN: "/bin/false" });
    manifest(w, [{ zone: "a.test", dns01: true, ns: OURS }]);
    drive(w);
    eq(certbotCalls(w).length, 0, "a non-primary host never issues DNS-01");
    const w2 = world("r2.test", { SC_TEST_STEPS: "primary", SC_ACME_COMMAND: "http-redirect" });
    manifest(w2, [{ zone: "a.test", dns01: true, ns: OURS }]);
    drive(w2);
    eq(certbotCalls(w2).length, 0, "no DNS-01 outside regenerate");
}
{   // cap and backoff
    const w = world("r2.test", { SC_TEST_STEPS: "primary", SC_ACME_MAX_ISSUE_PER_RUN: "1", FAKE_LE_FAIL: "srvctl-wildcard-a.test" });
    manifest(w, [{ zone: "a.test", dns01: true, ns: OURS }, { zone: "b.test", dns01: true, ns: OURS }]);
    drive(w);
    eq(certbotCalls(w).length, 1, "cap: one issuance per run");
    let idx = readIndex(w);
    eq(idx["a.test"].state, "failed", "failed issuance recorded");
    eq(idx["b.test"].lastError, "deferred: per-run issuance cap reached", "cap deferral recorded");
    drive(w, { SC_ACME_MAX_ISSUE_PER_RUN: "5" });
    idx = readIndex(w);
    eq(certbotCalls(w).length, 2, "backoff: a.test not retried, b.test issued");
    eq(idx["a.test"].lastError, "backing off after 1 failure(s)", "backoff reported");
    eq(idx["b.test"].state, "issued", "b.test issued");
}

{   // an unservable bundle already in bundles/ (foreign key, e.g. planted or
    // corrupted after publication) is never advertised and never suppresses
    // renewal: the real primaryPhase renews it from the dedicated lineage
    const w = world("r2.test", { SC_TEST_STEPS: "primary" });
    manifest(w, [{ zone: "x.test", container: "x.test", dns01: true, ns: OURS }]);
    const planted = makeBundle("x.test", { daysAfter: 89, foreignKey: true });
    write(path.join(w.acme, "bundles/x.test.pem"), planted);
    let r = drive(w);
    eq(r.code, 0, "primary with a foreign-key bundle exits 0: " + r.stderr);
    eq(certbotCalls(w).length, 1, "foreign-key bundle does not suppress renewal");
    let idx = readIndex(w);
    const published = fs.readFileSync(path.join(w.acme, "bundles/x.test.pem"), "utf8");
    eq(idx["x.test"].state, "issued", "renewed bundle issued");
    ok(idx["x.test"].sha256 !== sha256(planted) && idx["x.test"].sha256 === sha256(published), "index names the renewed bundle, not the planted one");
    eq(plan.servableManaged(path.join(w.acme, "bundles/x.test.pem"), w.env), "x.test", "published bundle passes the shared gate");
    ok(r.out.status.names["x.test"].alerts.some((a) => /not a servable wildcard; ignored/.test(a.text)), "unservable bundle alerted");

    // the same with issuance failing: failed, and the planted file is not advertised
    const w2 = world("r2.test", { SC_TEST_STEPS: "primary", FAKE_LE_FAIL: "srvctl-wildcard-x.test" });
    manifest(w2, [{ zone: "x.test", container: "x.test", dns01: true, ns: OURS }]);
    write(path.join(w2.acme, "bundles/x.test.pem"), planted);
    r = drive(w2);
    eq(certbotCalls(w2).length, 1, "renewal attempted");
    idx = readIndex(w2);
    eq([idx["x.test"].state, idx["x.test"].sha256], ["failed", undefined], "failed issuance: the unservable bundle is not advertised");
}

// ===================================================== serving-side scenarios
// A primary with a hand-written index (no issuance this run): the same code
// path every serving host runs after pulling.
function served(w, entries, bundles) {
    for (const [name, text] of Object.entries(bundles)) write(path.join(w.acme, "bundles", name + ".pem"), text);
    const idx = {};
    for (const [name, e] of Object.entries(entries)) {
        idx[name] = Object.assign({}, e);
        if (e.state === "issued" && bundles[name]) idx[name].sha256 = sha256(bundles[name]);
    }
    write(path.join(w.acme, "bundles/index.json"), JSON.stringify({ generatedAt: new Date().toISOString(), entries: idx }));
}
const srv = { SC_ACME_COMMAND: "regenerate-disabled", SC_TEST_SERVED: "x.test,www.x.test", SC_TEST_STEPS: "serve,leave" };

{   // (b) leaving: retirement waits for deployed replacements with >= 30 days
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    eq(drive(w).out.states["x.test"].state, "WILDCARD", "handover");
    served(w, { "x.test": { state: "not-dns01", reason: "served by external DNS" } }, {});
    let r = drive(w);
    eq(r.out.states["x.test"].state, "LEAVING", "explicit not-dns01 -> LEAVING");
    eq(r.out.suppressed, { "x.test": false, "www.x.test": false }, "http-01 resumes while leaving");
    ok(fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")), "no replacement: wildcard kept");
    write(path.join(w.ds, "cert/x.test.pem"), makeDomainPem("x.test", 20, ["x.test", "www.x.test"]));
    write(path.join(w.ds, "cert/www.x.test.pem"), makeDomainPem("www.x.test", 60));
    r = drive(w);
    ok(fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")), "replacement with 20 days: kept");
    write(path.join(w.ds, "cert/x.test.pem"), makeDomainPem("x.test", 60, ["x.test", "www.x.test"]));
    r = drive(w);
    eq(r.out.states["x.test"].state, "LEGACY", "replaced with >= 30 days: retired -> LEGACY");
    ok(!fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")) &&
        fs.existsSync(path.join(w.ds, "cert/wildcard-retired/x.test.pem")), "moved to wildcard-retired/");
}
{   // a replacement counts only when haproxy can serve it (key matches)
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    eq(drive(w).out.states["x.test"].state, "WILDCARD", "handover");
    served(w, { "x.test": { state: "not-dns01" } }, {});
    const foreign = (daysAfter, cn, sans) => {
        const c = makeCert({ cn: cn, sans: sans, daysAfter: daysAfter });
        return makeCert({ cn: "foreign.invalid" }).key + c.cert;
    };
    write(path.join(w.ds, "cert/x.test.pem"), foreign(60, "x.test", ["x.test", "www.x.test"]));
    write(path.join(w.ds, "cert/www.x.test.pem"), makeDomainPem("www.x.test", 60));
    let r = drive(w);
    eq(r.out.states["x.test"].state, "LEAVING", "foreign-key per-domain replacement: still LEAVING");
    ok(fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")) &&
        !fs.existsSync(path.join(w.ds, "cert/wildcard-retired/x.test.pem")), "foreign-key replacement: wildcard kept");
    write(path.join(w.env.SC_ADMIN_CERT_DIR, "x/x.test.pem"), foreign(60, "*.x.test"));
    r = drive(w);
    ok(fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")), "foreign-key admin wildcard: not a replacement either");
    // a matching-key admin wildcard whose validity starts in 10 days: the
    // http-01 gate still sees it (admin rule unchanged), but no client
    // accepts it yet, so it is no replacement
    const future = makeCert({ cn: "*.x.test", daysBefore: -10, daysAfter: 60 });
    write(path.join(w.env.SC_ADMIN_CERT_DIR, "x/x.test.pem"), future.cert + future.key);
    eq(plan.wildcardCovering("x.test", Object.assign({}, w.env, { SC_WILDCARD_EXCLUDE: path.join(w.ds, "cert/wildcard/x.test.pem") })),
        path.join(w.env.SC_ADMIN_CERT_DIR, "x/x.test.pem"), "not-yet-valid admin wildcard passes the admin gate as approved");
    ok(plan.keyMatchesLeaf(future.cert + future.key), "not-yet-valid admin wildcard has a matching key");
    r = drive(w);
    eq(r.out.states["x.test"].state, "LEAVING", "not-yet-valid admin wildcard: still LEAVING");
    ok(fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")) &&
        !fs.existsSync(path.join(w.ds, "cert/wildcard-retired/x.test.pem")), "not-yet-valid admin wildcard: managed wildcard kept");
    fs.rmSync(path.join(w.env.SC_ADMIN_CERT_DIR, "x/x.test.pem"));
    write(path.join(w.ds, "cert/x.test.pem"), makeDomainPem("x.test", 60, ["x.test", "www.x.test"]));
    r = drive(w);
    eq(r.out.states["x.test"].state, "LEGACY", "servable replacement with >= 30 days: retired");
}
{   // leaving with a wildcard that is no longer servable: retired at once
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    drive(w);
    write(path.join(w.ds, "cert/wildcard/x.test.pem"), makeBundle("x.test", { daysAfter: 0.5 }));
    served(w, { "x.test": { state: "not-dns01" } }, {});
    eq(drive(w).out.states["x.test"].state, "LEGACY", "unservable leaving wildcard retired without replacement");
}
{   // D-B off: expiring wildcard held and the gate opens only when unservable
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test", { daysBefore: 85, daysAfter: 5 }) });
    let r = drive(w);
    eq(r.out.states["x.test"].state, "LEGACY", "a 5-day bundle is installed but no handover");
    fs.writeFileSync(path.join(w.acme, "handover.json"), JSON.stringify({ version: 1, names: { "x.test": { state: "WILDCARD" } }, pending: null }));
    fs.rmSync(path.join(w.acme, "bundles/index.json"));
    r = drive(w);
    eq(r.out.states["x.test"].state, "WILDCARD", "fallback off: held");
    eq(r.out.suppressed["x.test"], true, "still servable: gate closed");
    ok(r.out.status.names["x.test"].alerts.some((a) => /fallback is disabled/.test(a.text)), "expiring alert");
    write(path.join(w.ds, "cert/wildcard/x.test.pem"), makeBundle("x.test", { daysAfter: 0.5 }));
    r = drive(w);
    eq(r.out.suppressed["x.test"], false, "not servable: http-01 no longer blocked (D-B off)");
    // (d) D-B on: fallback with the index unavailable, then ended by a renewed bundle
    write(path.join(w.ds, "cert/wildcard/x.test.pem"), makeBundle("x.test", { daysBefore: 85, daysAfter: 5 }));
    r = drive(w, { SC_ACME_HTTP01_FALLBACK: "true" });
    eq(r.out.states["x.test"].state, "FALLBACK", "fallback started without an index");
    eq(r.out.suppressed["x.test"], false, "fallback bypasses the gate while the wildcard is still servable");
    ok(r.out.status.names["x.test"].alerts.some((a) => /fallback started/.test(a.text)), "fallback start alert");
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    r = drive(w, { SC_ACME_HTTP01_FALLBACK: "true" });
    eq(r.out.states["x.test"].state, "WILDCARD", "renewed bundle validated: fallback ended");
    eq(r.out.suppressed["x.test"], true, "gate closed again");
}
{   // invalid pulled bundle (sha mismatch) is not installed; the state holds
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    const idx = JSON.parse(fs.readFileSync(path.join(w.acme, "bundles/index.json"), "utf8"));
    idx.entries["x.test"].sha256 = "0".repeat(64);
    fs.writeFileSync(path.join(w.acme, "bundles/index.json"), JSON.stringify(idx));
    const r = drive(w);
    eq(r.out.states["x.test"] ? r.out.states["x.test"].state : "LEGACY", "LEGACY", "sha mismatch: no handover");
    ok(!fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")), "nothing installed");
}

// ===================================================== (c) crash recovery
for (const point of ["install:begun", "install:copied", "save:before-rename", "install:performed"]) {
    const w = world("r2.test", srv);
    const bundle = makeBundle("x.test");
    served(w, { "x.test": { state: "issued" } }, { "x.test": bundle });
    const crashed = drive(w, { SC_ACME_CRASH_AT: point });
    eq(crashed.code, 86, "crashed at " + point);
    const r = drive(w);
    eq(r.code, 0, "recovery run after " + point);
    eq(r.out.states["x.test"].state, "WILDCARD", "consistent state after " + point);
    eq(r.out.pending, null, "journal empty after " + point);
    eq(sha256(fs.readFileSync(path.join(w.ds, "cert/wildcard/x.test.pem"))), sha256(bundle), "installed exactly the bundle after " + point);
    eq(fs.readdirSync(path.join(w.ds, "cert/wildcard")).filter((f) => /\.tmp\./.test(f)), [], "no temporary leftovers after " + point);
}
for (const point of ["retire:begun", "retire:performed"]) {
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    drive(w);
    write(path.join(w.ds, "cert/wildcard/x.test.pem"), makeBundle("x.test", { daysAfter: 0.5 }));
    served(w, { "x.test": { state: "not-dns01" } }, {});
    eq(drive(w, { SC_ACME_CRASH_AT: point }).code, 86, "crashed at " + point);
    const r = drive(w);
    eq(r.out.states["x.test"].state, "LEGACY", "retirement healed after " + point);
    ok(!fs.existsSync(path.join(w.ds, "cert/wildcard/x.test.pem")) &&
        fs.existsSync(path.join(w.ds, "cert/wildcard-retired/x.test.pem")), "file retired once after " + point);
}
{   // .bak restore and rebuild from disk
    const w = world("r2.test", srv);
    served(w, { "x.test": { state: "issued" } }, { "x.test": makeBundle("x.test") });
    drive(w);
    drive(w); // second save leaves a .bak
    fs.writeFileSync(path.join(w.acme, "handover.json"), "{ torn");
    let r = drive(w);
    eq(r.out.states["x.test"].state, "WILDCARD", "restored from .bak");
    ok(r.out.status.alerts.some((a) => /restored from/.test(a.text)), "restore alert");
    fs.writeFileSync(path.join(w.acme, "handover.json"), "{ torn");
    fs.writeFileSync(path.join(w.acme, "handover.json.bak"), "{ torn");
    fs.rmSync(path.join(w.acme, "bundles/index.json"));
    r = drive(w);
    eq(r.out.states["x.test"].state, "WILDCARD", "rebuilt from the installed servable wildcard");
    ok(r.out.status.alerts.some((a) => /rebuilt/.test(a.text)), "rebuild alert");
}

// ===================================================== host names (AC5)
function hostWorld(extra) {
    const w = world("h3.test", Object.assign({ SC_RSYNC_BIN: "/bin/false", SC_TEST_SERVED: "h3.test",
        SC_TEST_STEPS: "serve,host", SC_TEST_HOST_IP: "192.0.2.4", SC_ACME_COMMAND: "regenerate" }, extra || {}));
    write(path.join(w.acme, "host-dns.json"), JSON.stringify({ "h3.test": { A: ["192.0.2.4"], NS: ["a.iana-servers.net"], state: "OK" } }));
    return w;
}
{
    const w = hostWorld();
    let r = drive(w);
    eq(r.out.status.domains["h3.test"].outcome, "issued", "host name on external DNS: http-01 issued");
    eq(r.out.status.domains["h3.test"].class, "external", "host name classified");
    eq(certbotCalls(w), ["certonly --non-interactive --agree-tos --keep-until-expiring --webroot --webroot-path /var/acme/ --cert-name h3.test -d h3.test"],
        "host webroot argv");
    eq(mode(path.join(w.ds, "cert/h3.test.pem")), "600", "deployed to the datastore 0600 (served by certselect)");
    r = drive(w);
    eq(r.out.status.domains["h3.test"].outcome, "valid certificate", "not re-issued while valid");
    eq(certbotCalls(w).length, 1, "one issuance");
}
{
    const w = hostWorld();
    const wc = makeCert({ cn: "*.test", daysAfter: 30 });
    write(path.join(w.env.SC_ADMIN_CERT_DIR, "test/test.pem"), wc.cert + wc.key);
    eq(drive(w).out.status.domains["h3.test"].outcome, "covered by a servable wildcard", "covered host name: skipped");
    const old = makeCert({ cn: "*.test", daysBefore: 100, daysAfter: -1 });
    write(path.join(w.env.SC_ADMIN_CERT_DIR, "test/test.pem"), old.cert + old.key);
    eq(drive(w).out.status.domains["h3.test"].outcome, "issued", "expired wildcard never blocks http-01");
}
{
    const w = hostWorld({ SC_TEST_HOST_IP: "192.0.2.99" });
    eq(drive(w).out.status.domains["h3.test"].outcome, "A record does not point here", "A elsewhere: skipped");
    const w2 = hostWorld({ SC_ACME_HTTP01_AVAILABLE: "false" });
    const r = drive(w2);
    eq(r.out.status.domains["h3.test"].outcome, "http-01 unavailable", "acme-server down: no attempt");
    ok(r.out.status.names["h3.test"].alerts.some((a) => /acme-server not running/.test(a.text)), "acme-server down: alert");
}

console.log("handover.test: " + checks + " checks passed (" + combos + " rule combinations)");
