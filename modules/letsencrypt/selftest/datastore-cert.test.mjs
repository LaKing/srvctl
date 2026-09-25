// Run: node modules/letsencrypt/selftest/datastore-cert.test.mjs
// Exercise the deployed-certificate gate with real OpenSSL certificates,
// without loading the issuance engine or touching the live datastore.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { execFileSync, execSync } from 'node:child_process';

const require = createRequire(import.meta.url);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'srvctl-cert-'));
const source = fs.readFileSync(new URL('../letsencrypt.js', import.meta.url), 'utf8');
const gate = source.slice(source.indexOf('function check_checkend('), source.indexOf('// Bundle privkey + fullchain'));
const context = vm.createContext({
    fs, require, execSync, SC_CONTAINERS_CERT_DIR: dir,
    bundlelib: require('../bundlelib.js'), ntc() {}, console: { log() {} },
});
vm.runInContext(gate, context);
const check = context.check_datastore_cert;
const ssl = (...args) => execFileSync('openssl', args, { cwd: dir, stdio: 'ignore' });
const read = file => fs.readFileSync(path.join(dir, file), 'utf8');
const write = (file, text) => fs.writeFileSync(path.join(dir, file), text);
try {
    ssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'root.key', '-out', 'root.crt', '-days', '3650', '-subj', '/CN=placeholder.test/emailAddress=webmaster@placeholder.test');
    write('placeholder.pem', read('root.key') + read('root.crt'));
    assert.equal(check('placeholder'), false, 'ten-year webmaster placeholder needs issuance');
    write('legacy.pem', '\u001b[32mcat placeholder\u001b[0m\n' + read('placeholder.pem'));
    assert.equal(check('legacy'), false, 'legacy command echo does not hide placeholder');
    ssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'plain.key', '-out', 'plain.pem', '-days', '3650', '-subj', '/CN=plain.test');
    assert.equal(check('plain'), false, 'self-issued certificate without email needs issuance');
    ssl('req', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'leaf.key', '-out', 'leaf.csr', '-subj', '/CN=leaf.test/emailAddress=webmaster@leaf.test');
    for (const [name, days, expected] of [['valid', '30', true], ['renew', '1', false]]) {
        ssl('x509', '-req', '-in', 'leaf.csr', '-CA', 'root.crt', '-CAkey', 'root.key', '-set_serial', '2', '-out', 'leaf.crt', '-days', days);
        write(name + '.pem', read('leaf.key') + read('leaf.crt') + read('root.crt'));
        assert.equal(check(name), expected, name + ': evaluate leaf issuer and renewal window');
    }
    write('broken.pem', '\u001b[32mgarbage\n');
    assert.equal(check('broken'), false, 'malformed certificate needs issuance');
    assert.equal(check('missing'), false, 'missing certificate needs issuance');
    console.log('datastore-cert: 7 checks passed');
} finally {
    fs.rmSync(dir, { recursive: true, force: true });
}
