/*
 * modules/opendkim/lib/keys.js — where the DKIM key of a domain comes from.
 *
 * Pure, used by opendkim.js and selftest/keys.test.mjs. key_plan answers, for
 * one container domain:
 *   genkey   /srv/<domain> exists here and has no private key: generate one
 *            there (existing keys are never regenerated — DNS holds the
 *            public half), then copy it;
 *   copy     /srv/<domain>/opendkim/<selector>.private is the key: copy it to
 *            the host-side folder and publish the .txt public key;
 *   hostside a domain-only record (retire-ve): its container files are gone
 *            on purpose, the host-side copy in the opendkim datastore folder
 *            IS the key. Never generated, never copied over, the published
 *            dkim-<selector>-domainkey never rewritten — even when a leftover
 *            /srv/<domain> exists;
 *   missing  a domain-only record whose host-side key is gone (an error to
 *            report: its mail is not signed until the key is restored);
 *   none     no /srv/<domain> here (hosted elsewhere): nothing to do with the
 *            key, as before.
 */

'use strict';

const path = require('path');
const { selector } = require('./entitlement.js');

// {domain, record, srvRoot, opendkimFolder, exists(path) -> bool}
function key_plan({ domain, record, srvRoot, opendkimFolder, exists }) {
    const sel = selector(domain);
    const plan = {
        selector: sel,
        private_file: path.join(srvRoot, domain, 'opendkim', sel + '.private'),
        txt_file: path.join(srvRoot, domain, 'opendkim', sel + '.txt'),
        opendkim_folder: path.join(srvRoot, domain, 'opendkim'),
        hostside_file: path.join(opendkimFolder, domain, sel + '.private'),
    };
    if (record && record.domain_only === true) {
        plan.action = exists(plan.hostside_file) ? 'hostside' : 'missing';
        return plan;
    }
    if (exists(path.join(srvRoot, domain)) && !exists(plan.private_file)) plan.action = 'genkey';
    else if (exists(plan.private_file)) plan.action = 'copy';
    else plan.action = 'none';
    return plan;
}

module.exports = { key_plan };
