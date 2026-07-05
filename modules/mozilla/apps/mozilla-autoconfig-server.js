/*
    mozilla/apps/mozilla-autoconfig-server.js — Thunderbird mail autoconfig.

    Run as the mozilla-autoconfig.service systemd unit (written by
    libs/install.sh). Builds one static clientConfig XML at startup with
    this host's hostname baked in, and serves it with 200 text/xml to
    every request on port 1029. The haproxy module routes
    /.well-known/autoconfig/mail/ on every hosted domain to
    127.0.0.1:1029, so Thunderbird's account auto-setup fetches
    http://<domain>/.well-known/autoconfig/mail/config-v1.1.xml and
    configures IMAP 993 / POP3 995 / SMTP 465 (all SSL) against this
    host's mail stack (perdition + postfix).

    The %EMAILDOMAIN% and %EMAILADDRESS% tokens are placeholders
    substituted client-side by Thunderbird — they must stay literal.

    FIXME(v4): smell — os.hostname() is captured once at startup; a
    hostname change keeps serving the stale name until restart, and a
    non-FQDN hostname yields client-unresolvable server names.
*/

// Load modules to create a http server.
var http = require("http");
var os = require('os');

// Configure our HTTP server to respond with a file-read to all requests on the mozilla autoconfig URL
// http://example.com/.well-known/autoconfig/mail/config-v1.1.xml

var xml = '';
xml += '<clientConfig version="1.1">';
// FIXME(v4): low — provider id is hardcoded to D250.hu on every
// deployment; should come from the branding module.
xml += '<emailProvider id="D250.hu">';

xml += '<domain>%EMAILDOMAIN%</domain>';
xml += '<displayName>%EMAILADDRESS% at ' + os.hostname() + '</displayName>';
xml += '<displayShortName>%EMAILADDRESS%</displayShortName>';
xml += '<incomingServer type="imap">';
xml += '<hostname>' + os.hostname() + '</hostname>';
xml += '<port>993</port>';
xml += '<socketType>SSL</socketType>';
xml += '<authentication>password-cleartext</authentication>';
xml += '<username>%EMAILADDRESS%</username>';
xml += '</incomingServer>';

xml += '<incomingServer type="pop3">';
xml += '<hostname>' + os.hostname() + '</hostname>';
xml += '<port>995</port>';
xml += '<socketType>SSL</socketType>';
xml += '<authentication>password-cleartext</authentication>';
xml += '<username>%EMAILADDRESS%</username>';
xml += '</incomingServer>';

xml += '<outgoingServer type="smtp">';
xml += '<hostname>' + os.hostname() + '</hostname>';
xml += '<port>465</port>';
xml += '<socketType>SSL</socketType>';
xml += '<authentication>password-cleartext</authentication>';
xml += '<username>%EMAILADDRESS%</username>';
xml += '</outgoingServer>';

xml += '</emailProvider>';
xml += '</clientConfig>';

// FIXME(v4): low — every method and path gets 200 + the full config XML;
// should serve only /mail/config-v1.1.xml and 404 otherwise.
var http_server = http.createServer(function(req, res) {
    res.writeHead(200, {
        "Content-Type": "text/xml"
    });

    res.end(xml);
    console.log("Request.");

});

// FIXME(v4): medium — no bind address, so this root-owned process listens
// on all interfaces although haproxy consumes it via 127.0.0.1 only;
// should bind 127.0.0.1 (see the matching note in libs/install.sh).
http_server.listen(1029);
console.log('Started mozilla-autoconfig-server.js for ' + os.hostname());
