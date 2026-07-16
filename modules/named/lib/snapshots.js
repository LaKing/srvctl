"use strict";

const fs = require("fs");
const https = require("https");
const path = require("path");

const DATASTORE_PATH = "/.well-known/srvctl/datastore/containers.json";
const DEFAULT_TIMEOUT_MS = 3000;
const DEFAULT_MAX_CACHE_AGE_MS = 6 * 60 * 60 * 1000;
let temporaryFileCounter = 0;

function validateSnapshot(snapshot, source) {
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
        throw new Error(source + " did not contain a JSON object");
    }
    return snapshot;
}

// Atomic replacement in the target directory. Existing ownership/mode are
// retained; new generated files are world-readable like the legacy direct
// writes so named can read root-created zone files.
function atomicWriteFileSync(target, content, fsModule) {
    fsModule = fsModule || fs;
    const directory = path.dirname(target);
    const basename = path.basename(target);
    const temporary = path.join(directory,
        "." + basename + "." + process.pid + "." + temporaryFileCounter++ + ".tmp");
    let existing;
    try {
        existing = fsModule.statSync(target);
    } catch (error) {
        if (error.code !== "ENOENT") throw error;
    }

    let fd;
    let renamed = false;
    try {
        fd = fsModule.openSync(temporary, "wx", 0o600);
        fsModule.writeFileSync(fd, content);
        fsModule.fsyncSync(fd);
        fsModule.closeSync(fd);
        fd = undefined;

        fsModule.chmodSync(temporary, existing ? existing.mode & 0o777 : 0o644);
        if (existing && typeof fsModule.chownSync === "function") {
            fsModule.chownSync(temporary, existing.uid, existing.gid);
        }
        fsModule.renameSync(temporary, target);
        renamed = true;
    } finally {
        if (fd !== undefined) fsModule.closeSync(fd);
        if (!renamed) {
            try { fsModule.unlinkSync(temporary); } catch (_) { /* best effort */ }
        }
    }

    // Make the rename durable where directory fsync is supported.
    try {
        const directoryFd = fsModule.openSync(directory, "r");
        try { fsModule.fsyncSync(directoryFd); } finally { fsModule.closeSync(directoryFd); }
    } catch (_) { /* best effort */ }
}

function requestSnapshot(options) {
    options = options || {};
    const httpsModule = options.httpsModule || https;
    const timeoutMs = options.timeoutMs || DEFAULT_TIMEOUT_MS;
    const hostname = options.hostname;
    const ip = options.ip;

    return new Promise(function(resolve, reject) {
        let settled = false;
        let request;
        const timer = setTimeout(function() {
            if (settled) return;
            const error = new Error("timed out after " + timeoutMs + "ms");
            if (request && typeof request.destroy === "function") request.destroy(error);
            finish(error);
        }, timeoutMs);

        function finish(error, snapshot) {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            if (error) reject(error);
            else resolve(snapshot);
        }

        try {
            request = httpsModule.get({
                host: ip,
                port: 443,
                path: DATASTORE_PATH,
                method: "GET",
                rejectUnauthorized: false,
                requestCert: true,
                agent: false,
            }, function(response) {
                const statusCode = response.statusCode;
                const contentType = response.headers && response.headers["content-type"] || "";
                if (statusCode !== 200 || !/^application\/json(?:\s*;|$)/i.test(contentType)) {
                    if (typeof response.resume === "function") response.resume();
                    return finish(new Error("invalid response from " + hostname +
                        ": HTTP " + statusCode + " content-type " + JSON.stringify(contentType)));
                }

                let raw = "";
                response.setEncoding("utf8");
                response.on("data", function(chunk) { raw += chunk; });
                response.on("error", function(error) { finish(error); });
                response.on("end", function() {
                    try {
                        finish(null, validateSnapshot(JSON.parse(raw), "response from " + hostname));
                    } catch (error) {
                        finish(error);
                    }
                });
            });
            request.on("error", function(error) { finish(error); });
        } catch (error) {
            finish(error);
        }
    });
}

async function loadPeerSnapshot(options) {
    options = options || {};
    const fsModule = options.fsModule || fs;
    const cacheFile = path.join(options.cacheDir, options.hostname + ".json");
    const fetchSnapshot = options.fetchSnapshot || function() {
        return requestSnapshot(options);
    };

    try {
        const snapshot = validateSnapshot(await fetchSnapshot(), "response from " + options.hostname);
        atomicWriteFileSync(cacheFile, JSON.stringify(snapshot, null, 2) + "\n", fsModule);
        return { snapshot: snapshot, source: "fresh", cacheFile: cacheFile };
    } catch (freshError) {
        if (options.requireFresh === true) {
            throw new Error("cannot load fresh containers for " + options.hostname +
                ": " + freshError.message);
        }
        try {
            const maxCacheAgeMs = options.maxCacheAgeMs === undefined ?
                DEFAULT_MAX_CACHE_AGE_MS : Number(options.maxCacheAgeMs);
            if (!Number.isFinite(maxCacheAgeMs) || maxCacheAgeMs < 0) {
                throw new Error("invalid cache age limit " + options.maxCacheAgeMs);
            }
            const cacheAgeMs = (options.nowMs === undefined ? Date.now() : options.nowMs) -
                fsModule.statSync(cacheFile).mtimeMs;
            if (cacheAgeMs < 0 || cacheAgeMs > maxCacheAgeMs) {
                throw new Error("cache is " + Math.max(0, Math.floor(cacheAgeMs / 1000)) +
                    "s old (limit " + Math.floor(maxCacheAgeMs / 1000) + "s)");
            }
            const cached = validateSnapshot(
                JSON.parse(fsModule.readFileSync(cacheFile, "utf8")),
                "cache " + cacheFile);
            return {
                snapshot: cached,
                source: "cache",
                cacheFile: cacheFile,
                freshError: freshError,
            };
        } catch (cacheError) {
            throw new Error("cannot load containers for " + options.hostname +
                ": fresh fetch failed (" + freshError.message +
                ") and no valid last-good cache exists (" + cacheError.message + ")");
        }
    }
}

module.exports = {
    DATASTORE_PATH: DATASTORE_PATH,
    DEFAULT_MAX_CACHE_AGE_MS: DEFAULT_MAX_CACHE_AGE_MS,
    atomicWriteFileSync: atomicWriteFileSync,
    loadPeerSnapshot: loadPeerSnapshot,
    requestSnapshot: requestSnapshot,
    validateSnapshot: validateSnapshot,
};
