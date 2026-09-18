// modules/haproxy/selftest/wellknown.test.mjs — the http-01 path stays
// intact: haproxy's http frontend routes /.well-known/acme-challenge/ for any
// Host header to the letsencrypt backend on 127.0.0.1:1028, the https
// redirects exclude /.well-known, and acme-server.js still listens on 1028.
// Rendered from the real haproxy.js functions (vm slices, as the named tests do).
// Run: node modules/haproxy/selftest/wellknown.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

let checks = 0;
const ok = (v, m) => { assert.ok(v, m); checks++; };
const src = fs.readFileSync(new URL("../haproxy.js", import.meta.url), "utf8");
const slice = (from, to) => {
    const a = src.indexOf(from);
    const b = src.indexOf(to, a);
    assert.ok(a >= 0 && b > a, "slice " + from);
    return src.slice(a, b);
};

const ctx = {
    br: "\n", SC_COMPANY_DOMAIN: "company.test",
    containers: { "shop.example": { aliases: ["alias.example"] }, "ext.example": {} },
    datastore: { container_http_port: () => 80, container_https_port: () => 443 },
    msg() {}, ntc() {}, err() {},
    Object, Array,
};
vm.runInNewContext(slice("function ddn(", "\n}\n") + "\n}\n" + slice("function acl(", "\nfunction get_frontend_https(") +
    slice("function get_backends_for_http(", "\nfunction get_backends_for_https("), ctx);

const http = ctx.get_frontend_http();
ok(/^\s*acl letsencrypt-acl path_beg \/\.well-known\/acme-challenge\/$/m.test(http), "challenge ACL");
ok(/^\s*acl \.well-known-acl path_beg \/\.well-known$/m.test(http), "well-known ACL");
ok(/^\s*use_backend letsencrypt-backend if letsencrypt-acl$/m.test(http), "routed regardless of the Host header");
const redirects = http.split("\n").filter((l) => /redirect prefix https:\/\//.test(l));
ok(redirects.length > 0 && redirects.every((l) => l.endsWith(" !.well-known-acl")), "https redirects exclude /.well-known");
ok(http.indexOf("use_backend letsencrypt-backend") < http.indexOf("use_backend http:"), "challenge routing before container backends");
const backends = ctx.get_backends_for_http();
ok(/^backend letsencrypt-backend\n\s+server letsencrypt 127\.0\.0\.1:1028$/m.test(backends), "backend on 127.0.0.1:1028");

const acme = fs.readFileSync(new URL("../../letsencrypt/apps/acme-server.js", import.meta.url), "utf8");
ok(/http_server\.listen\(1028\);/.test(acme), "acme-server.js listens on 1028");
ok(acme.includes('"/.well-known/acme-challenge/"'), "acme-server.js serves the challenge path");
const lib = fs.readFileSync(new URL("../../letsencrypt/libs/letsencryptlib.sh", import.meta.url), "utf8");
ok(/ExecStart=\/bin\/node \$SC_INSTALL_DIR\/modules\/letsencrypt\/apps\/acme-server\.js/.test(lib), "acme-server.service unit unchanged");

console.log("wellknown.test: " + checks + " checks passed");
