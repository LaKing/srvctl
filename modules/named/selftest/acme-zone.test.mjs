// modules/named/selftest/acme-zone.test.mjs — the DNS-01 challenge zone as
// named.js renders it: the _acme-challenge CNAME per generated zone (base
// container target, shared by aliases), never over a customer record and
// never with an invalid target; the TSIG-restricted dynamic _acme zone on the
// primary with the same transfer ACL as every regular zone; the slave zone on
// replicas; regular zones static; the manifest bound to the rendered config.
// Run: node modules/named/selftest/acme-zone.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import crypto from "node:crypto";
import { createRequire } from "node:module";
import vm from "node:vm";
import net from "node:net";

const require = createRequire(import.meta.url);
const acme = require("../lib/acmezone.js");
const { SERIAL_PLACEHOLDER, planZoneUpdate } = require("../lib/zonefile.js");
let checks = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); checks++; };
const ok = (v, m) => { assert.ok(v, m); checks++; };

// --- lib -------------------------------------------------------------------
eq(acme.acmeZoneName("d250.hu"), "_acme.d250.hu", "zone name");
eq(acme.challengeTarget("shop.example", "d250.hu"), "shop.example._acme.d250.hu", "target");
eq(acme.challengeTarget("a".repeat(64) + ".example", "d250.hu"), null, "overlong label");
eq(acme.challengeTarget(("a".repeat(60) + ".").repeat(4) + "example", "d250.hu"), null, "overlong name");
eq(acme.hasCustomerChallengeRecord({ dns_records: [{ name: "_acme-challenge", type: "TXT" }] }, ["x.test"]), true, "relative customer record");
eq(acme.hasCustomerChallengeRecord({ dns_records: [{ name: "_acme-challenge.alias.test.", type: "CNAME" }] }, ["x.test", "alias.test"]), true, "absolute record in an alias zone");
eq(acme.hasCustomerChallengeRecord({ dns_records: [{ name: "_acme-challenge.sub", type: "TXT" }] }, ["x.test"]), false, "deeper names do not conflict");
eq(acme.hasCustomerChallengeRecord({ dns_records: [{ name: "_dmarc" }] }, ["x.test"]), false, "other records");
eq(acme.hasCustomerChallengeRecord({}, ["x.test"]), false, "no records");
eq(acme.challengePlan({ dns_records: [{ name: "_acme-challenge" }] }, "x.test", [], "d250.hu"),
    { cname: false, target: null, reason: "customer _acme-challenge record" }, "customer record kept");
eq(acme.challengePlan({}, "x.test", ["y.test"], "d250.hu"), { cname: true, target: "x.test._acme.d250.hu", reason: null }, "plan");
eq(acme.challengeLine("x.test._acme.d250.hu"), "_acme-challenge        IN        CNAME        x.test._acme.d250.hu.\n", "line");
const conf = "zone text\n";
eq(acme.buildManifest({ generatedAt: "t", cdn: "d250.hu", active: true, conf, zones: [] }).confSha256,
    crypto.createHash("sha256").update(conf).digest("hex"), "manifest bound to the rendered configuration");

// --- named.js render (same vm-slice technique as local-containers.test) ----
const src = fs.readFileSync(new URL("../named.js", import.meta.url), "utf8");
const slice = (from, to) => {
    const a = src.indexOf(from);
    const b = src.indexOf(to, a);
    assert.ok(a >= 0 && b > a, "slice " + from);
    return src.slice(a, b);
};
const renderSrc = slice("function get_container_zone(", "\nfunction make_conf()");
const acmeConfSrc = slice("function acme_zone_conf(", "\n}\n") + "\n}\n";

function context(overrides) {
    return Object.assign({
        HOSTNAME: "r2.test", CDN: "company.test", br: "\n", tab: "\t",
        ACME_ZONE: "_acme.company.test", ACME_KEY_FILE: "/var/named/srvctl-acme.key",
        ACME_SEED_FILE: "/var/named/dynamic/_acme.company.test.zone",
        clusters: { c1: { "r2.test": { host_ip: "192.0.2.10" } } },
        datastore: {
            containers: {
                "shop.example": {
                    aliases: ["shop-alias.example"],
                    dns: { "shop.example": { NS: ["ns1.company.test", "ns2.company.test"] } },
                },
                "cust.example": { dns_records: [{ name: "_acme-challenge", type: "TXT", data: "\"customer\"" }] },
                [("a".repeat(60) + ".").repeat(4) + "example"]: {},
            },
        },
        peer_container_snapshots: {},
        fs: { readFileSync() { const e = new Error("none"); e.code = "ENOENT"; throw e; } },
        is_master: true, listed_domain_names: [],
        master_servers: "192.0.2.10;", replica_servers: "192.0.2.54;", replica_transfer_clients: "198.51.100.54;",
        dns_topology: { primaryAclIp: "192.0.2.10", primary: { config: {} } },
        local_dns_host: { config: {} },
        soa_primary_name: "ns1.company.test", net, planZoneUpdate, SERIAL_PLACEHOLDER,
        acmezoneLib: acme, acme_active: true, acme_manifest_zones: [],
        msg() {}, err() {},
    }, overrides || {});
}

