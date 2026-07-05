// modules/datastore/lib/store.mjs — srvctl v4 datastore storage engine.
//
// Production-grade light JSON storage that stays human-readable and
// human-editable (014-datastore). Zero external dependencies — Node builtins
// only (D4: own the code).
//
// Design (why v3 was fragile → what this fixes):
//   - ONE FILE PER ENTITY   <root>/<type>/<id>.json   (directory = table,
//     file = row). Writers on different entities cannot collide; a corrupt
//     file loses one row, not the store; hand-editing touches one small doc.
//   - ATOMIC WRITES         temp file → fsync → rename() over the target.
//     A reader always sees a complete old or complete new file, never torn;
//     a crash mid-write cannot truncate the live file. Reads are lock-free.
//   - SINGLE LOCKED WRITER  every mutation takes an exclusive lockfile
//     (stale-steal), so concurrent `sc` invocations serialize instead of
//     clobbering. The read-only guard lives here (not a dead env check).
//   - VALIDATE ON WRITE     a per-type validator can reject a bad record
//     before it is persisted; the old file is kept.
//   - GIT-VERSIONED         best-effort commit after each change — the file
//     is the durable truth, git is the audit log (every change reversible).
//
// Records are stored exactly as v3 wrote them: JSON.stringify(record, null, 2)
// + trailing newline. Entity maps in v3 were { id: {..record..} }; here each
// record is its own file. resellers are DERIVED from users, never stored.

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const LOCK_STALE_MS = 30_000; // a lock older than this is considered abandoned
const LOCK_WAIT_MS = 10_000; // how long to wait for a contended lock
const LOCK_POLL_MS = 50;

// ---- id / path safety -----------------------------------------------------

// Entity ids become filenames, so they must not escape their type directory.
// Allow the characters real srvctl ids use (hostnames, usernames, container
// domain names): letters, digits, dot, dash, underscore. No slash, no "..",
// no leading dot.
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

function assertId(id) {
  if (typeof id !== "string" || !ID_RE.test(id) || id.includes("..")) {
    throw new StoreError("INVALID-ID", `unsafe entity id: ${JSON.stringify(id)}`);
  }
  return id;
}

function assertType(type) {
  if (typeof type !== "string" || !/^[a-z][a-z0-9]*$/.test(type)) {
    throw new StoreError("INVALID-TYPE", `unsafe entity type: ${JSON.stringify(type)}`);
  }
  return type;
}

export class StoreError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "StoreError";
    this.code = code;
  }
}

// ---- atomic write ---------------------------------------------------------

function serialize(record) {
  return JSON.stringify(record, null, 2) + "\n";
}

