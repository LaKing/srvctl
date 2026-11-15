// modules/named/selftest/domain-only-zone.test.mjs — retiring a container
// (retire-ve, domain_only=true) leaves its DNS untouched: the zone declaration
// and the zone file rendered by the real get_conf / get_container_zone are
// byte-identical before and after, with A, MX, SPF incl. Google, the default
// and Google DKIM keys, DMARC and the _acme-challenge CNAME.
// Run: node modules/named/selftest/domain-only-zone.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import { createRequire } from "node:module";
import vm from "node:vm";
import net from "node:net";

const require = createRequire(import.meta.url);
const { SERIAL_PLACEHOLDER, planZoneUpdate } = require("../lib/zonefile.js");
const acmezoneLib = require("../lib/acmezone.js");

const namedSource = fs.readFileSync(new URL("../named.js", import.meta.url), "utf8");
const start = namedSource.indexOf("function splitstring(");
const end = namedSource.indexOf("\nfunction make_conf()", start);
assert.ok(start >= 0 && end > start, "splitstring..get_conf slice");
const source = namedSource.slice(start, end);

// hangmaffia.hu as it is on r2: web and mail handed to d250.hu, Google sends
// as it, own default and Google DKIM keys, DMARC by default.
const record = () => ({
    user: "alice", type: "fedora", ip: "10.40.1.7",
    web_ve: "web.test", mail_ve: "web.test", use_google_spf: true,
    "dkim-default-domainkey": "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDdefault",
    "dkim-google-domainkey": "p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAgoogle",
});

function render(domainOnly) {
    const site = record();
    if (domainOnly) site.domain_only = true;
    const errors = [];
    const context = {
        HOSTNAME: "local.test", CDN: "company.test", br: "\n",
        clusters: { cluster: { "local.test": { host_ip: "192.0.2.10" }, "peer.test": { host_ip: "192.0.2.11" } } },
        datastore: { containers: { "site.test": site, "web.test": { user: "alice", type: "fedora", ip: "10.40.1.8" } } },
        peer_container_snapshots: {},
        fs: { readFileSync(path) { const e = new Error("missing " + path); e.code = "ENOENT"; throw e; } },
        is_master: true, listed_domain_names: [],
        master_servers: "192.0.2.53;", replica_servers: "192.0.2.54;", replica_transfer_clients: "198.51.100.54;",
        dns_topology: { primaryAclIp: "198.51.100.53", primary: { config: { dns_replication_source: "192.0.2.53" } } },
        local_dns_host: { config: { dns_replication_source: "192.0.2.54" } },
        soa_primary_name: "ns1.company.test",
        net, planZoneUpdate, SERIAL_PLACEHOLDER, acmezoneLib,
        acme_active: true, acme_manifest_zones: [],
        msg() {}, err(m) { errors.push(m); },
    };
    vm.runInNewContext(source, context, { filename: "named.js#get_conf" });
    const conf = context.get_conf("cluster", "local.test");
    const zone = context.pending_zone_updates.find((u) => u.path === "/var/named/srvctl/site.test.zone");
    assert.deepEqual(errors, [], "no errors");
    return { conf, zone: zone && zone.content, manifest: JSON.stringify(context.acme_manifest_zones) };
}

const before = render(false);
const after = render(true);
assert.ok(before.zone, "the zone is rendered");
assert.equal(after.conf, before.conf, "zone declarations identical after retirement");
assert.equal(after.zone, before.zone, "zone file byte-identical after retirement");
assert.equal(after.manifest, before.manifest, "DNS-01 manifest identical after retirement");

const z = after.zone;
assert.match(z, /^@\s+IN\s+A\s+192\.0\.2\.10$/m, "A");
assert.match(z, /^@\s+IN\s+MX\s+10\s+mail$/m, "MX");
assert.match(z, /^@\s+IN\s+TXT\s+"v=spf1 [^"]*include:_spf\.google\.com ~all"$/m, "SPF with Google");
const joined = z.replace(/"\n\s*"/g, "");
assert.match(z, /^default\._domainkey\s+IN\s+TXT\s+\( "v=DKIM1; k=rsa;"/m, "default DKIM");
assert.ok(joined.includes(record()["dkim-default-domainkey"]), "default DKIM key published");
assert.match(z, /^google\._domainkey\s+IN\s+TXT\s+\( "v=DKIM1; k=rsa;"/m, "Google DKIM");
assert.ok(joined.includes(record()["dkim-google-domainkey"]), "Google DKIM key published");
assert.match(z, /^_dmarc\s+TXT \( "v=DMARC1;p=reject;/m, "DMARC");
assert.match(z, /^_acme-challenge\s+IN\s+CNAME\s+\S+\.$/m, "_acme-challenge");

console.log("domain-only-zone.test: passed");
