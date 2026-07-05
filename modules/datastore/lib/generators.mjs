// modules/datastore/lib/generators.mjs — pure datastore text/config generators
// (v4 port of lib.js's string builders). Like derive.mjs, these are PURE
// functions over an explicit ctx — no module globals, no persisted output
// (recompute on read). Faithful port of v3 (quirks preserved, FIXMEs marked).
//
// ctx = same as derive.mjs, plus:
//   SC_COMPANY_DOMAIN, SC_INSTALL_DIR  (env values v3 read from process.env)
//
// The mutators (new_*, container_add_mapped_port, container_update_ip) and the
// fs-dependent container_useruids are NOT here — they are the WP-C write path
// (container_useruids is exported below but takes passwd/group content as
// explicit inputs, since v3 reads them from a live container rootfs).

import { derivations } from "./derive.mjs";

const BR = "\n";

export function generators(ctx) {
  const { containers, users, hosts, HOSTNAME, SC_COMPANY_DOMAIN, SC_INSTALL_DIR } = ctx;
  const d = derivations(ctx);

  // ---- domain-name normalization (pure over SC_COMPANY_DOMAIN) -------------

  function normalize_container_domain(name) {
    if (!SC_COMPANY_DOMAIN) return name;
    if (name.substring(0, 5) === "mail.") {
      const base = name.substring(5);
      if (base.indexOf(".") < 0) return "mail." + base + "." + SC_COMPANY_DOMAIN;
      return name;
    }
    if (name.indexOf(".") < 0) return name + "." + SC_COMPANY_DOMAIN;
    return name;
  }

  function normalize_mail_domain(name) {
    if (name.substring(0, 5) === "mail.") name = name.substring(5);
    if (name.indexOf(".") < 0 && SC_COMPANY_DOMAIN) return "mail." + name + "." + SC_COMPANY_DOMAIN;
    return "mail." + name;
  }

  // ---- per-container text ---------------------------------------------------

  function container_resolv_conf(C) {
    const container = containers[C];
    let str = "## srvctl generated" + BR;
    if (container.ip) str += "nameserver " + d.container_gw(C) + BR;
    if (hosts[HOSTNAME].dns1) str += "nameserver " + hosts[HOSTNAME].dns1 + BR;
    if (hosts[HOSTNAME].dns2) str += "nameserver " + hosts[HOSTNAME].dns2 + BR;
    str += "nameserver 8.8.8.8" + BR;
    str += "nameserver 8.8.4.4" + BR;
    return str;
  }

  function container_nspawn_network_ethernet(C) {
    const container = containers[C];
    let lines = "";
    if (!container.deprecated) lines += "VirtualEthernetExtra=" + d.container_interface(C) + BR;
    if (container.bridge) lines += "Bridge=" + container.bridge + BR;
    return lines;
  }

  function container_nspawn_network_mapped_ports(C) {
    const container = containers[C];
    if (container.mapped_ports) {
      let str = "";
      for (const i in container.mapped_ports) {
        const p = container.mapped_ports[i];
        str += "## " + p.comment + BR;
        str += "Port=" + p.proto + ":" + p.host_port + ":" + p.container_port + BR;
      }
      return str;
    }
    return "## no mapped ports";
  }

  function container_ethernet(C) {
    const interface_ = d.container_interface(C);
    const ip_br = d.container_br(C);
    let str = "#!/bin/bash" + BR;
    str += BR;
    str += "if ip link set dev " + interface_ + " up" + BR;
    str += "then" + BR;
    str += "    echo '[ OK ] ip link set dev " + interface_ + " up'" + BR;
    str += "else" + BR;
    str += "    echo '[FAIL] ip link set dev " + interface_ + " up'" + BR;
    str += "fi" + BR;
    str += BR;
    str += "if brctl addif " + ip_br + " " + interface_ + BR;
    str += "then" + BR;
    str += "    echo '[ OK ] brctl addif " + ip_br + " " + interface_ + "'" + BR;
    str += "else" + BR;
    str += "    echo '[FAIL] brctl addif " + ip_br + " " + interface_ + "'" + BR;
    str += "fi" + BR;
    str += BR;
    str += "if firewall-cmd --zone=trusted --add-interface=" + ip_br + BR;
    str += "then" + BR;
    str += "    echo '[ OK ] fireall-cmd added " + ip_br + "  to the trusted interfaces'" + BR;
    str += "else" + BR;
    str += "    echo '[FAIL] fireall-cmd could not add " + ip_br + "  to the trusted interfaces'" + BR;
    str += "fi" + BR;
    str += BR;
    str += "if firewall-cmd --permanent --zone=trusted --add-interface=" + ip_br + BR;
    str += "then" + BR;
    str += "    echo '[ OK ] fireall-cmd added " + ip_br + "  to the trusted interfaces'" + BR;
    str += "else" + BR;
    str += "    echo '[FAIL] fireall-cmd could not add " + ip_br + "  to the trusted interfaces'" + BR;
    str += "fi" + BR;
    return str;
  }

  function container_ethernet_network(C) {
    const container = containers[C];
    let str = "## srvctl-generated" + BR;
    str += "[Match]" + BR;
    str += "Virtualization=container" + BR;
    str += "Name=" + d.container_interface(C) + BR;
    str += "" + BR;
    str += "[Network]" + BR;
    str += "Address=" + container.ip + "/24" + BR;
    str += "Gateway=" + d.container_gw(C) + BR;
    str += "DNS=8.8.8.8" + BR;
    str += BR;
    return str;
  }

  function container_hosts(C) {
    const container = containers[C];
    let str = "## srvctl-generated for " + C + BR;
    str += "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4 " + C + BR;
    str += "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6" + BR;
    if (container.ip) {
      str += d.container_gw(C) + " srvctl-gateway" + BR;
    }
    return str;
  }

  function container_quota(C) {
    const container = containers[C];
    let str = "250000000";
    if (container.quota !== undefined) str = container.quota;
    return str;
  }

  function container_nspawn(C) {
    let str = "## srvctl generated - " + C + BR;
    str += "[Network]" + BR;
    str += container_nspawn_network_ethernet(C);
    str += container_nspawn_network_mapped_ports(C);
    str += BR;
    str += "[Exec]" + BR;
    str += "PrivateUsers=" + d.container_uid(C) + BR;
    str += "Capability=CAP_IPC_LOCK" + BR;
    str += "SystemCallFilter=add_key keyctl bpf" + BR;
    str += "" + BR;
    str += "[Files]" + BR;
    str += "PrivateUsersChown=true" + BR;
    str += "BindReadOnly=" + SC_INSTALL_DIR + BR;
    str += "BindReadOnly=/var/srvctl3/share/containers/" + C + BR;
    str += "BindReadOnly=/var/srvctl3/share/common" + BR;
    str += "BindReadOnly=/srv/" + C + "/network:/etc/systemd/network" + BR;
    str += BR;
    str += "BindReadOnly=/srv/" + C + "/hosts:/etc/hosts" + BR;
    str += BR;
    return str;
  }

  function container_br_netdev(C) {
    let str = "## srvctl generated" + BR;
    str += "[NetDev]" + BR;
    str += "Name=" + d.container_br(C) + BR;
    str += "Kind=bridge" + BR;
    return str;
  }

  function container_br_network(C) {
    let str = "## srvctl generated" + BR;
    str += "[Match]" + BR;
    str += "Name=" + d.container_br(C) + BR;
    str += BR;
    str += "[Network]" + BR;
    str += "IPMasquerade=ipv4" + BR;
    str += "Address=" + d.container_gw(C) + "/24" + BR;
    str += "ConfigureWithoutCarrier=yes";
    return str;
  }

  function container_firewall_commands(C) {
    const container = containers[C];
    if (container.mapped_ports) {
      let str = "";
      for (const i in container.mapped_ports) {
        const p = container.mapped_ports[i];
        str += "firewalld_add_service port-" + p.host_port + " " + p.proto + " " + p.host_port + " " + C + BR;
      }
      return str;
    }
    return "## no mapped ports";
  }

  function container_mx(C) {
    if (containers[C].use_gsuite) return false;
    if (C.substring(0, 5) === "mail.") return true;
    if (containers[C].mx !== undefined) return containers[C].mx;
    if (containers["mail." + C] !== undefined) return false;
    return true;
  }

  function container_domains(name) {
    const domains = [];
    if (name.indexOf(".") > 0) {
      domains.push(name);
      domains.push("www." + name);
    }
    if (containers[name].aliases) {
      for (const i in containers[name].aliases) {
        const domain = containers[name].aliases[i];
        domains.push(domain);
        domains.push("www." + domain);
      }
    }
    if (containers[name].altnames) {
      for (const i in containers[name].altnames) {
        const domain = containers[name].altnames[i];
        domains.push(domain);
        domains.push("www." + domain);
      }
    }
    if (containers[name].subdomains) {
      const fqdn = normalize_container_domain(name);
      for (const i in containers[name].subdomains) {
        domains.push(containers[name].subdomains[i] + "." + fqdn);
      }
    }
    return domains;
  }

  // ---- user -----------------------------------------------------------------

  function user_uid(u) {
    if (users[u]) if (users[u].uid !== undefined) return users[u].uid;
    let ret = 1000;
    Object.keys(users).forEach(function (i) {
      if (Number(users[i].uid) >= ret) ret = Number(users[i].uid) + 1;
    });
    // NOTE: v3 return_error on overflow; a pure port throws instead.
    if (ret > 65530) throw new Error("Could not find a valid user uid, out of range.");
    return ret;
  }

  // ---- cluster-wide ---------------------------------------------------------

  function cluster_etc_hosts() {
    let str = "";
    str += "## $SRVCTL generated" + BR;
    str += "127.0.0.1    localhost.localdomain localhost " + HOSTNAME + BR;
    str += "::1    localhost6.localdomain6 localhost6" + BR;
    str += "## hosts" + BR;
    Object.keys(hosts).forEach(function (i) {
      if (hosts[i].host_ip) str += hosts[i].host_ip + "    " + i + BR;
      // FIXME(v4): hardcoded 10.15 (OpenVPN hostnet range) — becomes 10.16
      // under G8 (zerotier). Faithful to v3 for now.
      if (hosts[i].hostnet) str += "10.15." + hosts[i].hostnet + ".0    " + i.split(".")[0] + BR;
    });
    str += "## containers" + BR;
    Object.keys(containers).forEach(function (i) {
      if (containers[i].ip) {
        str += containers[i].ip + "    " + i + BR;
        if (i.indexOf(".") < 0) str += containers[i].ip + "    " + i + ".local" + BR;
        if (i.indexOf(".") < 0) str += containers[i].ip + "    " + i + "." + SC_COMPANY_DOMAIN + BR;
        if (containers["mail." + i] === undefined)
          if (containers[i].is_mail === false) str += "## [disabled] " + containers[i].ip + "    mail." + i + BR;
          else {
            str += containers[i].ip + "    mail." + i + BR;
            str += containers[i].ip + "    mail." + i + "." + SC_COMPANY_DOMAIN + BR;
          }
        if (containers[i].aliases) {
          for (const alias of containers[i].aliases) {
            str += containers[i].ip + "    " + alias + BR;
            if (containers["mail." + i] === undefined)
              if (containers[i].is_mail === false) str += "## [disabled] " + containers[i].ip + "    mail." + alias + BR;
              else str += containers[i].ip + "    mail." + alias + BR;
          }
        }
      }
    });
    return str;
  }

  function cluster_postfix_relaydomains() {
    const rd = [];
    Object.keys(hosts).forEach(function (i) {
      rd.push(i);
    });
    Object.keys(containers).forEach(function (i) {
      if (i.substring(0, 5) === "mail.") rd.push(normalize_container_domain(i.substring(5)));
      else rd.push(normalize_container_domain(i));
      if (containers[i].aliases) for (const alias of containers[i].aliases) rd.push(normalize_container_domain(alias));
    });
    let str = "";
    [...new Set(rd)].forEach(function (i) {
      str += i + "\tOK" + BR;
    });
    return str;
  }

  function cluster_host_keys() {
    let str = "";
    Object.keys(hosts).forEach(function (i) {
      Object.keys(hosts[i]).forEach(function (j) {
        if (j.substring(0, 8) === "host-key") str += hosts[i][j] + BR;
      });
    });
    Object.keys(containers).forEach(function (i) {
      Object.keys(containers[i]).forEach(function (j) {
        if (j.substring(0, 8) === "host-key") str += containers[i][j] + BR;
      });
    });
    return str;
  }

  function cluster_user_list() {
    let str = "";
    Object.keys(users).forEach(function (i) {
      str += i + " ";
    });
    return str;
  }

  function cluster_container_list() {
    let str = "";
    Object.keys(containers).forEach(function (i) {
      str += i + " ";
    });
    return str;
  }

  function cluster_host_list() {
    let str = "";
    Object.keys(hosts).forEach(function (i) {
      str += i + " ";
    });
    return str;
  }

  function cluster_host_ip_list() {
    let str = "";
    Object.keys(hosts).forEach(function (i) {
      if (hosts[i].host_ip !== undefined) str += hosts[i].host_ip + " ";
    });
    return str;
  }

  // user_container_list is per-caller (SC_USER); v3 reads SC_USER from env.
  function user_container_list(SC_USER) {
    let str = " ";
    Object.keys(containers).forEach(function (i) {
      if (containers[i].user === SC_USER) str += i + " ";
      else if (users[containers[i].user].reseller === SC_USER) str += i + " ";
    });
    return str;
  }

  return {
    normalize_container_domain,
    normalize_mail_domain,
    container_resolv_conf,
    container_nspawn_network_ethernet,
    container_nspawn_network_mapped_ports,
    container_ethernet,
    container_ethernet_network,
    container_hosts,
    container_quota,
    container_nspawn,
    container_br_netdev,
    container_br_network,
    container_firewall_commands,
    container_mx,
    container_domains,
    user_uid,
    cluster_etc_hosts,
    cluster_postfix_relaydomains,
    cluster_host_keys,
    cluster_user_list,
    cluster_container_list,
    cluster_host_list,
    cluster_host_ip_list,
    user_container_list,
  };
}

