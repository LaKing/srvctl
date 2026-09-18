"use strict";

/*
 * srvctl letsencrypt module — acmerun.js
 *
 * The side-effecting half of the DNS-01 wildcard scheme, driven by
 * letsencrypt.js (decisions live in acmeplan.js):
 *
 *   Store          /var/srvctl3/acme/handover.json — per-name handover state
 *                  and a one-entry journal. Written tmp + fsync + rename + dir
 *                  fsync with a .bak; a pending install/retire is replayed
 *                  idempotently before anything else (rule J).
 *   primary        (the elected DNS primary, command "regenerate" only)
 *                  issues srvctl-wildcard-<name> lineages via DNS-01 for the
 *                  committed manifest, publishes bundles/<name>.pem and
 *                  bundles/index.json, writes the hook configuration and
 *                  reconciles failed hook cleanups.
 *   refresh        serving hosts pull index.json and their bundles from the
 *                  primary (rsync over ssh); the primary reads them locally.
 *   evaluateNames  runs acmeplan.evaluate per name and applies installs.
 *   finishLeaving  retires a still-servable wildcard only when every served
 *                  name it covers has a deployed replacement with at least
 *                  30 days left.
 *   hostPath       http-01 for this host's configured name.
 *
 * Every path is overridable through the environment for the selftests.
 */

const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");
const plan = require("./acmeplan.js");
const bundlelib = require("./bundlelib.js");

const INDEX_MAX_AGE = 26 * 3600000;
const RETIRE_MIN_DAYS = 30;

function onlyNames(value) {
    const names = String(value || "").split(/[\s,]+/).map(plan.normalizeName).filter(Boolean);
    return names.length ? new Set(names) : null;
}

function config(env) {
    const acmeDir = env.SC_ACME_DIR || "/var/srvctl3/acme";
    const datastoreCert = (env.SC_DATASTORE_DIR || "/var/srvctl3/datastore") + "/cert";
    return {
        env: env,
        acmeDir: acmeDir,
        stateFile: acmeDir + "/handover.json",
        statusFile: acmeDir + "/status.json",
        issueStateFile: acmeDir + "/issue-state.json",
        bundlesDir: acmeDir + "/bundles",
        incomingDir: acmeDir + "/incoming",
        hostDnsFile: acmeDir + "/host-dns.json",
        logDir: acmeDir + "/log",
        hookStateDir: acmeDir + "/hook",
        datastoreCertDir: datastoreCert,
        wildcardDir: datastoreCert + "/wildcard",
        retiredDir: datastoreCert + "/wildcard-retired",
        liveDir: env.SC_LE_LIVE_DIR || "/etc/letsencrypt/live",
        srvRoot: env.SC_SRV_ROOT || "/srv",
        clustersFile: env.SC_CLUSTERS_FILE || "/etc/srvctl/clusters.json",
        manifestSnapshot: env.SC_ACME_MANIFEST_SNAPSHOT || acmeDir + "/manifest.snapshot.json",
        manifestLiveSha: env.SC_ACME_MANIFEST_LIVE_SHA || acmeDir + "/manifest.live.sha256",
        hookConf: env.SC_ACME_HOOK_CONF || "/etc/letsencrypt/srvctl-acme-dns.conf",
        hookLock: env.SC_ACME_HOOK_LOCK || "/run/srvctl-acme-records.lock",
        acmeKeyFile: env.SC_ACME_KEY_FILE || "/var/named/srvctl-acme.key",
        hook: path.join(__dirname, "apps/acme-dns-hook.sh"),
        letsencryptBin: env.SC_LETSENCRYPT_BIN || "letsencrypt",
        rsyncBin: env.SC_RSYNC_BIN || "rsync",
        digBin: env.SC_DIG_BIN || "dig",
        cdn: env.SC_COMPANY_DOMAIN || "",
        command: env.SC_ACME_COMMAND || "",
        fallback: env.SC_ACME_HTTP01_FALLBACK === "true",
        http01: env.SC_ACME_HTTP01_AVAILABLE !== "false",
        staging: env.SC_LETSENCRYPT_STAGING === "true",
        maxIssue: Number(env.SC_ACME_MAX_ISSUE_PER_RUN || 10),
        // SC_ACME_DNS01_ONLY: space- or comma-separated names; when set, only
        // these are issued or renewed (a controlled rollout). Other candidates
        // stay pending, keeping every serving host in its current state.
        only: onlyNames(env.SC_ACME_DNS01_ONLY),
        crashAt: env.SC_ACME_CRASH_AT || "",
        now: env.SC_ACME_NOW ? Date.parse(env.SC_ACME_NOW) : Date.now(),
    };
}

