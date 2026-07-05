/*
 *  modules/datastore/apps/datastore-server.js — the well-known http daemon.
 *
 *  Standalone node process run as root by datastore-server.service (unit
 *  written by libs/httpserverlib.sh). Listens on port 1030 (all
 *  interfaces); haproxy forwards two internet-reachable paths here:
 *    /.well-known/srvctl/datastore/containers.json — public snapshot of
 *        /var/srvctl3/datastore/containers.json
 *    /.well-known/pki-validation/<file> — ACME/CA validation files placed
 *        in /var/srvctl3/datastore/pki-validation/ by the haproxy module
 *  Any other request is answered 200 with an "INVALID URL" body.
 */

// Load modules to create a http server.
var http = require("http");
var fs = require("fs");

// Configure our HTTP server to respond with a file-read to all requests on the acme URL.
var http_server = http.createServer(function(req, res) {
    // srvctl internal
    if (req.url === "/.well-known/srvctl/datastore/containers.json") {
        res.writeHead(200, {
            "Content-Type": "application/json"
        });
        var ch = req.url.substring(28);
        var file = "/var/srvctl3/datastore/containers.json";

        fs.access(file, fs.R_OK, function(err) {
            if (!err) {
                fs.readFile(file, function(err, data) {
                    if (err) return res.end("INVALID DATA");
                    var content = data.toString();
                    console.log("CONTENT sent");
                    res.end(content);
                });
            } else {
                console.log("CANNOT READ: " + ch);
                res.end("CANNOT READ: " + ch);
            }
        });

        return;
    }

    // domain validation
    if (req.url.substring(0, 27) === "/.well-known/pki-validation") {
        // FIXME(v4): path traversal — req.url is appended unsanitized, so a
        // crafted /.well-known/pki-validation/../../<path> request can read
        // files outside the pki-validation directory (process runs as root
        // and the path is internet-reachable via haproxy).
        var hash_file = "/var/srvctl3/datastore/pki-validation/" + req.url.substring(28);
        fs.access(hash_file, fs.R_OK, function(err) {
            if (!err) {
                fs.readFile(hash_file, function(err, data) {
                    if (err) return res.end("INVALID DATA");
                    var content = data.toString();
                    console.log("CONTENT sent");
                    res.end(content);
                });
            } else {
                console.log("CANNOT READ file");
                res.end("CANNOT READ: " + hash_file);
            }
        });

        return;
    }

    // a default error
    res.writeHead(200, {
        "Content-Type": "application/json"
    });
    res.end("INVALID URL: " + req.url);
    console.log("INVALID URL: " + req.url);
});

http_server.listen(1030);
console.log("Started datastore-server.js");
