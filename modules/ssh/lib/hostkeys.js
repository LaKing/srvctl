/*srvctl */

/*
 * modules/ssh/lib/hostkeys.js — host-key acquisition and known_hosts
 * rendering for modules/ssh/ssh.js.
 *
 * Kept free of top-level side effects and hardcoded state so that
 * modules/ssh/selftest/hostkeys.test.mjs can drive it without root:
 * every check takes an opts object whose srv_root, keyscan, is_running
 * and log members default to the production behaviour below.
 *
 * Key policy (RSA only, as ssh.js has always rendered 'ssh-rsa' lines):
 *   - cluster hosts: scanned only while they have no host_key;
 *   - containers hosted elsewhere (no local /srv/<C>): the datastore key
 *     written by their own host is used unchanged, scanned only while it
 *     is missing;
 *   - local containers: re-scanned on every pass while running (or while
 *     no key is known at all); a scanned key that differs from the stored
 *     one replaces it in the datastore record and /srv/<C>/host_key, and
 *     the change is logged with old and new SHA256 fingerprints;
 *   - empty, malformed or failed scans never touch an existing key.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const execFileSync = require("child_process").execFileSync;

const DEFAULT_SRV_ROOT = "/srv";

// True for a non-empty base64 blob that decodes to an ssh-rsa public key.
function is_rsa_key(key) {
    if (typeof key !== "string" || key === "") return false;
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(key)) return false;
    const blob = Buffer.from(key, "base64");
    if (blob.length < 11) return false;
    const len = blob.readUInt32BE(0);
    return len === 7 && blob.toString("latin1", 4, 11) === "ssh-rsa";
}

// Returns the base64 key of the first valid 'ssh-rsa' line of ssh-keyscan
// output, or undefined (empty output, comments only, other key types,
// garbage). Tolerates several lines, CRLF and a missing final newline.
function parse_keyscan(output) {
    if (output === undefined || output === null) return undefined;
    const lines = output.toString().split(/\r?\n/);
    for (let n = 0; n < lines.length; n++) {
        const line = lines[n].trim();
        if (line === "" || line[0] === "#") continue;
        const f = line.split(/\s+/);
        if (f.length >= 3 && f[1] === "ssh-rsa" && is_rsa_key(f[2])) return f[2];
    }
    return undefined;
}

// OpenSSH-style SHA256 fingerprint of a base64 public key blob (same
// value as 'ssh-keygen -lf'), computed with Node's built-in crypto.
function fingerprint(key) {
    if (typeof key !== "string" || key === "") return "(none)";
    const digest = crypto.createHash("sha256").update(Buffer.from(key, "base64")).digest("base64");
    return "SHA256:" + digest.replace(/=+$/, "");
}

// Production scanner: ssh-keyscan never runs through a shell; any failure
// or unusable output yields undefined.
function keyscan(target) {
    try {
        const out = execFileSync("ssh-keyscan", ["-t", "rsa", "-T", "1", target], {
            stdio: ["ignore", "pipe", "ignore"],
            timeout: 10000
        });
        return parse_keyscan(out);
    } catch (e) {
        return undefined;
    }
}

// Production run-state check, same unit as the rest of srvctl uses.
function is_running(c) {
    try {
        execFileSync("systemctl", ["is-active", "--quiet", "srvctl-nspawn@" + c + ".service"], {
            stdio: "ignore",
            timeout: 5000
        });
        return true;
    } catch (e) {
        return false;
    }
}

// The scanner is wrapped so that a throwing or misbehaving implementation
// can only ever mean "no usable key".
function with_defaults(opts) {
    const o = opts || {};
    const scan = o.keyscan || keyscan;
    return {
        srv_root: o.srv_root || DEFAULT_SRV_ROOT,
        keyscan: function (target) {
            try {
                const key = scan(target);
                return is_rsa_key(key) ? key : undefined;
            } catch (e) {
                return undefined;
            }
        },
        is_running: o.is_running || is_running,
        log: o.log || function () {}
    };
}

function read_cache(file) {
    try {
        if (!fs.existsSync(file)) return undefined;
        const key = fs.readFileSync(file, "utf8").trim();
        return is_rsa_key(key) ? key : undefined;
    } catch (e) {
        return undefined;
    }
}

// Keeps /srv/<C>/host_key equal to the key in use; a write failure is
// reported, never thrown.
function sync_cache(file, key, log) {
    try {
        if (fs.existsSync(file) && fs.readFileSync(file, "utf8") === key) return;
        fs.writeFileSync(file, key);
    } catch (e) {
        log("host_key cache " + file + " not written: " + e.message, "error");
    }
}

// Returns true when the container record i in data needs persisting.
function check_container_host_key(data, i, opts) {
    const o = with_defaults(opts);
    const stored = is_rsa_key(data[i].host_key) ? data[i].host_key : undefined;
    const dir = path.join(o.srv_root, i);

    // A domain-only record (retire-ve) has no container and no sshd: never
    // scan its name (the domain may point anywhere) nor write a leftover dir.
    if (data[i].domain_only === true) return false;

    if (!fs.existsSync(dir)) {
        // Hosted on another cluster host, which owns revalidation.
        if (stored !== undefined) return false;
        const found = o.keyscan(i);
        if (found === undefined) return false;
        data[i].host_key = found;
        o.log("ssh host_key of " + i + " recorded: " + fingerprint(found), "new");
        return true;
    }

    const cache_file = path.join(dir, "host_key");
    let known = stored;
    let changed = false;

    if (known === undefined) {
        const cached = read_cache(cache_file);
        if (cached !== undefined) {
            data[i].host_key = known = cached;
            changed = true;
            o.log("ssh host_key of " + i + " restored from " + cache_file + ": " + fingerprint(cached), "new");
        }
    }

    if (known === undefined || o.is_running(i)) {
        const scanned = o.keyscan(i);
        if (scanned !== undefined && scanned !== known) {
            if (known === undefined) {
                o.log("ssh host_key of " + i + " recorded: " + fingerprint(scanned), "new");
            } else {
                o.log("ssh host_key of " + i + " changed: old " + fingerprint(known) + " new " + fingerprint(scanned), "changed");
            }
            data[i].host_key = known = scanned;
            changed = true;
        }
    }

    if (known !== undefined) sync_cache(cache_file, known, o.log);
    return changed;
}

// Returns true when the cluster host record i in data needs persisting.
function check_host_key(data, i, opts) {
    const o = with_defaults(opts);
    if (is_rsa_key(data[i].host_key)) return false;
    const found = o.keyscan(i);
    if (found === undefined) return false;
    data[i].host_key = found;
    o.log("ssh host_key of cluster host " + i + " recorded: " + fingerprint(found), "new");
    return true;
}

// Renders both known_hosts files. Line formats (FQDN, host_ip, short
// hostname and the 10.15.x.x VPN alias) are relied on by cluster ssh
// automation. `common` is /var/srvctl3/share/common/known_hosts, `host`
// is /var/srvctl3/ssh/known_hosts (common plus the localhost entries).
// FIXME(v4): low — host_ip / hostnet are used unguarded; missing fields
// yield literal 'undefined ssh-rsa ...' / '10.15.undefined.undefined ...'
// lines in both known_hosts files.
function render_known_hosts(hosts, containers, srvctl, hostname) {
    const br = "\n";
    let keys = "## " + srvctl + " generated" + br;

    Object.keys(hosts).forEach(function (i) {
        if (hosts[i].host_key !== undefined) {
            keys += i + " ssh-rsa " + hosts[i].host_key + br;
            keys += hosts[i].host_ip + " ssh-rsa " + hosts[i].host_key + br;
            keys += i.split(".")[0] + " ssh-rsa " + hosts[i].host_key + br;
            keys += "10.15." + hosts[i].hostnet + "." + hosts[i].hostnet + " ssh-rsa " + hosts[i].host_key + br;
            keys += br;
        }
    });
    Object.keys(containers).forEach(function (i) {
        // a domain-only record's old key no longer belongs to any machine
        if (containers[i].domain_only === true) return;
        if (containers[i].host_key !== undefined) {
            keys += i + " ssh-rsa " + containers[i].host_key + br;
            keys += containers[i].ip + " ssh-rsa " + containers[i].host_key + br + br;
        }
    });

    const common = keys;
    if (hosts[hostname])
        if (hosts[hostname].host_key !== undefined) {
            keys += "localhost ssh-rsa " + hosts[hostname].host_key + br;
            keys += "127.0.0.1 ssh-rsa " + hosts[hostname].host_key + br;
        }

    return { common: common, host: keys };
}

exports.is_rsa_key = is_rsa_key;
exports.parse_keyscan = parse_keyscan;
exports.fingerprint = fingerprint;
exports.keyscan = keyscan;
exports.is_running = is_running;
exports.check_container_host_key = check_container_host_key;
exports.check_host_key = check_host_key;
exports.render_known_hosts = render_known_hosts;
