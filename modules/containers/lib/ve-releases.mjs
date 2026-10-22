#!/bin/node

// containers/lib/ve-releases.mjs — the 'sc list-ve-releases' survey.
//
// Read-only. Called by commands/list-ve-releases.sh as root on a host, with SC_DATASTORE_DIR and
// SC_HOST_IP in the environment. Lists every local container (/srv/<C>/rootfs), oldest release first,
// with the facts needed to plan an OS upgrade. argv[2] == "tsv" prints tab-separated values instead
// of the aligned table, so the lists of several hosts can be concatenated.
//
// Pitfall: a rootfs is container-controlled. Every path read here is resolved with realpath and must
// stay inside that rootfs; symlinks are never followed during the walk. An absolute /etc/os-release
// symlink would otherwise report the HOST's release.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createStore } from "../../datastore/lib/store.mjs";

const TSV = process.argv[2] === "tsv";
const HOST_IP = process.env.SC_HOST_IP || "";
const DATASTORE = process.env.SC_DATASTORE_DIR || "/var/srvctl3/datastore";
// Test seam: selftest/ve-releases.test.sh points this at fake rootfs trees.
const SRV = process.env.SC_VE_RELEASES_SRV || "/srv";
const WANTS = "/etc/systemd/system/machines.target.wants";

// Units the fedora template or a stock Fedora enables. Anything else enabled in multi-user.target.wants
// is something the owner installed, and makes the container "custom".
const BASELINE = new Set(
    (
        "postfix dovecot httpd sshd rsyslog firewalld crond atd auditd chronyd ntpd systemd-networkd systemd-resolved remote-fs.target dnf-makecache.timer " +
        "NetworkManager sssd mcelog irqbalance smartd rngd sendmail sm-client abrtd abrt-ccpp abrt-oops abrt-vmcore abrt-xorg abrt-journal-core lvm2-monitor " +
        "dbus-broker systemd-homed systemd-userdbd systemd-oomd mariadb mysqld nfs-client.target cups gssproxy livesys livesys-late"
    ).split(" "),
);
const SKIP_DIRS = new Set(["node_modules", ".git", ".cache"]);
const WALK_LIMIT = 100000;

// Resolve rel inside rootfs; null when it does not exist or escapes the rootfs through a symlink.
function inside(rootfs, rel) {
    try {
        const real = fs.realpathSync(path.join(rootfs, rel));
        return real === rootfs || real.startsWith(rootfs + "/") ? real : null;
    } catch {
        return null;
    }
}

