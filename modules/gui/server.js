#!/usr/bin/env node

//'use strict';

/*jshint esnext: true */

const global_install_prefix = '/usr/lib/node_modules/';
const port = 250;

//const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;
// okay, this is not visible here .. TODO, make it so, ...
const SC_DATASTORE_DIR = '/var/srvctl3/datastore/rw';
const SC_INSTALL_DIR = '/usr/local/share/srvctl';

const https = require('https');
const os = require('os');
const fs = require('fs');
const exec = require('child_process').exec;

const express = require(global_install_prefix + 'express');
const pty = require(global_install_prefix + 'pty.js');

// NOTE https://github.com/mscdex/ssh2/issues/433

// todo, dont burn by CDN in here
const HOSTNAME = os.hostname();

const options = {
    cert: fs.readFileSync('/etc/srvctl/cert/' + HOSTNAME + '/' + HOSTNAME + '.pem'),
    key: fs.readFileSync('/etc/srvctl/cert/' + HOSTNAME + '/' + HOSTNAME + '.key'),
    ca: [fs.readFileSync('/etc/srvctl/CA/ca/usernet.crt.pem')],
    requestCert: true,
    rejectUnauthorized: true,
};

const app = express();

const server = https.createServer(options, app);

/// to prevent the segfault bug, I addeded { wsEngine: 'ws' }
const io = require(global_install_prefix + 'socket.io')(server, {
    wsEngine: 'ws'
});
const Client = require(global_install_prefix + 'ssh2').Client;

app.use(express.static(__dirname + '/srvctl-gui'));
app.use('/angular', express.static(global_install_prefix + 'angular'));
app.use('/bootstrap', express.static(global_install_prefix + 'bootstrap/dist'));
app.use('/angular-ui-bootstrap', express.static(global_install_prefix + 'angular-ui-bootstrap/dist'));
app.use('/angular-sanitize', express.static(global_install_prefix + 'angular-sanitize'));
app.use('/wetty', express.static(global_install_prefix + 'wetty/public/wetty'));

app.get('/ssh/:user', function(req, res) {
    res.sendFile(__dirname + '/srvctl-gui/wetty.html');
});



const containers = JSON.parse(fs.readFileSync(SC_DATASTORE_DIR + '/containers.json'));
const users = JSON.parse(fs.readFileSync(SC_DATASTORE_DIR + '/users.json'));
const hosts = JSON.parse(fs.readFileSync(SC_DATASTORE_DIR + '/hosts.json'));


function process_commands_spec() {
    var commands_spec = fs.readFileSync('/var/local/srvctl/commands.spec', 'UTF8');
    var r = {};
    
    // spec lines array
    var sla = commands_spec.split('\n');
    var l = '';
    var la;
    var cat;
    var o = {};
    for (i = 0; i < sla.length; i++) { 
        l = sla[i];
        if (l.length > 0) {
            la = l.split('×');
            o = {};
            
            if (la[0].substring(0,SC_INSTALL_DIR.length) === SC_INSTALL_DIR) cat = la[0].substring(SC_INSTALL_DIR.length+1).split('/')[1];
            else cat = la[0].split('/')[2];
            
            o.hint = la[2];
            if (la[3].split(' ').length > 0) o.args = la[3].split(' ');
            if (r[cat] === undefined) r[cat] = {};
            r[cat][la[1]] = o;
        }
    }
    return r;
}

const spec = process_commands_spec();
console.log(spec);

function send_main(socket) {

    var main = {};

    main.containers = {};
    main.hosts = hosts;
    main.users = users;
    main.spec = spec;
    main.services = {};
    
    main.user = socket.user;
    main.host = socket.host;
    
    Object.keys(containers).forEach(function(i) {
        if (socket.user === containers[i].user) main.containers[i] = containers[i];
    });
    
    

    socket.emit('main', main);
    console.log("send_main");

}

function run_command(socket, cmd) {
    send_main(socket);
    socket.emit('lock', true);
    
    var user = socket.user;
    var host = cmd.host;
    var command = cmd.command;
    //socket.host = command.host;
    if (cmd.host === 'localhost') host = HOSTNAME;
    if (cmd.selected === 'container') {
        host = cmd.container;
        user = "root";
    }
    
    console.log("run_command", host, user, command);

    var conn = new Client();
    conn.on('ready', function() {
        var adat = '[' + user + '@' + host + ']$ ' + command + '\n';
        console.log('command:', adat);
        conn.exec(command + ' 2>&1', function(err, stream) {
            if (err) throw err;
            stream.on('close', function(code, signal) {
                conn.end();
                //socket.emit('lock', false);
            }).on('data', function(data) {
                adat += data;
                socket.emit('terminal', term2html(adat));
            }).stderr.on('data', function(data) {
                adat += data;
                socket.emit('terminal', term2html(adat));
            });
        });
    });
    conn.on('error', function(err) {
        //console.log(err);
        socket.emit('terminal', err.level + ' error.');
        socket.emit('lock', false);
    });
    conn.on('close', function(err) {
        //console.log('ssh2 connection closed');
        socket.emit('lock', false);
    });
    conn.connect({
        host: host,
        port: 22,
        username: user,
        privateKey: socket.key,
        readyTimeout: 500
    });


}

