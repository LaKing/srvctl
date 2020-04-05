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
