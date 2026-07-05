// modules/datastore/lib/derive.mjs — pure datastore derivations (v4 port).
//
// v3 lib.js computed a container's addressing and identity (uid, bridge,
// gateway, interface name, host placement, reseller, ports) from the raw
// records, using module-global `containers/users/hosts/SC_HOSTNET/HOSTNAME`.
// v4 makes these PURE FUNCTIONS over an explicit context (D4/D5; boilerplate
// `fun/`): no module globals, no persisted derived data — recompute on read.
//
// This is a FAITHFUL port of the v3 math, quirks included (G3: preserve
// behavior, file bugs as FIXME, do not silently fix). Snapshot-tested against
// hand-computed expected values in selftest/derive.test.mjs.
//
// ctx = {
//   containers, users, hosts,   // v3-style { id: record } maps (from store.readAll)
//   SC_HOSTNET,                 // this host's hostnet id
//   HOSTNAME,                   // this host's name
//   hasLocalRootfs,             // (C) => bool; defaults to fs.existsSync(/srv/C/rootfs)
// }

import fs from "node:fs";

const DOT = ".";

export function derivations(ctx) {
  const { containers, users, hosts, SC_HOSTNET, HOSTNAME } = ctx;
  const hasLocalRootfs =
    ctx.hasLocalRootfs || ((C) => fs.existsSync("/srv/" + C + "/rootfs"));

  // v3: 65536 * (user_id * 255 + ipOctet4). Custom-bridge containers may have
  // no ip yet → octet defaults to 1.
  function container_uid(C) {
    const container = containers[C];
    const b = Number(users[container.user].user_id);
    let c = 1;
    if (container.ip) c = Number(container.ip.split(DOT)[3] || 1);
    return 65536 * (b * 255 + c);
  }

  // Derived bridge address "10.<oct2>.<oct3>.x" unless an explicit `br` is set.
  function container_br(C) {
    const container = containers[C];
    if (container.br) return container.br;
    const cipa = container.ip.split(DOT);
    return "10" + DOT + Number(cipa[1]) + DOT + Number(cipa[2]) + DOT + "x";
  }

  // Default gateway "<oct1>.<oct2>.<oct3>.1" unless an explicit `gateway`.
  function container_gw(C) {
    const container = containers[C];
    if (container.gateway) return container.gateway;
    const cipa = container.ip.split(DOT);
    return Number(cipa[0]) + DOT + Number(cipa[1]) + DOT + Number(cipa[2]) + DOT + "1";
  }

  // Interface name; separator encodes the network class (192 → "_", 172 → "+",
  // else "-"). Explicit `interface` wins.
  function container_interface(C) {
    const container = containers[C];
    if (container.interface) return container.interface;
    const cipa = container.ip.split(DOT);
    if (Number(cipa[0]) === 192) return Number(cipa[1]) + "_" + Number(cipa[2]) + "_" + Number(cipa[3]);
    if (Number(cipa[0]) === 172) return Number(cipa[1]) + "+" + Number(cipa[2]) + "+" + Number(cipa[3]);
    return Number(cipa[1]) + "-" + Number(cipa[2]) + "-" + Number(cipa[3]);
  }

  function container_br_host_ip(C) {
    const cipa = containers[C].ip.split(DOT);
    return "10" + DOT + Number(cipa[1]) + DOT + Number(cipa[2]) + DOT + "1";
  }

  // Custom bridge name, or false when srvctl manages the bridge.
  function container_bridge(C) {
    return containers[C].bridge || false;
  }

  function container_user_id(C) {
    return Number(users[containers[C].user].user_id);
  }

  // FIXME(v4): strict === compares user_id (may be number) against the parsed
  // 3rd ip octet; if user_id is stored as a string this never matches. v3
  // behavior preserved verbatim (see modules/datastore/lib.js:239).
  function container_user_ip_match(C) {
    const container = containers[C];
    if (container.bridge) return true;
    const cipa = container.ip.split(DOT);
    if (users[container.user].user_id === Number(cipa[2])) return true;
    return false;
  }

  // NOTE: returns the ip's 2nd octet as a STRING (v3 behavior); bridge
  // containers return SC_HOSTNET. Callers compare it with loose == (below).
  function container_hostnet(C) {
    const container = containers[C];
    if (container.bridge) return SC_HOSTNET;
    return container.ip.split(DOT)[1];
  }

  // Which host serves this container: the local host if its rootfs exists
  // here, else the host whose hostnet matches (loose == across string/number).
  function container_host(C) {
    if (hasLocalRootfs(C)) return HOSTNAME;
    const hostnet = container_hostnet(C);
    let ret;
    Object.keys(hosts).forEach(function (i) {
      if (hosts[i].hostnet == hostnet) ret = i; // eslint-disable-line eqeqeq
    });
    return ret;
  }

  function container_host_ip(C) {
    const hostnet = container_hostnet(C);
    let ret = "ERROR datastore/lib.js: container_host_ip not found";
    Object.keys(hosts).forEach(function (i) {
      if (hosts[i].hostnet == hostnet) ret = hosts[i].host_ip; // eslint-disable-line eqeqeq
    });
    return ret;
  }

  function container_reseller(C) {
    const container = containers[C];
    if (users[container.user].reseller_id !== undefined) return container.user;
    if (users[container.user].reseller !== undefined) return users[container.user].reseller;
    return "root";
  }

  function container_http_port(C) {
    return containers[C].http_port || 80;
  }

  function container_https_port(C) {
    return containers[C].https_port || 443;
  }

  return {
    container_uid,
    container_br,
    container_gw,
    container_interface,
    container_br_host_ip,
    container_bridge,
    container_user_id,
    container_user_ip_match,
    container_hostnet,
    container_host,
    container_host_ip,
    container_reseller,
    container_http_port,
    container_https_port,
  };
}