function osRelease(rootfs) {
    for (const rel of ["usr/lib/os-release", "etc/os-release"]) {
        const file = inside(rootfs, rel);
        if (!file) continue;
        const os = {};
        for (const line of fs.readFileSync(file, "utf8").split("\n")) {
            const m = line.match(/^([A-Z_]+)=("?)(.*)\2$/);
            if (m) os[m[1]] = m[3];
        }
        return { id: os.ID || "?", version: os.VERSION_ID || "?" };
    }
    return { id: "?", version: "?" };
}

function mtime(rootfs, rel) {
    const file = inside(rootfs, rel);
    return file ? fs.lstatSync(file).mtimeMs : 0;
}

// Newest file mtime under the user-data trees. Bounded by WALK_LIMIT entries; "+" marks a capped walk.
function lastChange(rootfs) {
    let newest = 0;
    let seen = 0;
    const stack = ["var/www/html", "srv", "home"].map((rel) => inside(rootfs, rel)).filter(Boolean);
    while (stack.length && seen < WALK_LIMIT) {
        const dir = stack.pop();
        let entries;
        try {
            entries = fs.readdirSync(dir, { withFileTypes: true });
        } catch {
            continue;
        }
        for (const e of entries) {
            if (++seen >= WALK_LIMIT) break;
            const p = path.join(dir, e.name);
            if (e.isDirectory()) {
                if (!SKIP_DIRS.has(e.name)) stack.push(p);
            } else if (e.isFile()) {
                try {
                    newest = Math.max(newest, fs.lstatSync(p).mtimeMs);
                } catch {}
            }
        }
    }
    return { time: newest, capped: seen >= WALK_LIMIT };
}

function unitState(c) {
    let active = "inactive";
    try {
        active = execFileSync("systemctl", ["is-active", `srvctl-nspawn@${c}.service`], { encoding: "utf8", timeout: 2000 }).trim();
    } catch (e) {
        active = String(e.stdout || "").trim() || "unknown";
    }
    const enabled = fs.existsSync(`${WANTS}/srvctl-nspawn@${c}.service`);
    return { active, enabled };
}

// From the dns-scan results in the datastore record: here / away / none / ?.
function dnsState(record) {
    const scans = Object.values((record && record.dns) || {});
    if (!scans.length) return "?";
    if (scans.some((s) => Array.isArray(s.A) && s.A.includes(HOST_IP))) return "here";
    if (scans.some((s) => Array.isArray(s.A) && s.A.length)) return "away";
    return "none";
}

function apps(rootfs) {
    const found = [];
    if (inside(rootfs, "var/www/html/wp-config.php")) found.push("wp");
    if (inside(rootfs, "var/lib/mysql/mysql")) found.push("mysql");
    if (inside(rootfs, "var/lib/mongo") || inside(rootfs, "var/lib/mongodb")) found.push("mongo");
    if (inside(rootfs, "var/codepad/codepad4")) found.push("codepad");
    if (inside(rootfs, "usr/bin/php")) found.push("php");
    const wants = inside(rootfs, "etc/systemd/system/multi-user.target.wants");
    const units = wants ? fs.readdirSync(wants).map((u) => u.replace(/\.service$/, "")) : [];
    const custom = units.filter((u) => !BASELINE.has(u) && !u.startsWith("srvctl"));
    return { found, custom };
}

function classify(row, a) {
    if (row.active !== "active" || row.dns === "away" || row.dns === "none") return "dead?";
    if (a.custom.length || a.found.includes("mongo") || a.found.includes("codepad")) return "custom";
    if (a.found.includes("wp")) return "wordpress";
    return "simple";
}

// Local date, like the rest of the host tooling (toISOString would shift late-evening times to UTC).
const day = (ms) => (ms ? new Date(ms).toLocaleDateString("sv-SE") : "-");

function survey(c, record) {
    const rootfs = fs.realpathSync(`${SRV}/${c}/rootfs`);
    const os = osRelease(rootfs);
    const unit = unitState(c);
    const http = Math.max(mtime(rootfs, "var/log/httpd/access_log"), mtime(rootfs, "var/log/httpd/ssl_access_log"));
    const change = lastChange(rootfs);
    const a = apps(rootfs);
    const row = {
        ve: c,
        os: `${os.id} ${os.version}`,
        version: Number(os.version) || 0,
        active: unit.active,
        state: unit.active + (unit.enabled ? "" : ",disabled"),
        dns: record ? dnsState(record) : "orphan",
        http: day(http),
        change: day(change.time) + (change.capped ? "+" : ""),
        size: record && record.du ? (record.du / 1048576).toFixed(1) + "G" : "?",
        owner: (record && record.user) || "-",
        apps: [...a.found, ...a.custom].join(",") || "-",
    };
    row.class = classify(row, a);
    return row;
}

const COLUMNS = ["ve", "os", "state", "dns", "http", "change", "size", "owner", "class", "apps"];
const HEADER = { ve: "VE", os: "OS", state: "STATE", dns: "DNS", http: "LAST-HTTP", change: "LAST-FILE", size: "SIZE", owner: "OWNER", class: "CLASS", apps: "APPS" };

function print(rows) {
    if (TSV) {
        for (const r of [HEADER, ...rows]) console.log(COLUMNS.map((k) => r[k]).join("\t"));
        return;
    }
    const width = Object.fromEntries(COLUMNS.map((k) => [k, Math.max(...[HEADER, ...rows].map((r) => String(r[k]).length))]));
    const line = (r) => COLUMNS.map((k) => String(r[k]).padEnd(width[k])).join("  ");
    for (const r of [HEADER, ...rows]) console.log(line(r).trimEnd());

    const count = (key) => rows.reduce((m, r) => m.set(r[key], (m.get(r[key]) || 0) + 1), new Map());
    console.log("\nby release: " + [...count("os")].map(([k, n]) => `${k}: ${n}`).join(", "));
    console.log("by class:   " + [...count("class")].map(([k, n]) => `${k}: ${n}`).join(", "));
}

const containers = createStore(DATASTORE, { readOnly: true, git: false }).readAll("containers");
const local = fs.readdirSync(SRV).filter((c) => fs.existsSync(`${SRV}/${c}/rootfs`));
const rows = [];
for (const c of local) {
    try {
        rows.push(survey(c, containers[c]));
    } catch (e) {
        console.error(`${c}: ${e.message}`);
    }
}
rows.sort((a, b) => a.version - b.version || a.os.localeCompare(b.os) || a.ve.localeCompare(b.ve));
print(rows);