const ctx = context();
vm.runInNewContext(renderSrc + acmeConfSrc, ctx, { filename: "named.js#acme" });
const confText = ctx.get_conf("c1", "r2.test");
const zoneOf = (path) => ctx.pending_zone_updates.find((u) => u.path === path).content;
const shopZone = zoneOf("/var/named/srvctl/shop.example.zone");
ok(/^_acme-challenge\s+IN\s+CNAME\s+shop\.example\._acme\.company\.test\.$/m.test(shopZone), "CNAME in a generated zone");
ok(confText.includes('zone "shop-alias.example" {type master; file "/var/named/srvctl/shop.example.zone";'),
    "the alias shares the base file, so its CNAME targets the base container");
const custZone = zoneOf("/var/named/srvctl/cust.example.zone");
ok(!/_acme-challenge\s+IN\s+CNAME/.test(custZone), "no CNAME next to a customer _acme-challenge record");
ok(/^_acme-challenge\t\tIN\tTXT\t\t"customer"$/m.test(custZone), "customer record rendered unchanged");
const long = Object.keys(ctx.datastore.containers)[2];
ok(!/_acme-challenge/.test(zoneOf("/var/named/srvctl/" + long + ".zone")), "no CNAME with an overlong target");
ok(!/allow-update|update-policy/.test(confText), "regular zone statements stay static");

const byZone = Object.fromEntries(JSON.parse(JSON.stringify(ctx.acme_manifest_zones)).map((z) => [z.zone, z]));
eq(byZone["shop.example"], { zone: "shop.example", container: "shop.example", host: "r2.test", cluster: "c1",
    ns: ["ns1.company.test", "ns2.company.test"], dns01: true, reason: null }, "manifest entry with scanned NS");
eq(byZone["shop-alias.example"].dns01, true, "alias listed for DNS-01");
eq(byZone["shop-alias.example"].ns, null, "alias without scan data: NS null (undetermined)");
eq([byZone["cust.example"].dns01, byZone["cust.example"].reason], [false, "customer _acme-challenge record"], "customer zone keeps http-01");
eq([byZone[long].dns01, byZone[long].reason], [false, "challenge target too long"], "overlong zone keeps http-01");

// the _acme zone statement on the primary: TSIG TXT-only updates, same ACLs
const regular = ctx.primary_zone_statement("shop.example", "/var/named/srvctl/shop.example.zone");
const acmeConf = ctx.acme_zone_conf();
ok(acmeConf.includes('include "/var/named/srvctl-acme.key";\n'), "key included");
ok(acmeConf.includes('zone "_acme.company.test" {type master; file "/var/named/dynamic/_acme.company.test.zone"; ' +
    "update-policy { grant srvctl-acme subdomain _acme.company.test. TXT; }; "), "TSIG-restricted, TXT only");
eq(acmeConf.match(/allow-transfer \{[^}]*\};/)[0], regular.match(/allow-transfer \{[^}]*\};/)[0], "same transfer ACL as regular zones");
eq(acmeConf.match(/also-notify \{[^}]*\};/)[0], "also-notify {192.0.2.54;};", "replicas notified");
ok(!/allow-update/.test(acmeConf), "no allow-update");
eq(acmeConf.split("\n").filter((l) => l.startsWith("zone ")).length, 1, "one zone line (parsed by named_managed_zones)");

// replicas: a slave zone from the primary; inactive: nothing, and no CNAMEs
const rctx = context({ is_master: false });
vm.runInNewContext(renderSrc + acmeConfSrc, rctx);
ok(rctx.acme_zone_conf().includes('zone "_acme.company.test" {type slave; masters {192.0.2.10;}; allow-notify {192.0.2.10;}; ' +
    'file "/var/named/srvctl/_acme.company.test.slave.zone";};'), "replica slave zone");
const ictx = context({ acme_active: false });
vm.runInNewContext(renderSrc + acmeConfSrc, ictx);
ictx.get_conf("c1", "r2.test");
eq(ictx.acme_zone_conf(), "", "inactive: no _acme zone");
ok(!ictx.pending_zone_updates.some((u) => /_acme-challenge\s+IN\s+CNAME/.test(u.content)), "inactive: no CNAMEs");
eq(ictx.acme_manifest_zones.every((z) => !z.dns01 && z.reason === "acme zone inactive"), true, "inactive: nothing eligible");

// no HMAC-MD5 and no AXFR in the new DNS-01 code
for (const f of ["../lib/acmezone.js", "../libs/acmelib.sh", "../../letsencrypt/apps/acme-dns-hook.sh",
    "../../letsencrypt/acmerun.js", "../../letsencrypt/acmeplan.js"]) {
    const text = fs.readFileSync(new URL(f, import.meta.url), "utf8");
    ok(!/hmac-md5/i.test(text), "no HMAC-MD5 in " + f);
    ok(!/\bAXFR\b/.test(text.replace(/^\s*(#|\/\/|\*).*$/gm, "")), "no AXFR in " + f);
}

console.log("acme-zone.test: " + checks + " checks passed");
