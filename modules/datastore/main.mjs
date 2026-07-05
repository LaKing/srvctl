// modules/datastore/main.mjs — srvctl v4 datastore verb dispatcher.
//
// Reimplements the v3 modules/datastore/main.js verb API on the pure v4
// modules (derive.mjs / generators.mjs / mutators.mjs). WP-C step 1: still
// reads/writes the MONOLITHIC hosts.json/users.json/containers.json format so
// it is byte-identical to v3 (proven by selftest/verbapi.test.mjs, 61/61).
// The file-per-entity swap (store.mjs) is WP-C step 2.
//
// Contract preserved verbatim (main.js header + the verb golden):
//   argv:  CMD DAT ARG [OPA] [VAL]
//   exit:  0 done/value · 100 empty optional get · 110 MAIN-ERROR ·
//          112 LIB-ERROR · 99 fall-through
//   out:   get=bare value · out=VAR='value' (- -> _, objects JSON.stringify'd,
//          "out container X json"=pretty 4-space, "out host X"=SC_-prefixed)

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createStore, StoreError } from "./lib/store.mjs";
import { derivations } from "./lib/derive.mjs";
import { generators, container_useruids } from "./lib/generators.mjs";
import {
  newUser, newReseller, newContainer, containerUpdateIp, containerAddMappedPort, MutatorError,
} from "./lib/mutators.mjs";

// ---- argv (v3 main.js positions) ------------------------------------------
const CMD = process.argv[2];
const DAT = process.argv[3];
const ARG = process.argv[4];
const OPA = process.argv[5];
const VAL = process.argv[6];

const SC_USER = process.env.SC_USER !== undefined ? process.env.SC_USER : process.env.USER;

// ---- output layer (byte-identical to v3 main.js) --------------------------
process.exitCode = 99;

function exit0() { process.exitCode = 0; }

function return_value(msg) {
  if (msg === undefined || msg === "") process.exitCode = 100;
  else { console.log(msg); process.exitCode = 0; }
}

function return_error(msg) {
  console.error("MAIN-ERROR:", msg);
  process.exitCode = 110;
  process.exit(110);
}

function lib_error(msg) {
  console.error("LIB-ERROR:", msg);
  process.exitCode = 112;
  process.exit(112);
}

function output(variable, value) {
  if (typeof value === "object") value = JSON.stringify(value);
  console.log(variable.replace(/-/g, "_") + "='" + value + "'");
  process.exitCode = 0;
}

function output_json(value) {
  console.log(JSON.stringify(value, null, 4));
  process.exitCode = 0;
}

// ---- file-per-entity store (store.mjs) — WP-C step 2 -----------------------
// Storage is now one file per entity (<dir>/<type>/<id>.json), atomic +
// locked + git-versionable (014). stdout/exit stay byte-identical to v3 (the
// verb golden); only the on-disk layout changes.
const DATASTORE_DIR = process.env.SC_DATASTORE_DIR;

// Effective readonly: v3's SC_DATASTORE_RO guard was dead (bash sets
// SC_DATASTORE_RO_USE, never that). Enforce the EFFECTIVE variable HERE, in
// the writer (store.mjs readOnly) — the fix deferred from step 1. git:false:
// the bash datastore_push wrappers (libs/gitlib.sh) do the git commit, so the
// store must not double-commit.
const READONLY = process.env.SC_DATASTORE_RO_USE === "true";
const store = createStore(DATASTORE_DIR, { readOnly: READONLY, git: false });

// v3 lablib.js msg(): console.log($BLUE'[ 'shorthost' ]'$GREEN, text, $CLEAR)
// — space-separated args, so the byte layout is exactly this.
const $TAG = "\x1b[34m[ " + os.hostname().split(".")[0] + " ]";
function msg(text) { console.log($TAG + "\x1b[32m", text, "\x1b[0m"); }

// Derivations/generators iterate whole maps, so load each type in full.
// Per-entity semantics vs v3's "3 required files": hosts must be non-empty
// (the unmounted/empty-datastore signal, as v3's hosts length check); an
// empty users/containers set is valid (there is no single file to be
// "missing" per-entity). A corrupt entity file → LIB-ERROR 112.
let hosts, users, containers;
try {
  hosts = store.readAll("hosts");
  users = store.readAll("users");
  containers = store.readAll("containers");
} catch (err) {
  lib_error("READFILE " + err);
}
if (Object.keys(hosts).length < 1) lib_error("READFILE hosts has no hosts defined. Eventually run: srvctl update-install");

