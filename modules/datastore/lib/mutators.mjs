// modules/datastore/lib/mutators.mjs — pure datastore state-transitions (v4
// port of v3 lib.js's mutators + ip/uid allocation). PURE: each takes the
// current {containers, users} maps + inputs and RETURNS the new record (or a
// value); it does NOT write. The dispatcher applies the result via store.mjs
// and reproduces v3's side effects (the stray new_container debug line, the
// update_ip/add_mapped_port msg lines).
//
// Faithful port — v3 quirks preserved (field insertion ORDER matters for
// byte-identical JSON; the strict === on ip octets; the dead undefined checks).

export class MutatorError extends Error {
  constructor(message) {
    super(message);
    this.name = "MutatorError";
  }
}

// ---- allocation helpers (v3 internals) ------------------------------------

// v3 get_next_user_id: smallest free user_id >= 1, capped at 255.
export function getNextUserId(users) {
  let ret = 1;
  Object.keys(users).forEach(function (i) {
    if (Number(users[i].user_id) >= ret) ret = Number(users[i].user_id) + 1;
  });
  if (ret > 255) throw new MutatorError("Out of range. Can not allocate user_id");
  return ret;
}

// v3 user_uid: existing uid if set, else smallest free uid >= 1000.
export function userUid(users, u) {
  if (users[u]) if (users[u].uid !== undefined) return users[u].uid;
  let ret = 1000;
  Object.keys(users).forEach(function (i) {
    if (Number(users[i].uid) >= ret) ret = Number(users[i].uid) + 1;
  });
  if (ret > 65530) throw new MutatorError("Could not find a valid user uid, out of range.");
  return ret;
}

// v3 find_next_cip_for_container_on_network: next free 4th octet (from 2) on
// the given "10.a.b.x" network. NOTE: strict === compares string octets.
export function findNextCip(containers, network) {
  const nipa = network.split(".");
  let c = 2;
  Object.keys(containers).forEach(function (i) {
    const cipa = containers[i].ip.split(".");
    if (cipa[1] === nipa[1] && cipa[2] === nipa[2]) {
      const cc = Number(cipa[3]);
      if (cc >= c) c = cc + 1;
    }
  });
  if (c > 250) throw new MutatorError("out of range in find_next_cip_for_container_on_network " + network);
  return c;
}

// v3 get_user_id: the acting user's user_id.
export function getUserId(users, SC_USER) {
  return Number(users[SC_USER].user_id);
}

// v3 find_ip_for_container: 10.<SC_HOSTNET>.<acting user_id>.<next c>
export function findIpForContainer(containers, users, { SC_HOSTNET, SC_USER }) {
  const a = SC_HOSTNET;
  const b = getUserId(users, SC_USER);
  const c = findNextCip(containers, "10." + a + "." + b + ".x");
  return "10." + a + "." + b + "." + c;
}

// v3 is_mapped_port: is (proto, n) reserved or already taken across containers.
export function isMappedPort(containers, proto, n) {
  if (n >= 8000 && n <= 10000) return true;
  if (n >= 5900 && n <= 6000) return true;
  if (n < 1024) return true;
  let result = false;
  Object.keys(containers).forEach(function (i) {
    if (containers[i].mapped_ports)
      containers[i].mapped_ports.forEach(function (j) {
        if (j.proto === proto && j.host_port === n) result = true;
      });
  });
  return result;
}

// ---- record builders (return the new record; caller persists) -------------

// v3 new_user: build a user under the acting reseller. Field order preserved.
export function newUser(state, username, { SC_USER, NOW }) {
  const { users } = state;
  if (users[username] !== undefined) throw new MutatorError("USER EXISTS");
  const user = {};
  user.added_by_username = SC_USER;
  user.added_on_datestamp = NOW;
  if (users[SC_USER].reseller_id === undefined) throw new MutatorError("MISSING RESELLER_ID");
  user.reseller = SC_USER;
  user.user_id = getNextUserId(users);
  user.uid = userUid(users, username);
  return user;
}

// v3 new_reseller: allocate the next reseller_id. Field order preserved.
export function newReseller(state, username, { SC_USER, NOW }) {
  const { users } = state;
  if (users[username] !== undefined) throw new MutatorError("USER EXISTS");
  const user = {};
  user.added_by_username = SC_USER;
  user.added_on_datestamp = NOW;
  user.reseller = username;
  let rid = 1;
  Object.keys(users).forEach(function (i) {
    if (users[i].reseller_id >= rid) rid = users[i].reseller_id + 1;
  });
  user.reseller_id = rid;
  user.uid = userUid(users, username);
  return user;
}

// v3 new_container: allocate ip (even with a custom bridge). Field order:
// user, [bridge], ip, creation_time, type. The stray console.log(C,T,B) that
// v3 emits is reproduced by the DISPATCHER, not here.
export function newContainer(state, C, T, B, { SC_USER, NOW, SC_HOSTNET }) {
  const { containers, users } = state;
  if (containers[C] !== undefined) throw new MutatorError("CONTAINER EXISTS");
  const container = {};
  container.user = SC_USER;
  if (B) container.bridge = B;
  container.ip = findIpForContainer(containers, users, { SC_HOSTNET, SC_USER });
  container.creation_time = NOW;
  container.type = T;
  return container;
}

// v3 container_update_ip: recompute ip on the container's owner network.
// Returns the new ip string; the dispatcher assigns it and emits the msg line.
export function containerUpdateIp(state, C, { SC_HOSTNET }) {
  const { containers, users } = state;
  const container = containers[C];
  const a = SC_HOSTNET;
  const b = Number(users[container.user].user_id);
  const c = findNextCip(containers, "10." + a + "." + b + ".x");
  return "10." + a + "." + b + "." + c;
}

// v3 container_add_mapped_port: build one mapped_ports entry with an allocated
// free host_port. The argv juggling (proto/port/comment extraction) stays in
// the dispatcher; this takes the parsed values. Field order: proto, comment,
// container_port, user, timestamp, host_port.
export function containerAddMappedPort(state, C, { proto, container_port, comment, SC_USER, NOW }) {
  const { containers } = state;
  const o = {};
  o.proto = proto;
  o.comment = comment;
  o.container_port = container_port;
  o.user = SC_USER;
  o.timestamp = NOW;
  if (o.container_port < 1) throw new MutatorError("invalid port");
  if (o.container_port > 65535) throw new MutatorError("invalid port");
  // v3 host-port seed ladder (bump low/reserved container ports up).
  let port = o.container_port;
  if (port < 20) port = 1024 + port;
  if (port < 30) port = 2000 + port;
  if (port < 1024) port = 3000 + port;
  if (port > 5000 && port < 10000) port = port - 2000;
  for (let i = port; i < 65535; i++) {
    if (isMappedPort(containers, o.proto, i)) continue;
    port = i;
    break;
  }
  o.host_port = port;
  return o;
}
