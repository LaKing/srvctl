// modules/opendkim/selftest/keys.test.mjs — DKIM key lookup (lib/keys.js):
// a container's key comes from /srv/<domain>/opendkim, a domain-only
// record's (retire-ve) from the host-side datastore copy, and nothing ever
// generates a replacement key for a domain-only record.
// Run: node modules/opendkim/selftest/keys.test.mjs

import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { key_plan } = require("../lib/keys.js");

const srvRoot = "/srv";
const opendkimFolder = "/ds/opendkim";
let checks = 0;
const plan = (domain, record, files) => key_plan({ domain, record, srvRoot, opendkimFolder, exists: (p) => files.includes(p) });
const is = (actual, expected, what) => { assert.equal(actual, expected, what); checks++; };

// ordinary containers: exactly as before
is(plan("a.test", {}, ["/srv/a.test", "/srv/a.test/opendkim/default.private"]).action, "copy", "container with a key: copy it to the host side");
is(plan("a.test", {}, ["/srv/a.test"]).action, "genkey", "container without a key: generate one");
is(plan("a.test", {}, []).action, "none", "container hosted elsewhere: nothing");
is(plan("a.test", {}, ["/srv/a.test"]).private_file, "/srv/a.test/opendkim/default.private", "key path below /srv");

// domain-only records
const retired = { domain_only: true };
is(plan("a.test", retired, ["/ds/opendkim/a.test/default.private"]).action, "hostside", "domain-only: the host-side key is the key");
is(plan("a.test", retired, ["/srv/a.test", "/ds/opendkim/a.test/default.private"]).action, "hostside", "domain-only with an empty leftover /srv dir: no genkey");
is(plan("a.test", retired, ["/srv/a.test"]).action, "missing", "domain-only without a host-side key: reported, never generated");
is(plan("a.test", retired, ["/srv/a.test", "/srv/a.test/opendkim/default.private"]).action, "missing", "domain-only: a leftover /srv key is not copied over the host side");
is(plan("a.test", { domain_only: "true" }, ["/srv/a.test"]).action, "genkey", "only a boolean true is domain-only");
is(plan("a.test", retired, []).hostside_file, "/ds/opendkim/a.test/default.private", "host-side location");

// the selector rule
is(plan("mail.a.test", retired, ["/ds/opendkim/mail.a.test/mail.private"]).action, "hostside", "mail. names use the mail selector");
is(plan("mail.a.test", retired, []).selector, "mail", "selector of a mail. name");

// repeated regenerate: same answer
const files = ["/srv/a.test", "/ds/opendkim/a.test/default.private"];
is(JSON.stringify(plan("a.test", retired, files)), JSON.stringify(plan("a.test", retired, files)), "a second run plans the same");

console.log("All opendkim key tests passed (" + checks + " checks).");