// SERIALIZED read-modify-write for every mutating verb. The WHOLE
// read → existence-check → allocate/mutate → write runs under ONE store lock
// (store.transaction), re-reading FRESH state inside the lock — so concurrent
// allocations (container ip, user_id/uid, host_port) and same-entity updates
// cannot race. Reads (get/out/exist/cfg-read) stay lock-free on the top-level
// snapshot loaded above.
//
// Error mapping (v3 contract): a MutatorError (or a dispatch-level "DONT
// EXISTS") propagates out of the transaction (lock released by its finally) to
// the outer handler → return_error 110. A readonly store → LIB-ERROR 112
// "Readonly datastore."; a write/parse failure → LIB-ERROR 112.
//
// v3 emitted "wrote X.json" from the ASYNC fs.writeFile callback, so those
// lines come AFTER synchronous output — reproduced by DEFERRING them to a
// flush after dispatch. The label stays "wrote users.json"/"wrote
// containers.json" (byte-exact stdout) though the write targets a per-entity
// file.
const pendingWrites = [];
function runMutation(message, fn) {
  try {
    store.transaction(message, (tx) => {
      const st = {
        hosts: tx.readAll("hosts"),
        users: tx.readAll("users"),
        containers: tx.readAll("containers"),
      };
      fn(tx, st);
    });
  } catch (err) {
    if (err instanceof MutatorError) throw err; // -> outer handler -> return_error 110
    if (err instanceof StoreError && err.code === "READONLY") return lib_error("Readonly datastore.");
    return lib_error("WRITEFILE " + err);
  }
}
function txWrite(tx, type, id, record, wroteMsg) { tx.write(type, id, record); pendingWrites.push(wroteMsg); }
function txRemove(tx, type, id, wroteMsg) { tx.remove(type, id); pendingWrites.push(wroteMsg); }

// ---- derivation / generator context ---------------------------------------
const ctx = {
  containers, users, hosts,
  HOSTNAME: os.hostname(),
  SC_HOSTNET: Number(process.env.SC_HOSTNET),
  SC_COMPANY_DOMAIN: process.env.SC_COMPANY_DOMAIN,
  SC_INSTALL_DIR: process.env.SC_INSTALL_DIR,
  hasLocalRootfs: (C) => fs.existsSync("/srv/" + C + "/rootfs"),
};
const d = derivations(ctx);
const g = generators(ctx);
const NOW = process.env.NOW !== undefined ? process.env.NOW : new Date().toISOString();

// container GET dispatch: OPA -> derived function (v3: datastore["container_"+OPA]).
const CONTAINER_FNS = {
  uid: d.container_uid, br: d.container_br, gw: d.container_gw, interface: d.container_interface,
  br_host_ip: d.container_br_host_ip, bridge: d.container_bridge, user_id: d.container_user_id,
  user_ip_match: d.container_user_ip_match, hostnet: d.container_hostnet, host: d.container_host,
  host_ip: d.container_host_ip, reseller: d.container_reseller, http_port: d.container_http_port,
  https_port: d.container_https_port,
  resolv_conf: g.container_resolv_conf, ethernet: g.container_ethernet,
  ethernet_network: g.container_ethernet_network, hosts: g.container_hosts, quota: g.container_quota,
  nspawn: g.container_nspawn, br_netdev: g.container_br_netdev, br_network: g.container_br_network,
  firewall_commands: g.container_firewall_commands, mx: g.container_mx, domains: g.container_domains,
};
const CLUSTER_FNS = {
  etc_hosts: g.cluster_etc_hosts, postfix_relaydomains: g.cluster_postfix_relaydomains,
  host_keys: g.cluster_host_keys, user_list: g.cluster_user_list,
  container_list: g.cluster_container_list, host_list: g.cluster_host_list,
  host_ip_list: g.cluster_host_ip_list,
};

function containerGet(C, opa) {
  if (opa === "useruids") {
    const passwd = fs.readFileSync("/srv/" + C + "/rootfs/etc/passwd", "utf8");
    const group = fs.readFileSync("/srv/" + C + "/rootfs/etc/group", "utf8");
    return container_useruids(C, d.container_uid(C), passwd, group);
  }
  if (CONTAINER_FNS[opa]) return CONTAINER_FNS[opa](C);
  return containers[C][opa];
}

// ---- argument validation (v3 main.js) -------------------------------------
if (CMD === undefined) return_error("MISSING CMD ARGUMENT: get | put | out | cfg | del | new | add");
if (DAT === undefined) return_error("MISSING DAT ARGUMENT: cluster | user | reseller | container | host");
if (ARG === undefined) return_error("MISSING ARG ARGUMENT: containername / username / hostname / query");
const VERBS = ["get", "put", "out", "cfg", "del", "new", "add"];
const DATS = ["cluster", "user", "container", "host", "reseller"];
if (!VERBS.includes(CMD)) return_error("INVALID CMD ARGUMENT: " + CMD);
if (!DATS.includes(DAT)) return_error("INVALID DAT ARGUMENT: " + DAT);