// ---------------------------------------------------------------- files ---

function crashPoint(cfg, name) {
    if (cfg.crashAt === name) process.exit(86);
}

function fsyncDir(dir) {
    try {
        const fd = fs.openSync(dir, "r");
        fs.fsyncSync(fd);
        fs.closeSync(fd);
    } catch (error) {
        // directories cannot always be opened for fsync; the rename stands
    }
}

function atomicWrite(file, data, mode) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = file + ".tmp." + process.pid;
    const fd = fs.openSync(tmp, "w", mode || 0o600);
    try {
        fs.writeSync(fd, data);
        fs.fsyncSync(fd);
    } finally {
        fs.closeSync(fd);
    }
    fs.chmodSync(tmp, mode || 0o600);
    fs.renameSync(tmp, file);
    fsyncDir(path.dirname(file));
}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (error) {
        return null;
    }
}

function readText(file) {
    try {
        return fs.readFileSync(file, "utf8");
    } catch (error) {
        return null;
    }
}

function sweepTmp(dirs) {
    dirs.forEach(function(dir) {
        let names = [];
        try {
            names = fs.readdirSync(dir);
        } catch (error) {
            return;
        }
        names.filter(function(n) { return /\.tmp\.\d+$/.test(n); }).forEach(function(n) {
            try { fs.unlinkSync(path.join(dir, n)); } catch (error) { /* already gone */ }
        });
    });
}

// Split a bundle (key + fullchain) into its parts.
function splitBundle(text) {
    const key = /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]+?-----END [A-Z ]*PRIVATE KEY-----\n?/.exec(text);
    return {
        privkey: key ? key[0].replace(/\s+$/, "") + "\n" : "",
        fullchain: bundlelib.certificateBlocks(text).join(""),
    };
}

// ---------------------------------------------------------------- store ---

class Store {
    constructor(cfg, report) {
        this.cfg = cfg;
        this.report = report;
        this.data = null;
    }

    load() {
        const cfg = this.cfg;
        let data = readJson(cfg.stateFile);
        if (!data || typeof data.names !== "object") {
            data = readJson(cfg.stateFile + ".bak");
            if (data && typeof data.names === "object") {
                this.report.alert(null, "error", "handover state unreadable; restored from " + cfg.stateFile + ".bak");
            } else {
                data = this.rebuild();
            }
        }
        this.data = data;
        return data;
    }

    // Nothing readable: derive the state from what is installed.
    rebuild() {
        const cfg = this.cfg;
        const data = { version: 1, names: {}, pending: null };
        let files = [];
        try {
            files = fs.readdirSync(cfg.wildcardDir).filter(function(n) { return /\.pem$/.test(n); });
        } catch (error) {
            files = [];
        }
        files.forEach((file) => {
            const name = file.slice(0, -4);
            const servable = plan.servableManaged(path.join(cfg.wildcardDir, file), this.cfg.env) === name;
            data.names[name] = { state: servable ? "WILDCARD" : "LEGACY", since: new Date(cfg.now).toISOString() };
        });
        if (fs.existsSync(cfg.stateFile) || files.length > 0) {
            this.report.alert(null, "error", "handover state rebuilt from installed wildcards (" + files.length + ")");
        }
        return data;
    }

    save() {
        const cfg = this.cfg;
        fs.mkdirSync(cfg.acmeDir, { recursive: true });
        const tmp = cfg.stateFile + ".tmp." + process.pid;
        const fd = fs.openSync(tmp, "w", 0o600);
        try {
            fs.writeSync(fd, JSON.stringify(this.data, null, 2) + "\n");
            fs.fsyncSync(fd);
        } finally {
            fs.closeSync(fd);
        }
        if (fs.existsSync(cfg.stateFile)) {
            fs.copyFileSync(cfg.stateFile, cfg.stateFile + ".bak");
        }
        crashPoint(cfg, "save:before-rename");
        fs.renameSync(tmp, cfg.stateFile);
        fsyncDir(cfg.acmeDir);
    }

    state(name) {
        const entry = this.data.names[name];
        return entry ? entry.state : "LEGACY";
    }

    setState(name, state) {
        const entry = this.data.names[name] || {};
        if (entry.state !== state) {
            entry.state = state;
            entry.since = new Date(this.cfg.now).toISOString();
        }
        this.data.names[name] = entry;
    }
}

