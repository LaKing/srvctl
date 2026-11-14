// modules/letsencrypt/selftest/acme-server.test.mjs — the http-01 responder
// serves a token file and nothing outside its directory.
// Run: node modules/letsencrypt/selftest/acme-server.test.mjs

import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const { createHttpServer } = require(path.join(HERE, "../apps/acme-server.js"));

// http.get would normalise the path, so the request line is written as given.
function request(port, rawPath) {
    return new Promise((resolve, reject) => {
        const req = http.request({ host: "127.0.0.1", port, path: rawPath, method: "GET" }, (res) => {
            let body = "";
            res.on("data", (chunk) => (body += chunk));
            res.on("end", () => resolve({ status: res.statusCode, body }));
        });
        req.on("error", reject);
        req.end();
    });
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sc-acme-server-"));
const dir = path.join(tmp, "webroot", ".well-known", "acme-challenge");
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, "tok_EN-123"), "tok_EN-123.thumbprint");
fs.writeFileSync(path.join(tmp, "secret"), "outside");
fs.writeFileSync(path.join(dir, ".hidden"), "hidden");

const server = createHttpServer(dir);
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const PREFIX = "/.well-known/acme-challenge/";
let failed = 0;

try {
    const good = await request(port, PREFIX + "tok_EN-123");
    assert.deepEqual(good, { status: 200, body: "tok_EN-123.thumbprint" });
    console.log("  ok  a token is served");

    const refused = ["../../../secret", "..%2F..%2F..%2Fsecret", "%2e%2e/%2e%2e/%2e%2e/secret", "sub/tok", "/etc/hostname", "tok_EN-123?x=1", ".hidden", "missing-token", ""];
    for (const tail of refused) {
        const r = await request(port, PREFIX + tail);
        assert.equal(r.status, 404, tail + " -> " + r.status + " " + r.body);
        assert.ok(!r.body.includes("outside") && !r.body.includes("secret") && !r.body.includes(tmp), tail + " leaked: " + r.body);
    }
    console.log("  ok  nothing outside the directory is served and the request is not echoed");

    assert.equal((await request(port, "/")).status, 404);
    assert.equal((await request(port, "/.well-known/other/tok_EN-123")).status, 404);
    console.log("  ok  other paths are refused");
} catch (err) {
    failed = 1;
    console.log("FAIL  " + (err.stack || err));
} finally {
    server.close();
    fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(failed ? "acme-server: failed" : "acme-server: all passed");
process.exit(failed);