// container_useruids: v3 reads /srv/<C>/rootfs/etc/{passwd,group}. The pure
// port takes those file contents as inputs so it is testable without a live
// container. root_uid = container_uid(C) from derive.mjs.
export function container_useruids(C, root_uid, passwdContent, groupContent) {
  const users = {};
  for (const line of passwdContent.split("\n")) {
    const f = line.split(":");
    users[f[0]] = Number(f[2]);
  }
  const groups = {};
  for (const line of groupContent.split("\n")) {
    const f = line.split(":");
    groups[f[0]] = Number(f[2]);
  }
  function chown(user, group, p) {
    // FIXME(v4): `!users[user]` treats uid 0 as falsy, so a user whose uid is
    // 0 (notably root) is reported "## no user" and skipped — /root never gets
    // chowned. Faithful to v3 (lib.js:575); use `users[user] === undefined` in
    // the rewrite. Same for groups (gid 0).
    if (!users[user]) return "## no user " + user + BR;
    if (!groups[group]) return "## no group " + group + BR;
    return (
      "[[ -d /srv/" + C + "/rootfs" + p + " ]] && chown -R " +
      Number(root_uid + users[user]) + ":" + Number(root_uid + groups[group]) +
      " /srv/" + C + "/rootfs" + p + " && echo '" + p + "'" + BR
    );
  }
  let str = "## srvctl generated - for restore userids shell script" + C + BR;
  str += "root_uid=" + root_uid + BR;
  str += "" + BR;
  str += "#echo 'USERS " + JSON.stringify(users) + "'" + BR;
  str += "#echo 'GROUP " + JSON.stringify(groups) + "'" + BR;
  str += "" + BR;
  str += chown("codepad", "codepad", "/srv/codepad-project");
  str += chown("apache", "apache", "/var/www/html");
  str += chown("mysql", "mysql", "/var/lib/mysql");
  str += chown("mongod", "mongod", "/var/lib/mongo");
  str += "# for u in /srv/" + C + "/rootfs" + BR;
  str += "# do" + BR;
  str += "#   ssh " + C + ' "sc add-user $u"' + BR;
  str += "# done" + BR;
  for (const u in users) {
    if (users[u] >= 1000) str += chown(u, u, "/home/" + u);
  }
  str += chown("root", "root", "/root");
  str += "" + BR;
  str += BR;
  return str;
}