// Journaled file operations. op = { op: "install"|"retire", name, src, dst,
// sha256, nextState }.
function performOp(cfg, op) {
    if (op.op === "install") {
        const dstOk = fs.existsSync(op.dst) && plan.sha256(fs.readFileSync(op.dst)) === op.sha256;
        if (dstOk) return true;
        if (!fs.existsSync(op.src) || plan.sha256(fs.readFileSync(op.src)) !== op.sha256) return false;
        fs.mkdirSync(path.dirname(op.dst), { recursive: true });
        const tmp = op.dst + ".tmp." + process.pid;
        fs.copyFileSync(op.src, tmp);
        fs.chmodSync(tmp, 0o600);
        const fd = fs.openSync(tmp, "r");
        fs.fsyncSync(fd);
        fs.closeSync(fd);
        crashPoint(cfg, "install:copied");
        fs.renameSync(tmp, op.dst);
        fsyncDir(path.dirname(op.dst));
        return true;
    }
    if (op.op === "retire") {
        if (fs.existsSync(op.src)) {
            fs.mkdirSync(path.dirname(op.dst), { recursive: true });
            fs.renameSync(op.src, op.dst);
            fsyncDir(path.dirname(op.src));
            fsyncDir(path.dirname(op.dst));
        }
        return true;
    }
    return false;
}

function runOp(cfg, store, op) {
    store.data.pending = op;
    store.save();
    crashPoint(cfg, op.op + ":begun");
    const done = performOp(cfg, op);
    crashPoint(cfg, op.op + ":performed");
    if (done) store.setState(op.name, op.nextState);
    store.data.pending = null;
    store.save();
    return done;
}

// ---------------------------------------------------------------- run -----

class AcmeRun {
    constructor(env, deps) {
        this.cfg = config(env);
        this.deps = deps || {};
        this.hostname = this.deps.hostname || require("os").hostname();
        this.status = { generatedAt: new Date(this.cfg.now).toISOString(), role: "none", alerts: [], names: {}, domains: {}, dns01: {} };
        this.store = new Store(this.cfg, this);
        this.index = null;
        this.indexFresh = false;
        this.bypassNames = new Set();
        this.leaving = [];
        this.gate = {};
        this.topology = null;
        this.role = "none";
        this.clusterHosts = [];
    }

    alert(name, level, text) {
        const entry = { level: level, text: text };
        if (name) {
            const n = this.status.names[name] || (this.status.names[name] = { alerts: [], events: [] });
            n.alerts.push(entry);
        } else {
            this.status.alerts.push(entry);
        }
        const log = this.deps.log || function() {};
        log(level, (name ? name + ": " : "") + text);
    }

    // J: replay a pending journal operation, sweep temporary files.
    begin() {
        const cfg = this.cfg;
        this.store.load();
        const pending = this.store.data.pending;
        if (pending) {
            const done = performOp(cfg, pending);
            if (done) {
                this.store.setState(pending.name, pending.nextState);
            } else {
                this.alert(pending.name, "error", "pending " + pending.op + " could not be replayed (source gone); state unchanged");
            }
            this.store.data.pending = null;
            this.store.save();
            this.alert(pending.name, "warn", "replayed pending " + pending.op + " after an interrupted run");
        }
        sweepTmp([cfg.wildcardDir, cfg.retiredDir, cfg.bundlesDir, cfg.incomingDir, cfg.acmeDir, cfg.datastoreCertDir]);
        this.loadTopology();
    }

    loadTopology() {
        try {
            const clusterConfig = require("../containers/lib/cluster-config.js");
            const topologyLib = require("../named/lib/topology.js");
            const clusters = clusterConfig.readClusters(this.cfg.clustersFile).clusters;
            this.clusterHosts = [];
            Object.keys(clusters).forEach((cluster) => {
                Object.keys(clusters[cluster] || {}).forEach((host) => this.clusterHosts.push(host));
            });
            const topology = topologyLib.electDnsTopology(clusters);
            this.topology = topology;
            this.role = topologyLib.dnsRoleForHost(topology, this.hostname) || "none";
        } catch (error) {
            this.topology = null;
            this.role = "none";
            this.alert(null, "warn", "no DNS topology (" + error.message + "); wildcard distribution unavailable");
        }
        this.status.role = this.role;
    }

    isPrimary() {
        return this.role === "primary";
    }

    // ---------------------------------------------------------- primary ---

