// Run: node modules/named/selftest/snapshots.test.mjs

import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import fs from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";

const require = createRequire(import.meta.url);
const {
    atomicWriteFileSync,
    loadPeerSnapshot,
    requestSnapshot,
} = require("../lib/snapshots.js");

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "srvctl-named-snapshot-"));
try {
    const fresh = await loadPeerSnapshot({
        cacheDir: temporaryRoot,
        hostname: "peer.test",
        ip: "192.0.2.10",
        fetchSnapshot: async () => ({ "fresh.example": { ip: "10.0.0.2" } }),
    });
    assert.equal(fresh.source, "fresh");
    assert.deepEqual(fresh.snapshot, { "fresh.example": { ip: "10.0.0.2" } });
    assert.deepEqual(JSON.parse(fs.readFileSync(fresh.cacheFile, "utf8")), fresh.snapshot,
        "a successful response must become the last-good cache");

    const fallback = await loadPeerSnapshot({
        cacheDir: temporaryRoot,
        hostname: "peer.test",
        ip: "192.0.2.10",
        fetchSnapshot: async () => { throw new Error("peer unavailable"); },
    });
    assert.equal(fallback.source, "cache");
    assert.match(fallback.freshError.message, /peer unavailable/);
    assert.deepEqual(fallback.snapshot, fresh.snapshot);

    await assert.rejects(loadPeerSnapshot({
        cacheDir: temporaryRoot,
        hostname: "peer.test",
        ip: "192.0.2.10",
        requireFresh: true,
        fetchSnapshot: async () => { throw new Error("peer unavailable"); },
    }), /cannot load fresh containers for peer\.test: peer unavailable/,
    "a manual convergence run must never turn stale cache into success");

    const cacheMtime = fs.statSync(fresh.cacheFile).mtimeMs;
    await assert.rejects(loadPeerSnapshot({
        cacheDir: temporaryRoot,
        hostname: "peer.test",
        ip: "192.0.2.10",
        maxCacheAgeMs: 1000,
        nowMs: cacheMtime + 1001,
        fetchSnapshot: async () => { throw new Error("peer unavailable"); },
    }), /cache is 1s old \(limit 1s\)/,
    "automatic fallback must reject an expired last-good cache");

    await assert.rejects(loadPeerSnapshot({
        cacheDir: temporaryRoot,
        hostname: "missing.test",
        ip: "192.0.2.11",
        fetchSnapshot: async () => { throw new Error("connection refused"); },
    }), /fresh fetch failed .* no valid last-good cache exists/,
    "generation must fail closed when neither a fresh response nor cache exists");

    const atomicTarget = path.join(temporaryRoot, "atomic.txt");
    fs.writeFileSync(atomicTarget, "old\n", { mode: 0o640 });
    atomicWriteFileSync(atomicTarget, "new\n");
    assert.equal(fs.readFileSync(atomicTarget, "utf8"), "new\n");
    assert.equal(fs.statSync(atomicTarget).mode & 0o777, 0o640);
    assert.equal(fs.readdirSync(temporaryRoot).some((name) => name.endsWith(".tmp")), false);

    const hangingHttps = {
        get() {
            const request = new EventEmitter();
            request.destroy = function() {};
            return request;
        },
    };
    const started = Date.now();
    await assert.rejects(requestSnapshot({
        hostname: "hanging.test",
        ip: "192.0.2.12",
        httpsModule: hangingHttps,
        timeoutMs: 20,
    }), /timed out after 20ms/);
    assert.ok(Date.now() - started < 1000, "the request timeout must be a hard bound");
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("snapshots.test: passed");
