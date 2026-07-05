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

// ---- monolithic store (v3 format; file-per-entity is WP-C step 2) ----------
const DATASTORE_DIR = process.env.SC_DATASTORE_DIR;

function loadJson(name, { required }) {
  const p = path.join(DATASTORE_DIR, name);
  let raw;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (err) {
    if (required) lib_error("READFILE " + p + " " + err);
    return {};
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    lib_error("READFILE " + p + " " + err);
  }
}

const hosts = loadJson("hosts.json", { required: true });
if (Object.keys(hosts).length < 1) lib_error("READFILE hosts.json has no hosts defined. Eventually run: srvctl update-install");
const users = loadJson("users.json", { required: false });
const containers = loadJson("containers.json", { required: false });

// v3 lablib.js msg(): console.log($BLUE'[ 'shorthost' ]'$GREEN, text, $CLEAR)
// — space-separated args, so the byte layout is exactly this.
const $TAG = "\x1b[34m[ " + os.hostname().split(".")[0] + " ]";
function msg(text) { console.log($TAG + "\x1b[32m", text, "\x1b[0m"); }

// v3 write_users/write_containers: JSON.stringify(obj, null, 2) (no newline),
// then msg("wrote X.json"). In v3 the write is ASYNC (fs.writeFile), so its
// msg fires AFTER all synchronous output; we reproduce that ordering by
// DEFERRING the "wrote" msg to a flush after dispatch (see below).
const pendingWrites = [];
function writeUsers() { fs.writeFileSync(path.join(DATASTORE_DIR, "users.json"), JSON.stringify(users, null, 2)); pendingWrites.push("wrote users.json"); }
function writeContainers() { fs.writeFileSync(path.join(DATASTORE_DIR, "containers.json"), JSON.stringify(containers, null, 2)); pendingWrites.push("wrote containers.json"); }

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
    if (CMD === "new") {
      const rec = newContainer({ containers, users }, ARG, OPA, VAL, { SC_USER, NOW, SC_HOSTNET: ctx.SC_HOSTNET });
      console.log(ARG, OPA, VAL);           // v3 new_container stray debug line
      containers[ARG] = rec;
      writeContainers();
      return exit0();
    }
    if (CMD === "get" && OPA === "exist") return return_value(containers[ARG] !== undefined ? "true" : "false");
    if (containers[ARG] === undefined) return return_error("CONTAINER " + ARG + " DONT EXISTS");
    const container = containers[ARG];
    const C = ARG;
    if (CMD === "put") {
      if (VAL === undefined) delete container[OPA];
      else if (VAL === "true") container[OPA] = true;
      else if (VAL === "false") container[OPA] = false;
      else container[OPA] = VAL;
      writeContainers();
      return exit0();
    }
    if (CMD === "cfg") {
      // v3: `return_value(fn())` then a trailing `exit()` — the update_ip /
      // add_mapped_port fns return undefined (→ return_value sets exit 100),
      // but the trailing exit() overrides exitCode back to 0.
      if (OPA === "update_ip") {
        container.ip = containerUpdateIp({ containers, users }, C, { SC_HOSTNET: ctx.SC_HOSTNET });
        writeContainers();
        msg("Update container " + C + " ip " + container.ip); // v3 container_update_ip msg (sync)
        return_value(undefined);
      } else if (OPA === "add_mapped_port") {
        const parsed = parseMappedPortArgs();
        const entry = containerAddMappedPort({ containers, users }, C, { ...parsed, SC_USER, NOW });
        if (!container.mapped_ports) container.mapped_ports = [];
        container.mapped_ports.push(entry);
        msg("Registering " + entry.proto + " port " + entry.host_port + " for " + C + ":" + entry.container_port); // v3 msg (sync)
        writeContainers();
        return_value(undefined);
      } else {
        return return_error("INTERNAL CFG FUNCTION DONT EXISTS");
      }
      return exit0(); // v3's trailing exit() -> exitCode 0
    }
    if (CMD === "out") {
      if (OPA === "json") return output_json(container);
      output("C", ARG);
      Object.keys(container).forEach((j) => output(j, container[j]));
      return exit0();
    }
    if (CMD === "del") { delete containers[ARG]; writeContainers(); return exit0(); }
    if (CMD === "add") {
      // v3 has TWO sequential `if (CMD===ADD)` blocks, each ending in
      // write_containers()+exit() with no process.exit, so BOTH writes run on
      // every add (the duplicate-ADD FIXME). Reproduced verbatim: two writes →
      // two "wrote containers.json" lines. (A future step may collapse this to
      // one write; that changes output and will update the golden explicitly.)
      if (OPA === "user" && VAL) {
        if (!container.users) container.users = [];
        if (container.users.indexOf(VAL) < 0) container.users.push(VAL);
        return_value(container.users);
      }
      writeContainers();
      if (OPA === "vncuser" && VAL) {
        if (!container.vncusers) container.vncusers = [];
        if (container.vncusers.indexOf(VAL) < 0) container.vncusers.push(VAL);
        return_value(container.vncusers);
      }
      writeContainers();
      return exit0();
    }
    if (CMD === "get") return return_value(containerGet(C, OPA));
    return;
  }
  // --------------------------------------------------------------------- user
  if (DAT === "user") {
    if (CMD === "new") {
      users[ARG] = newUser({ containers, users }, ARG, { SC_USER, NOW });
      writeUsers();
      return exit0();
    }
    if (CMD === "get" && OPA === "exist") return return_value(users[ARG] !== undefined ? "true" : "false");
    if (CMD === "cfg" && ARG === "container_list") return return_value(g.user_container_list(SC_USER));
    if (users[ARG] === undefined) return return_error("USER DONT EXISTS");
    const user = users[ARG];
    const U = ARG;
    if (CMD === "put") {
      if (VAL === undefined) delete user[OPA];
      else if (VAL === "true") user[OPA] = true;
      else if (VAL === "false") user[OPA] = false;
      else user[OPA] = VAL;
      writeUsers();
      return exit0();
    }
    if (CMD === "out") {
      output("U", ARG);
      Object.keys(user).forEach((j) => output(j, user[j]));
      return exit0();
    }
    if (CMD === "del") { delete users[ARG]; writeUsers(); return exit0(); }
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
      users[ARG] = newReseller({ containers, users }, ARG, { SC_USER, NOW });
      writeUsers();
      return exit0();
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