    writeHookConf() {
        const t = this.topology;
        const secondaries = t.replicaIps.join(" ");
        const lines = [
            "ACME_ZONE=_acme." + this.cfg.cdn,
            "ACME_KEY=" + this.cfg.acmeKeyFile,
            "ACME_PRIMARY=" + t.primaryIp,
            "ACME_SECONDARIES=" + secondaries,
            "ACME_TTL=60",
            "ACME_TIMEOUT=180",
            "ACME_POLL=2",
            "ACME_STATE_DIR=" + this.cfg.hookStateDir,
            "ACME_LOCK=" + this.cfg.hookLock,
        ];
        lines.forEach(function(line) {
            if (!/^[A-Z_]+=[A-Za-z0-9_.:/ -]*$/.test(line)) throw new Error("unsafe hook configuration value: " + line);
        });
        atomicWrite(this.cfg.hookConf, lines.join("\n") + "\n", 0o600);
    }

    runHook(mode) {
        return childProcess.execFileSync("bash", [this.cfg.hook, mode],
            { env: Object.assign({}, this.cfg.env, { SC_ACME_HOOK_CONF: this.cfg.hookConf }), encoding: "utf8" });
    }

    // Dates of a lineage's fullchain.pem (no key): only decides whether to
    // publish, and publish() gates the composed bundle.
    lineageView(file) {
        const text = readText(file);
        const meta = text && plan.certMeta(text);
        if (!meta) return null;
        return { notAfter: meta.notAfter };
    }

    // A published bundle counts (is advertised as issued, suppresses
    // renewal) only when it passes the shared servable-managed gate; any
    // other file in bundles/ is treated as absent.
    bundleView(file, name) {
        const text = readText(file);
        const meta = text && plan.certMeta(text);
        if (!meta) return null;
        if (plan.servableManaged(file, this.cfg.env) !== name) {
            this.alert(name, "error", "published bundle " + file + " is not a servable wildcard; ignored, renewal due");
            return null;
        }
        return Object.assign(plan.certView(Object.assign({ servable: true }, meta), this.cfg.now), { notAfter: meta.notAfter });
    }

    // Publish the dedicated lineage as bundles/<name>.pem; returns the index
    // entry or null when the lineage is missing or not servable.
    publish(name) {
        const cfg = this.cfg;
        const live = path.join(cfg.liveDir, "srvctl-wildcard-" + name);
        const privkey = readText(path.join(live, "privkey.pem"));
        const fullchain = readText(path.join(live, "fullchain.pem"));
        if (!privkey || !fullchain) return null;
        const stageDir = path.join(cfg.bundlesDir, ".stage");
        const staged = path.join(stageDir, name + ".pem");
        atomicWrite(staged, bundlelib.composeBundle(privkey, fullchain), 0o600);
        if (plan.servableManaged(staged, cfg.env) !== name) {
            this.alert(name, "error", "lineage srvctl-wildcard-" + name + " is not a servable wildcard; not published");
            return null;
        }
        fs.mkdirSync(cfg.bundlesDir, { recursive: true, mode: 0o700 });
        fs.renameSync(staged, path.join(cfg.bundlesDir, name + ".pem"));
        fsyncDir(cfg.bundlesDir);
        return this.bundleEntry(name);
    }

    bundleEntry(name) {
        const file = path.join(this.cfg.bundlesDir, name + ".pem");
        const text = readText(file);
        if (!text) return null;
        const meta = plan.certMeta(text);
        return { state: "issued", sha256: plan.sha256(text), notAfter: meta ? new Date(meta.notAfter).toISOString() : null };
    }

    certbot(args, name) {
        const cfg = this.cfg;
        fs.mkdirSync(cfg.logDir, { recursive: true });
        const fd = fs.openSync(path.join(cfg.logDir, name + ".log"), "a", 0o600);
        try {
            childProcess.execFileSync(cfg.letsencryptBin, args, { stdio: ["ignore", fd, fd], env: cfg.env });
            return true;
        } catch (error) {
            return false;
        } finally {
            fs.closeSync(fd);
        }
    }