try {
  dispatch();
} catch (err) {
  if (err instanceof MutatorError) return_error(err.message);
  throw err;
}
// v3 async write callbacks emit their msg after all synchronous output.
for (const w of pendingWrites) msg(w);

function dispatch() {
  // ---------------------------------------------------------------- container
  if (DAT === "container") {
    // --- mutating verbs: fresh read + mutate + write, all under one lock ---
    if (CMD === "new") {
      return runMutation("new container " + ARG, (tx, st) => {
        const rec = newContainer({ containers: st.containers, users: st.users }, ARG, OPA, VAL, { SC_USER, NOW, SC_HOSTNET: ctx.SC_HOSTNET });
        console.log(ARG, OPA, VAL); // v3 new_container stray debug line
        txWrite(tx, "containers", ARG, rec, "wrote containers.json");
        exit0();
      });
    }
    if (CMD === "put") {
      return runMutation("put container " + ARG, (tx, st) => {
        const container = st.containers[ARG];
        if (container === undefined) throw new MutatorError("CONTAINER " + ARG + " DONT EXISTS");
        if (VAL === undefined) delete container[OPA];
        else if (VAL === "true") container[OPA] = true;
        else if (VAL === "false") container[OPA] = false;
        else container[OPA] = VAL;
        txWrite(tx, "containers", ARG, container, "wrote containers.json");
        exit0();
      });
    }
    if (CMD === "cfg") {
      return runMutation("cfg container " + ARG, (tx, st) => {
        const container = st.containers[ARG];
        if (container === undefined) throw new MutatorError("CONTAINER " + ARG + " DONT EXISTS");
        const C = ARG;
        // v3: `return_value(fn())` then a trailing `exit()` — the fns return
        // undefined (return_value sets 100), the trailing exit() forces 0.
        if (OPA === "update_ip") {
          container.ip = containerUpdateIp({ containers: st.containers, users: st.users }, C, { SC_HOSTNET: ctx.SC_HOSTNET });
          txWrite(tx, "containers", C, container, "wrote containers.json");
          msg("Update container " + C + " ip " + container.ip); // v3 msg (sync)
          return_value(undefined);
        } else if (OPA === "add_mapped_port") {
          const parsed = parseMappedPortArgs();
          const entry = containerAddMappedPort({ containers: st.containers, users: st.users }, C, { ...parsed, SC_USER, NOW });
          if (!container.mapped_ports) container.mapped_ports = [];
          container.mapped_ports.push(entry);
          msg("Registering " + entry.proto + " port " + entry.host_port + " for " + C + ":" + entry.container_port); // v3 msg (sync)
          txWrite(tx, "containers", C, container, "wrote containers.json");
          return_value(undefined);
        } else {
          throw new MutatorError("INTERNAL CFG FUNCTION DONT EXISTS");
        }
        exit0(); // v3's trailing exit() -> exitCode 0
      });
    }
    if (CMD === "del") {
      return runMutation("del container " + ARG, (tx, st) => {
        if (st.containers[ARG] === undefined) throw new MutatorError("CONTAINER " + ARG + " DONT EXISTS");
        txRemove(tx, "containers", ARG, "wrote containers.json");
        exit0();
      });
    }
    if (CMD === "add") {
      return runMutation("add container " + ARG, (tx, st) => {
        const container = st.containers[ARG];
        if (container === undefined) throw new MutatorError("CONTAINER " + ARG + " DONT EXISTS");
        const C = ARG;
        // v3 has TWO sequential `if (CMD===ADD)` blocks, each ending in
        // write_containers()+exit(), so BOTH writes run on every add (the
        // duplicate-ADD FIXME → two "wrote containers.json" lines). Reproduced
        // for byte-exact stdout; the transaction dedups to a single file write.
        if (OPA === "user" && VAL) {
          if (!container.users) container.users = [];
          if (container.users.indexOf(VAL) < 0) container.users.push(VAL);
          return_value(container.users);
        }
        txWrite(tx, "containers", C, container, "wrote containers.json");
        if (OPA === "vncuser" && VAL) {
          if (!container.vncusers) container.vncusers = [];
          if (container.vncusers.indexOf(VAL) < 0) container.vncusers.push(VAL);
          return_value(container.vncusers);
        }
        txWrite(tx, "containers", C, container, "wrote containers.json");
        exit0();
      });
    }
    // --- reading verbs: lock-free on the top-level snapshot ---
    if (CMD === "get" && OPA === "exist") return return_value(containers[ARG] !== undefined ? "true" : "false");
    if (containers[ARG] === undefined) return return_error("CONTAINER " + ARG + " DONT EXISTS");
    const container = containers[ARG];
    const C = ARG;
    if (CMD === "out") {
      if (OPA === "json") return output_json(container);
      output("C", ARG);
      Object.keys(container).forEach((j) => output(j, container[j]));
      return exit0();
    }
    if (CMD === "get") return return_value(containerGet(C, OPA));
    return;
  }
  // --------------------------------------------------------------------- user
  if (DAT === "user") {
    // --- mutating verbs under one lock ---
    if (CMD === "new") {
      return runMutation("new user " + ARG, (tx, st) => {
        const rec = newUser({ containers: st.containers, users: st.users }, ARG, { SC_USER, NOW });
        txWrite(tx, "users", ARG, rec, "wrote users.json");
        exit0();
      });
    }
    if (CMD === "get" && OPA === "exist") return return_value(users[ARG] !== undefined ? "true" : "false");
    if (CMD === "cfg" && ARG === "container_list") return return_value(g.user_container_list(SC_USER));
    if (CMD === "put") {
      return runMutation("put user " + ARG, (tx, st) => {
        const user = st.users[ARG];
        if (user === undefined) throw new MutatorError("USER DONT EXISTS");
        if (VAL === undefined) delete user[OPA];
        else if (VAL === "true") user[OPA] = true;
        else if (VAL === "false") user[OPA] = false;
        else user[OPA] = VAL;
        txWrite(tx, "users", ARG, user, "wrote users.json");
        exit0();
      });
    }
    if (CMD === "del") {
      return runMutation("del user " + ARG, (tx, st) => {
        if (st.users[ARG] === undefined) throw new MutatorError("USER DONT EXISTS");
        txRemove(tx, "users", ARG, "wrote users.json");
        exit0();
      });
    }
    // --- reading verbs: lock-free ---
    if (users[ARG] === undefined) return return_error("USER DONT EXISTS");
    const user = users[ARG];
    const U = ARG;
    if (CMD === "out") {
      output("U", ARG);
      Object.keys(user).forEach((j) => output(j, user[j]));
      return exit0();
    }
    if (CMD === "get") {
      if (OPA === "uid") return return_value(g.user_uid(U));
      if (OPA === "container_list") return return_value(g.user_container_list(SC_USER));
      return return_value(user[OPA]);
    }
    return;
  }
  // ----------------------------------------------------------------- reseller
  if (DAT === "reseller") {
    if (CMD === "new") {
      return runMutation("new reseller " + ARG, (tx, st) => {
        const rec = newReseller({ containers: st.containers, users: st.users }, ARG, { SC_USER, NOW });
        txWrite(tx, "users", ARG, rec, "wrote users.json");
        exit0();
      });
    }
    return;
  }
  // --------------------------------------------------------------------- host
  if (DAT === "host") {
    if (hosts[ARG] === undefined) return return_error("HOST " + ARG + " DONT EXISTS " + JSON.stringify(Object.keys(hosts)));
    const host = hosts[ARG];
    if (CMD === "get") return return_value(host[OPA]);
    if (CMD === "out") {
      output("SC_HOSTNAME", ARG);
      Object.keys(host).forEach((j) => output("SC_" + j.toUpperCase(), host[j]));
      return exit0();
    }
    return;
  }
  // ------------------------------------------------------------------ cluster
  if (DAT === "cluster") {
    if (CMD === "get") {
      if (CLUSTER_FNS[ARG]) return return_value(CLUSTER_FNS[ARG]());
    }
    return;
  }
}

// v3 container_add_mapped_port argv juggling — reproduced verbatim.
// argv: [node, main, cfg, container, C, add_mapped_port, a6, a7, a8, ...]
function parseMappedPortArgs() {
  let proto = "tcp";
  let port_arg = process.argv[7];
  let comment = process.argv.slice(7).join(" ");
  if (process.argv[6] === "udp" || process.argv[6] === "tcp") proto = process.argv[6];
  if (process.argv[7] === "udp" || process.argv[7] === "tcp") {
    proto = process.argv[7];
    port_arg = process.argv[8];
    comment = process.argv.slice(8).join(" ");
  }
  let container_port;
  if (port_arg.indexOf(":") >= 0) {
    if (port_arg.split(":")[0] === "udp") proto = "udp";
    container_port = Number(port_arg.split(":")[1]);
  } else container_port = Number(port_arg);
  return { proto, container_port, comment };
}