io.on('connection', function(socket) {
    //    console.log('a user connected (id=' + socket.id + ')');
    var cert = socket.client.request.client.getPeerCertificate();
    console.log(cert.subject.CN, 'connected');
    socket.user = cert.subject.CN;
    socket.host = HOSTNAME;
    
    var keyfile = SC_DATASTORE_DIR + "/users/" + socket.user + "/srvctl_id_rsa";
    fs.readFile(keyfile, 'utf8', function(err, data) {

        if (err) {
            console.log(err);
            return;
        }
        socket.key = data;

        if (socket.request.headers.referer.split('/')[3] === 'ssh') {

            var ssh_user = socket.request.headers.referer.split('/')[4];
            console.log('ssh', ssh_user);
            //'-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no',
            socket.term = pty.spawn('ssh', ['-p', 22, '-o', 'PreferredAuthentications=publickey', '-i', keyfile, ssh_user], {

                name: 'xterm-256color',
                cols: 80,
                rows: 30
            });

            socket.term.on('data', function(data) {
                socket.emit('output', data);
            });
            socket.term.on('exit', function(code) {
                console.log((new Date()) + " PID=" + socket.term.pid + " ENDED");
            });
            socket.on('resize', function(data) {
                if (!socket.term.readable || !socket.term.writable || socket.term.destroyed) return;
                socket.term.resize(data.col, data.row);
            });
            socket.on('input', function(data) {
                socket.term.write(data);
            });

        } else send_main(socket);
    });

    socket.on('get-main', function() {
        console.log('get-main (' + socket.user + ')');
        send_main(socket);
    });

    socket.on('command', function(command) {
        run_command(socket, command);
    });

    socket.on('disconnect', function() {
        console.info('Client gone (id=' + socket.id + ').');
    });



});


server.listen(port, function() {
    console.log('Listening on port ' + port);
    //process.setgid('node');
    //process.setuid('node');

    // TODO use it as srvctl-gui user
});

console.log("Srvctl-gui version 3.0");





function term2html(text) {
    // TODO add to theme
    var colors = ['#000', '#D00', '#00CF12', '#C2CB00', '#3100CA',
        '#E100C6', '#00CBCB', '#C7C7C7', '#686868', '#FF5959', '#00FF6B',
        '#FAFF5C', '#775AFF', '#FF47FE', '#0FF', '#FFF'
    ];

    // EL – Erase in Line: CSI n K.
    // Erases part of the line. If n is zero (or missing), clear from cursor to
    // the end of the line. If n is one, clear from cursor to beginning of the
    // line. If n is two, clear entire line. Cursor position does not change.
    text = text.replace(/^.*\u001B\[[12]K/mg, '');

    // CHA – Cursor Horizontal Absolute: CSI n G.
    // Moves the cursor to column n.
    text = text.replace(/^(.*)\u001B\[(\d+)G/mg, function(_, text, n) {
        return text.slice(0, n);
    });

    // SGR – Select Graphic Rendition: CSI n m.
    // Sets SGR parameters, including text color. After CSI can be zero or more
    // parameters separated with ;. With no parameters, CSI m is treated as
    // CSI 0 m (reset / normal), which is typical of most of the ANSI escape
    // sequences.
    var state = {
        bg: -1,
        fg: -1,
        bold: false,
        underline: false,
        negative: false
    };
    text = text.replace(/\u001B\[([\d;]+)m([^\u001B]+)/g, function(_, n, text) {
        // Update state according to SGR codes.
        n.split(';').forEach(function(code) {
            code = code | 0;
            if (code === 0) {
                state.bg = -1;
                state.fg = -1;
                state.bold = false;
                state.underline = false;
                state.negative = false;
            } else if (code === 1) {
                state.bold = true;
            } else if (code === 4) {
                state.underline = true;
            } else if (code === 7) {
                state.negative = true;
            } else if (code === 21) {
                state.bold = false;
            } else if (code === 24) {
                state.underline = false;
            } else if (code === 27) {
                state.negative = false;
            } else if (code >= 30 && code <= 37) {
                state.fg = code - 30;
            } else if (code === 39) {
                state.fg = -1;
            } else if (code >= 40 && code <= 47) {
                state.bg = code - 40;
            } else if (code === 49) {
                state.bg = -1;
            } else if (code >= 90 && code <= 97) {
                state.fg = code - 90 + 8;
            } else if (code >= 100 && code <= 107) {
                state.bg = code - 100 + 8;
            }
        });

        // Convert color codes to CSS colors.
        var bold = state.bold * 8;
        var fg, bg;
        if (state.negative) {
            fg = state.bg | bold;
            bg = state.fg;
        } else {
            fg = state.fg | bold;
            bg = state.bg;
        }
        fg = colors[fg] || '';
        bg = colors[bg] || '';

        // Create style element.
        var css = '';
        var style = '';
        if (bg) {
            style += 'background-color:' + bg + ';';
        }
        if (fg) {
            //style += 'color:' + fg + ';';
            css = "log_" + state.fg;
        }
        if (bold) {
            style += 'font-weight:bold;';
        }
        if (state.underline) {
            style += 'text-decoration:underline';
        }
        var html = text.
        replace(/&/g, '&amp;').
        replace(/</g, '&lt;').
        replace(/>/g, '&gt;');

        // Return HTML for this section of formatted text.
        if (style || css) {
            if (style) return '<span class="' + css + '" style="' + style + '">' + html + '</span>';
            else return '<span class="' + css + '">' + html + '</span>';
        } else {
            return html;
        }
    });

    return text.replace(/\u001B\[.*?[A-Za-z]/g, '');
}