    hostHasChallengeCname(fqdn) {
        try {
            const out = childProcess.execFileSync(this.cfg.digBin,
                ["+time=2", "+tries=1", "+norecurse", "+short", "@127.0.0.1", "_acme-challenge." + fqdn, "CNAME"],
                { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
            return plan.normalizeName(out).endsWith("._acme." + this.cfg.cdn);
        } catch (error) {
            return false;
        }
    }

    // DNS-01 issuance on the elected primary, "regenerate" runs only.
    primaryPhase() {
        const cfg = this.cfg;
        if (!this.isPrimary()) return;
        if (cfg.command !== "regenerate") {
            this.status.dns01.skipped = "not a regenerate run";
            return;
        }
        const snapshot = readJson(cfg.manifestSnapshot);
        const liveSha = (readText(cfg.manifestLiveSha) || "").trim().split(/\s+/)[0];
        if (!snapshot) {
            this.alert(null, "warn", "DNS-01 skipped: no committed zone manifest (the named regenerate has not activated one yet)");
            this.status.dns01.skipped = "no manifest";
            return;
        }
        if (!snapshot.confSha256 || snapshot.confSha256 !== liveSha) {
            this.alert(null, "error", "DNS-01 skipped: the zone manifest does not match the active BIND configuration");
            this.status.dns01.skipped = "manifest mismatch";
            return;
        }
        if (!snapshot.active) {
            this.alert(null, "warn", "DNS-01 skipped: the _acme zone is not active yet");
            this.status.dns01.skipped = "acme zone inactive";
            return;
        }
        this.writeHookConf();
        try {
            this.status.dns01.reconcile = this.runHook("reconcile").trim();
        } catch (error) {
            this.alert(null, "error", "hook reconcile failed: " + String(error.message).split("\n")[0]);
        }

        const indexFile = path.join(cfg.bundlesDir, "index.json");
        const previous = (readJson(indexFile) || {}).entries || {};
        const issueState = readJson(cfg.issueStateFile) || {};
        const entries = {};
        const candidates = [];

        (snapshot.zones || []).forEach((z) => {
            const name = plan.normalizeName(z.zone);
            const nsClass = plan.classifyNS(z.ns, cfg.cdn);
            if (!z.dns01) entries[name] = { state: "not-dns01", kind: "zone", reason: z.reason || "no challenge CNAME" };
            else if (nsClass === "external") entries[name] = { state: "not-dns01", kind: "zone", reason: "served by external DNS" };
            else if (nsClass === "undetermined") {
                entries[name] = previous[name] || { state: "pending", kind: "zone", reason: "name servers undetermined" };
            } else candidates.push({ name: name, kind: "zone" });
        });
        // configured host names (every cluster) whose operator-added
        // _acme-challenge CNAME exists in the company zone
        (this.clusterHosts || []).forEach((fqdn) => {
            const name = plan.normalizeName(fqdn);
            if (!name.includes(".") || entries[name] || candidates.some(function(c) { return c.name === name; })) return;
            if (this.hostHasChallengeCname(name)) candidates.push({ name: name, kind: "host" });
        });

        let issued = 0;
        candidates.sort(function(a, b) { return a.name < b.name ? -1 : 1; }).forEach((c) => {
            let name;
            try {
                name = require("../named/lib/zones.js").canonicalZoneName(c.name);
            } catch (error) {
                entries[c.name] = { state: "not-dns01", kind: c.kind, reason: "not a valid name" };
                return;
            }
            const bundlePath = path.join(cfg.bundlesDir, name + ".pem");
            let view = this.bundleView(bundlePath, name);
            const lineage = this.lineageView(path.join(cfg.liveDir, "srvctl-wildcard-" + name, "fullchain.pem"));
            if (lineage && (!view || lineage.notAfter > view.notAfter)) {
                if (this.publish(name)) view = this.bundleView(bundlePath, name);
            }
            const st = issueState[name] || { failures: 0, lastFailure: 0 };
            let lastError = null;
            if (plan.renewalDue(view)) {
                if (cfg.only && !cfg.only.has(name)) {
                    lastError = "deferred: not in SC_ACME_DNS01_ONLY";
                } else if (cfg.now < plan.backoffUntil(st.failures, st.lastFailure)) {
                    lastError = "backing off after " + st.failures + " failure(s)";
                } else if (issued >= cfg.maxIssue) {
                    lastError = "deferred: per-run issuance cap reached";
                } else {
                    issued++;
                    if (this.certbot(plan.certbotDns01Args(name, cfg.hook, cfg.staging), name) && this.publish(name)) {
                        view = this.bundleView(bundlePath, name);
                        issueState[name] = { failures: 0, lastFailure: 0 };
                    } else {
                        issueState[name] = { failures: st.failures + 1, lastFailure: cfg.now };
                        lastError = "DNS-01 issuance failed (see " + path.join(cfg.logDir, name + ".log") + ")";
                        this.alert(name, "error", lastError);
                    }
                }
            }
            const entry = view ? this.bundleEntry(name) : { state: (issueState[name] || {}).failures ? "failed" : "pending" };
            entry.kind = c.kind;
            if (lastError) entry.lastError = lastError;
            entries[name] = entry;
        });

        Object.keys(previous).forEach(function(name) {
            if (!entries[name]) entries[name] = { state: "not-dns01", kind: previous[name].kind || "zone", reason: "left the DNS-01 zone list" };
        });

        atomicWrite(cfg.issueStateFile, JSON.stringify(issueState, null, 2) + "\n", 0o600);
        fs.mkdirSync(cfg.bundlesDir, { recursive: true, mode: 0o700 });
        atomicWrite(indexFile, JSON.stringify({ version: 1, generatedAt: new Date(cfg.now).toISOString(), entries: entries }, null, 2) + "\n", 0o600);
        this.status.dns01.issued = issued;
        this.status.dns01.names = Object.keys(entries).length;
    }

    // ---------------------------------------------------------- serving ---

    rsync(remote, local) {
        const t = this.topology;
        fs.mkdirSync(path.dirname(local), { recursive: true });
        const tmp = local + ".tmp." + process.pid;
        try {
            childProcess.execFileSync(this.cfg.rsyncBin,
                ["-e", "ssh -o BatchMode=yes -o ConnectTimeout=5", "root@" + t.primary.hostname + ":" + remote, tmp],
                { stdio: ["ignore", "ignore", "pipe"] });
            fs.chmodSync(tmp, 0o600);
            fs.renameSync(tmp, local);
            return true;
        } catch (error) {
            try { fs.unlinkSync(tmp); } catch (e) { /* not created */ }
            return false;
        }
    }

    // Load the index (pulled or local) and stage the bundles of the names
    // this host serves. Failures leave the previous files: freshness decides.
    refresh(servedDomains) {
        const cfg = this.cfg;
        let indexFile;
        let bundleDir;
        if (this.isPrimary()) {
            indexFile = path.join(cfg.bundlesDir, "index.json");
            bundleDir = cfg.bundlesDir;
        } else if (this.topology) {
            indexFile = path.join(cfg.incomingDir, "index.json");
            bundleDir = cfg.incomingDir;
            if (!this.rsync(cfg.bundlesDir + "/index.json", indexFile)) {
                this.alert(null, "warn", "could not pull index.json from " + this.topology.primary.hostname);
            }
        } else {
            return;
        }
        const index = readJson(indexFile);
        this.bundleDir = bundleDir;
        this.index = index && index.entries ? index : null;
        const age = index && index.generatedAt ? cfg.now - Date.parse(index.generatedAt) : Infinity;
        this.indexFresh = Boolean(this.index) && age <= INDEX_MAX_AGE;
        if (this.index && !this.indexFresh) this.alert(null, "warn", "index.json is stale; holding every handover state");
        if (!this.indexFresh || this.isPrimary()) return;
        this.relevantNames(servedDomains).forEach((name) => {
            const entry = this.index.entries[name];
            if (!entry || entry.state !== "issued") return;
            const local = path.join(cfg.incomingDir, name + ".pem");
            const have = readText(local);
            if (have && plan.sha256(have) === entry.sha256) return;
            if (!this.rsync(cfg.bundlesDir + "/" + name + ".pem", local)) {
                this.alert(name, "warn", "could not pull the bundle from " + this.topology.primary.hostname);
            }
        });
    }

    relevantNames(servedDomains) {
        const names = new Set(Object.keys(this.store.data.names));
        if (this.index) {
            const indexNames = Object.keys(this.index.entries);
            servedDomains.forEach(function(d) {
                plan.indexNamesFor(d, indexNames).forEach(function(n) { names.add(n); });
            });
        }
        return Array.from(names).sort();
    }

    installedView(name) {
        const file = path.join(this.cfg.wildcardDir, name + ".pem");
        const text = readText(file);
        if (!text) return { view: plan.certView(null, this.cfg.now), notAfter: 0 };
        const meta = plan.certMeta(text);
        const servable = plan.servableManaged(file, this.cfg.env) === name;
        return {
            view: plan.certView(meta ? Object.assign({ servable: servable }, meta) : null, this.cfg.now),
            notAfter: meta ? meta.notAfter : 0,
        };
    }

    // A validated renewed bundle for name, or null.
    candidate(name, entry, installedNotAfter) {
        if (!entry || entry.state !== "issued" || !entry.sha256 || !this.bundleDir) return null;
        const staged = path.join(this.bundleDir, name + ".pem");
        const text = readText(staged);
        if (!text || plan.sha256(text) !== entry.sha256) return null;
        if (plan.servableManaged(staged, this.cfg.env) !== name) {
            this.alert(name, "error", "bundle rejected: not a servable wildcard for " + name);
            return null;
        }
        const meta = plan.certMeta(text);
        if (!meta || meta.notAfter <= installedNotAfter) return null;
        return { path: staged, sha256: entry.sha256, view: plan.certView(Object.assign({ servable: true }, meta), this.cfg.now) };
    }

    evaluateNames(servedDomains) {
        const cfg = this.cfg;
        this.relevantNames(servedDomains).forEach((name) => {
            const entry = this.indexFresh ? this.index.entries[name] : null;
            const indexState = this.indexFresh ? (entry ? entry.state : "unavailable") : "unavailable";
            const installed = this.installedView(name);
            const bundle = this.candidate(name, entry, installed.notAfter);
            const before = this.store.state(name);
            const result = plan.evaluate({
                state: before,
                index: indexState,
                bundle: bundle ? bundle.view : null,
                wildcard: installed.view,
                fallback: cfg.fallback,
            });
            if (result.install) {
                runOp(cfg, this.store, {
                    op: "install", name: name, src: bundle.path,
                    dst: path.join(cfg.wildcardDir, name + ".pem"), sha256: bundle.sha256, nextState: result.state,
                });
                this.deployRootfs(name);
            } else if (result.state !== before) {
                this.store.setState(name, result.state);
                this.store.save();
            }
            const n = this.status.names[name] || (this.status.names[name] = { alerts: [], events: [] });
            n.state = result.state;
            n.index = indexState;
            n.wildcard = { servable: installed.view.servable, daysLeft: Math.floor(installed.view.daysLeft) };
            n.events = n.events.concat(result.events);
            result.alerts.forEach((a) => this.alert(name, a.level, a.text));
            if (result.http01 === "bypass") this.bypassNames.add(name);
            if (result.retire) this.leaving.push(name);
        });
    }

    // Deploy an installed wildcard into the container rootfs named like the
    // zone, only when it expires later than what the container has.
    deployRootfs(name) {
        const cfg = this.cfg;
        const pki = path.join(cfg.srvRoot, name, "rootfs/etc/pki/tls");
        if (!fs.existsSync(path.join(pki, "private")) || !fs.existsSync(path.join(pki, "certs"))) return;
        const text = readText(path.join(cfg.wildcardDir, name + ".pem"));
        const meta = text && plan.certMeta(text);
        if (!meta) return;
        const current = plan.certMeta(readText(path.join(pki, "certs/localhost.crt")) || "");
        if (current && current.notAfter >= meta.notAfter) return;
        const parts = splitBundle(text);
        atomicWrite(path.join(pki, "private/localhost.key"), parts.privkey, 0o600);
        atomicWrite(path.join(pki, "certs/localhost.crt"), parts.fullchain, 0o644);
        atomicWrite(path.join(pki, "certs", name + ".pem"), text, 0o600);
        atomicWrite(path.join(pki, "certs/localhost.pem"), text, 0o600);
    }

    // The one wildcard rule for every served domain, after installs.
    computeGate(domains) {
        try {
            this.gate = plan.wildcardCoveringMany(Array.from(new Set(domains)), this.cfg.env);
        } catch (error) {
            this.gate = {};
            this.alert(null, "error", "wildcard gate failed (" + String(error.message).split("\n")[0] + "); http-01 is not suppressed");
        }
    }

    bypassed(domain) {
        return plan.indexNamesFor(domain, Array.from(this.bypassNames)).length > 0;
    }

    // true: a servable wildcard covers domain and no fallback/leave is active
    suppressed(domain) {
        if (this.bypassed(domain)) return false;
        return Boolean(this.gate[domain]);
    }

    // ----------------------------------------------------------- leaving --

    replacementDays(domain, excludeFile) {
        const cfg = this.cfg;
        const perDomain = readText(path.join(cfg.datastoreCertDir, domain + ".pem"));
        let best = 0;
        // a replacement counts only if it is servable now: its validity has
        // begun and its key matches (the same test for both sources)
        const servable = (text) => {
            const meta = text && plan.certMeta(text);
            return meta && meta.notBefore <= cfg.now && plan.keyMatchesLeaf(text) ? meta : null;
        };
        const consider = (text) => {
            const meta = servable(text);
            if (!meta) return;
            const names = meta.sans.map(plan.normalizeName);
            const covers = names.includes(domain) || names.some(function(n) {
                return n.startsWith("*.") && plan.indexNamesFor(domain, [n.slice(2)]).length > 0 && domain !== n.slice(2);
            });
            if (covers) best = Math.max(best, (meta.notAfter - cfg.now) / plan.DAY);
        };
        consider(perDomain);
        try {
            // another wildcard the shared rule says covers domain (admin
            // wildcards are often CN-only, so no SAN check here)
            const other = plan.wildcardCovering(domain, Object.assign({}, cfg.env, { SC_WILDCARD_EXCLUDE: excludeFile }));
            const meta = other && servable(readText(other));
            if (meta) best = Math.max(best, (meta.notAfter - cfg.now) / plan.DAY);
        } catch (error) {
            // no other wildcard
        }
        return best;
    }

    finishLeaving(servedDomains) {
        const cfg = this.cfg;
        this.leaving.forEach((name) => {
            const file = path.join(cfg.wildcardDir, name + ".pem");
            const installed = this.installedView(name);
            const covered = servedDomains.filter(function(d) { return plan.indexNamesFor(d, [name]).length > 0; });
            const missing = installed.view.servable ? covered.filter((d) => this.replacementDays(d, file) < RETIRE_MIN_DAYS) : [];
            if (missing.length > 0) {
                this.alert(name, "error", "leaving DNS-01: wildcard kept until replaced (" + missing.join(", ") + ")");
                return;
            }
            runOp(cfg, this.store, {
                op: "retire", name: name, src: file, dst: path.join(cfg.retiredDir, name + ".pem"),
                sha256: null, nextState: "LEGACY",
            });
            this.alert(name, "warn", "wildcard retired; " + name + " is on http-01 again");
        });
    }

    // ------------------------------------------------------------- host ---

    hostPath(hostIp) {
        const cfg = this.cfg;
        const fqdn = plan.normalizeName(this.hostname);
        const report = this.status.domains[fqdn] = { kind: "host" };
        if (!fqdn.includes(".")) return (report.outcome = "no fqdn");
        const scan = (readJson(cfg.hostDnsFile) || {})[fqdn] || {};
        const entry = this.indexFresh ? this.index.entries[fqdn] || this.index.entries[fqdn.split(".").slice(1).join(".")] : null;
        Object.assign(report, plan.classifyDomain(entry || null, scan.NS, cfg.cdn));
        if (this.suppressed(fqdn)) return (report.outcome = "covered by a servable wildcard");
        const existing = plan.certMeta(readText(path.join(cfg.datastoreCertDir, fqdn + ".pem")) || "");
        if (existing && (existing.notAfter - cfg.now) / plan.DAY >= 7) return (report.outcome = "valid certificate");
        if (!cfg.http01) {
            this.alert(fqdn, "error", "host certificate due but http-01 is unavailable (acme-server not running)");
            return (report.outcome = "http-01 unavailable");
        }
        if (!hostIp || !Array.isArray(scan.A) || scan.A.indexOf(hostIp) < 0) {
            return (report.outcome = "A record does not point here");
        }
        if (!this.certbot(plan.certbotHostArgs(fqdn, cfg.staging), fqdn)) {
            this.alert(fqdn, "error", "http-01 issuance failed for the host name");
            return (report.outcome = "issuance failed");
        }
        const live = path.join(cfg.liveDir, fqdn);
        const privkey = readText(path.join(live, "privkey.pem"));
        const fullchain = readText(path.join(live, "fullchain.pem"));
        if (!privkey || !fullchain) return (report.outcome = "no lineage after issuance");
        atomicWrite(path.join(cfg.datastoreCertDir, fqdn + ".pem"), bundlelib.composeBundle(privkey, fullchain), 0o600);
        return (report.outcome = "issued");
    }

    writeStatus() {
        try {
            atomicWrite(this.cfg.statusFile, JSON.stringify(this.status, null, 2) + "\n", 0o600);
        } catch (error) {
            // status is informational
        }
    }
}

module.exports = {
    AcmeRun,
    RETIRE_MIN_DAYS,
    Store,
    atomicWrite,
    config,
    performOp,
    runOp,
    splitBundle,
};
