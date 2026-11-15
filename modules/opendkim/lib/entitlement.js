/*
 * modules/opendkim/lib/entitlement.js — who may get a DKIM signature for what.
 *
 * Pure functions over the datastore records, used by opendkim.js and by
 * selftest/entitlement.test.mjs. The gateway OpenDKIM signs a message for the
 * header From domain D only when the sender is entitled to D:
 *   - a container client (its IP) owns: its own name, its name without a
 *     leading 'mail.' (mail.X owns X), its aliases, and the names (without
 *     'mail.') and aliases of every container S whose mail_ve hands its mail
 *     to it (as cluster_mail_ve_map in datastore/lib/generators.mjs);
 *   - an alias never grants a name that is another container's own name (or
 *     that name without 'mail.'): container owners set aliases themselves
 *     (set-ve-alias is owner_only), add-ve and set-ve-mail-ve are not;
 *   - host-local mail (pickup/sendmail, seen as 127.0.0.1 / ::1) may sign the
 *     cluster host names and SC_COMPANY_DOMAIN.
 * Only domains with a key (the KeyTable domains: container names that are not
 * .devel/-devel/.local/-local) can be signed at all, so every list is cut to
 * those. Unentitled mail is not signed (verified like inbound mail) rather than
 * rejected; see documentation.md, OpenDKIM.
 * The output depends only on the records, never on the generating host: the
 * datastore folder may be shared by the hosts of a cluster.
 */

'use strict';

// Same rule as the key generation in opendkim.js, the datastore keys and the
// named module's zone records (and conf/signing-policy.lua).
function selector(domain) {
    return domain.substring(0, 5) === 'mail.' ? 'mail' : 'default';
}

function signable(name) {
    const tail = name.substr(name.length - 6);
    return tail !== '.devel' && tail !== '-devel' && tail !== '.local' && tail !== '-local';
}

function strip_mail(name) {
    return name.substring(0, 5) === 'mail.' ? name.substring(5) : name;
}

function sorted(set) {
    return [...set].sort();
}

// {containers, hosts, SC_COMPANY_DOMAIN} -> {signable, entitled, host}
//   signable: domains that have a key
//   entitled: '<ip>/<domain>' lines (container IPs and loopback)
//   host:     the host's own signable domains (host-local mail)
function entitlement({ containers, hosts, SC_COMPANY_DOMAIN }) {
    containers = containers || {};
    const names = Object.keys(containers);
    const keys = new Set(names.filter(signable).map(n => n.toLowerCase()));

    // name -> container whose own name (or own name without mail.) it is
    const reserved = new Map();
    for (const n of names) {
        reserved.set(n.toLowerCase(), n);
        if (!reserved.has(strip_mail(n).toLowerCase())) reserved.set(strip_mail(n).toLowerCase(), n);
    }
    const aliases_of = function (n) {
        const a = containers[n].aliases;
        return Array.isArray(a) ? a.map(x => String(x).toLowerCase()) : [];
    };
    // an alias of container n counts unless it is somebody else's own name
    const own_aliases = function (n) {
        return aliases_of(n).filter(a => !reserved.has(a) || reserved.get(a) === n);
    };

    const entitled = new Set();
    for (const c of names) {
        const ip = containers[c].ip;
        if (!ip) continue;
        const owned = new Set([c.toLowerCase(), strip_mail(c).toLowerCase(), ...own_aliases(c)]);
        for (const s of names) {
            if (containers[s].mail_ve !== c) continue;
            owned.add(strip_mail(s).toLowerCase());
            for (const a of own_aliases(s)) owned.add(a);
        }
        for (const d of owned) if (keys.has(d)) entitled.add(ip + '/' + d);
    }

    const host = new Set();
    for (const h of Object.keys(hosts || {}).concat(SC_COMPANY_DOMAIN ? [SC_COMPANY_DOMAIN] : [])) {
        if (keys.has(h.toLowerCase())) host.add(h.toLowerCase());
    }
    for (const d of host) {
        entitled.add('127.0.0.1/' + d);
        entitled.add('::1/' + d);
    }

    return { signable: sorted(keys), entitled: sorted(entitled), host: sorted(host) };
}

const HEADER = '## srvctl generated (modules/opendkim/lib/entitlement.js). Mail whose header From\n' +
    '## domain the sender is not entitled to is not signed (it is verified like inbound mail).\n';

// The files opendkim.js writes into the datastore opendkim folder.
function tables(e) {
    return {
        InternalHosts: HEADER + '127.0.0.1\n::1\n',
        EntitledSigners: HEADER + e.entitled.map(l => l + '\n').join(''),
        SignableDomains: HEADER + e.signable.map(d => d + '\n').join(''),
        HostSigningTable: HEADER + e.host.map(d => '*@' + d + ' ' + selector(d) + '._domainkey.' + d + '\n').join(''),
        EmptySigningTable: HEADER + '## nothing is signed through the SigningTable; see SetupPolicyScript\n'
    };
}

module.exports = { selector, signable, entitlement, tables };