// Write `data` to `target` atomically: temp in the same dir, fsync the file,
// rename over target, fsync the directory so the rename is durable.
function atomicWrite(target, data) {
  const dir = path.dirname(target);
  fs.mkdirSync(dir, { recursive: true });
  // Unique temp name in the SAME directory (rename is only atomic within a fs).
  const tmp = path.join(dir, `.${path.basename(target)}.${process.pid}.${atomicWrite._n++}.tmp`);
  let fd;
  try {
    fd = fs.openSync(tmp, "wx", 0o600);
    fs.writeSync(fd, data);
    fs.fsyncSync(fd);
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
  try {
    fs.renameSync(tmp, target);
  } catch (err) {
    try { fs.unlinkSync(tmp); } catch { /* best effort */ }
    throw err;
  }
  // Durability of the rename: fsync the containing directory.
  try {
    const dfd = fs.openSync(dir, "r");
    try { fs.fsyncSync(dfd); } finally { fs.closeSync(dfd); }
  } catch { /* directory fsync unsupported on some platforms — non-fatal */ }
}
atomicWrite._n = 0;

// ---- the store ------------------------------------------------------------

export function createStore(rootDir, options = {}) {
  const {
    validators = {}, // { type: (record, id) => void, throws StoreError on invalid }
    git = true, // best-effort git-commit each change
    readOnly = false, // the RO guard, enforced HERE (fixes v3's dead guard)
    lockWaitMs = LOCK_WAIT_MS, // how long to wait for a contended lock
    lockStaleMs = LOCK_STALE_MS, // a lock older than this is stealable
    lockPollMs = LOCK_POLL_MS,
  } = options;
  const now = Date.now;

  const root = path.resolve(rootDir);
  const lockPath = path.join(root, ".lock");

  function typeDir(type) {
    return path.join(root, assertType(type));
  }
  function filePath(type, id) {
    return path.join(typeDir(type), `${assertId(id)}.json`);
  }

  // ---- reads (lock-free) --------------------------------------------------

  function read(type, id) {
    let raw;
    try {
      raw = fs.readFileSync(filePath(type, id), "utf8");
    } catch (err) {
      if (err.code === "ENOENT") return null;
      throw new StoreError("READ", `read ${type}/${id}: ${err.message}`);
    }
    try {
      return JSON.parse(raw);
    } catch (err) {
      throw new StoreError("PARSE", `corrupt json in ${type}/${id}: ${err.message}`);
    }
  }

  function has(type, id) {
    return fs.existsSync(filePath(type, id));
  }

  function list(type) {
    let names;
    try {
      names = fs.readdirSync(typeDir(type));
    } catch (err) {
      if (err.code === "ENOENT") return [];
      throw err;
    }
    return names
      .filter((n) => n.endsWith(".json") && !n.startsWith("."))
      .map((n) => n.slice(0, -5))
      .sort();
  }

  // Load a whole type as the v3-style { id: record } map (compat for callers
  // and for derivation functions that want the full set).
  function readAll(type) {
    const out = {};
    for (const id of list(type)) out[id] = read(type, id);
    return out;
  }

  // ---- locking ------------------------------------------------------------

  function acquireLock() {
    fs.mkdirSync(root, { recursive: true });
    const deadline = now() + lockWaitMs;
    for (;;) {
      try {
        const fd = fs.openSync(lockPath, "wx");
        fs.writeSync(fd, `${process.pid} ${now()}\n`);
        fs.closeSync(fd);
        return;
      } catch (err) {
        if (err.code !== "EEXIST") throw err;
        // Someone holds it. Steal if stale.
        let stale = false;
        try {
          const st = fs.statSync(lockPath);
          if (now() - st.mtimeMs > lockStaleMs) stale = true;
        } catch {
          continue; // lock vanished — retry immediately
        }
        if (stale) {
          try { fs.unlinkSync(lockPath); } catch { /* raced — retry */ }
          continue;
        }
        if (now() >= deadline) {
          throw new StoreError("LOCK-TIMEOUT", `datastore lock held > ${lockWaitMs}ms`);
        }
        sleep(lockPollMs);
      }
    }
  }

  function releaseLock() {
    try { fs.unlinkSync(lockPath); } catch { /* already gone */ }
  }

  // ---- git (best-effort audit log) ----------------------------------------

  function gitCommit(message) {
    if (!git) return;
    if (!fs.existsSync(path.join(root, ".git"))) {
      run(["init", "-q"]);
      run(["config", "user.name", "srvctl"]);
      run(["config", "user.email", "srvctl@localhost"]);
    }
    run(["add", "-A"]);
    // commit may be a no-op (nothing changed) — that's fine, ignore failure.
    run(["commit", "-q", "-m", message]);
    function run(args) {
      try {
        spawnSync("git", ["-C", root, ...args], { stdio: "ignore" });
      } catch { /* git absent or failed — the file write already succeeded */ }
    }
  }

  // ---- writes (locked, validated, atomic, versioned) ----------------------

  function guardWritable() {
    if (readOnly) throw new StoreError("READONLY", "datastore is read-only");
  }

  function validate(type, record, id) {
    const v = validators[type];
    if (v) v(record, id);
  }

  function write(type, id, record) {
    guardWritable();
    assertType(type);
    assertId(id);
    validate(type, record, id);
    acquireLock();
    try {
      atomicWrite(filePath(type, id), serialize(record));
      gitCommit(`write ${type}/${id}`);
    } finally {
      releaseLock();
    }
    return record;
  }

  function remove(type, id) {
    guardWritable();
    const fp = filePath(type, id);
    acquireLock();
    try {
      try {
        fs.unlinkSync(fp);
      } catch (err) {
        if (err.code !== "ENOENT") throw err;
        return false;
      }
      gitCommit(`delete ${type}/${id}`);
      return true;
    } finally {
      releaseLock();
    }
  }

  // Coarse store-level transaction for multi-entity changes (rare): the whole
  // callback runs under one lock, and one git commit captures all of it.
  function transaction(message, fn) {
    guardWritable();
    acquireLock();
    try {
      const tx = {
        read,
        list,
        has,
        readAll,
        write(type, id, record) {
          assertType(type); assertId(id); validate(type, record, id);
          atomicWrite(filePath(type, id), serialize(record));
        },
        remove(type, id) {
          try { fs.unlinkSync(filePath(type, id)); return true; }
          catch (err) { if (err.code === "ENOENT") return false; throw err; }
        },
      };
      const result = fn(tx);
      gitCommit(message);
      return result;
    } finally {
      releaseLock();
    }
  }

  return { root, read, has, list, readAll, write, remove, transaction, readOnly };
}

// Busy-sleep in ms without pulling in a timer (we are a short-lived CLI and
// the lock poll interval is tiny). Uses Atomics.wait on a throwaway buffer.
function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}
