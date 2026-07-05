/* srvctl — modules/named/apps/dyndns-server.js
 *
 * DEAD CODE — the dormant dyndns subsystem. Never installed or started:
 * install_dyndns (libs/install.sh) returns before doing any work, and the
 * dormant systemd unit's ExecStart points at a wrong path (hs-apps/)
 * anyway. Kept only as a reference for a possible v4 rebuild.
 *
 * What it would do: HTTPS POST server on port 855 (cert/key paths from
 * argv); the request path names the dyndns host, the POSTed 'auth' value
 * is compared against /var/dyndns/<host>.auth, then the client IP is
 * written to /var/dyndns/<host>.ip and dyndns-update.sh runs nsupdate on
 * the local BIND.
 *
 * KNOWN SECURITY ISSUES — DO NOT REVIVE AS-IS:
 *   - shell command injection: the URL-derived host name is concatenated
 *     unquoted into the exec() command line below
 *   - path traversal: the same unvalidated name is concatenated into the
 *     /var/dyndns/<host>.auth and .ip file paths
 *   - non-constant-time, plaintext-file auth compare
 *   - hard-coded uid 103 in setuid; HMAC-MD5 TSIG key material
 * A v4 rebuild needs strict input validation, execFile with arguments,
 * tsig-keygen based keys and a named service user.
 */

console.log('Starting dyndns-server.js');

var https = require('https');
var fs = require('fs');
var querystring = require('querystring');
var exec = require('child_process').exec;
var upd;

function processPost(request, response, callback) {
    var queryData = "";
    if (typeof callback !== 'function') return null;

    if (request.method == 'POST') {
        request.on('data', function(data) {
            queryData += data;
            if (queryData.length > 1e6) {
                queryData = "";
                response.writeHead(413, {
                    'Content-Type': 'text/plain'
                }).end();
                request.connection.destroy();
            }
        });

        request.on('end', function() {
            request.post = querystring.parse(queryData);
            callback();
        });

    } else {
        response.writeHead(405, {
            'Content-Type': 'text/plain'
        });
        response.end();
    }
}

var options = {
    key: fs.readFileSync(process.argv[2]),
    cert: fs.readFileSync(process.argv[3])
};

console.log('Certificates loaded.');

https.createServer(options, function(request, response) {
    //response.writeHead(200);
    var ip = request.connection.remoteAddress;
    var dyndnshost = request.url.substring(1);

    console.log(dyndnshost + " update request from " + ip);

    if (request.url.length < 9 || request.method !== 'POST') {
        response.writeHead(200, "OK", {
            'Content-Type': 'text/plain'
        });
        response.end('Error!');
        console.log('invalid dyndns update request from ' + ip);
    } else {

        processPost(request, response, function() {
            console.log(request.post);
            // authorize

            fs.readFile("/var/dyndns/" + dyndnshost + '.auth', 'utf8', function(err, data) {
                if (err) {
                    response.end('Internal error.');
                    return console.log(err);
                } else {
                    if (request.post.auth == data) {
                        response.writeHead(200, "OK", {
                            'Content-Type': 'text/plain'
                        });
                        fs.writeFile("/var/dyndns/" + dyndnshost + '.ip', ip, function(err) {
                            if (err) {
                                response.end('Internal error.');
                                return console.log(err);
                            } else {


                                upd = exec("/bin/bash " + __dirname + "/dyndns-update.sh " + dyndnshost, function(error, stdout, stderr) {
                                    console.log('stdout: ' + stdout);
                                    console.log('stderr: ' + stderr);
                                    if (error !== null) {
                                        console.log('exec error: ' + error);
                                        response.end(error);
                                    } else {
                                        response.end(stdout + 'OK\n');
                                    }
                                });

                            }
                        });

                    } else {
                        response.writeHead(200, "OK", {
                            'Content-Type': 'text/plain'
                        });
                        response.end('Permission denied');
                    }
                }

            });


        });

    }
}).listen(855);

process.setuid(103);

console.log('Started dyndns-server.js under uid ' + process.getuid());