/*
 * srvctl letsencrypt module — pkilib.js
 *
 * Lives in the module root, not libs/: commonlib.sh sources every file under
 * every module's libs directory as a bash library, and this file is Node.
 *
 * Container /etc/pki/tls writes for letsencrypt_deploy and the legacy sweep
 * that letsencrypt.js runs over every container rootfs. Kept free of
 * datastore and environment access so modules/letsencrypt/selftest/
 * pki.test.sh can drive it against a fixture root.
 *
 * Key material reaching a container lives only in private/localhost.key
 * (0600); certs/localhost.crt, certs/<domain>.pem and certs/localhost.pem
 * carry the fullchain only. Earlier versions wrote the key+fullchain bundle
 * into both certs/*.pem files with no mode; the sweep strips the key from
 * them and narrows a wide localhost.key.
 *
 * Everything below <srv>/<C>/rootfs is controlled by the container root, so
 * nothing here resolves a path through it. Each directory (etc, pki, tls,
 * private, certs) is opened by fd from its parent's fd with O_NOFOLLOW, and
 * files are reached as /proc/self/fd/<dir fd>/<name> — Node has no openat;
 * that is its equivalent. A directory renamed or replaced by a symlink after
 * it was opened therefore cannot redirect a read, write, chown or chmod
 * outside the rootfs; the swap is still reported. Files: lstat rejects a
 * non-regular target before it is opened, O_NOFOLLOW|O_NONBLOCK keeps a
 * symlink or FIFO swapped in afterwards from being followed or blocking, and
 * fstat must still see the same regular file before any I/O, all through
 * the fd.
 */

const fs = require("fs");
const path = require("path");

const C = fs.constants;
const NB = C.O_NOFOLLOW | C.O_NONBLOCK | C.O_NOCTTY;
const DIR = C.O_RDONLY | C.O_DIRECTORY | NB;
const KEY = /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]+?-----END [A-Z ]*PRIVATE KEY-----\n?/g;

function failure(code, file) {
    var error = new Error(code + ": " + file);
    error.code = code;
    return error;
}

// name inside the directory open at dirFd, never resolved through a path
function at(dirFd, name) {
    return "/proc/self/fd/" + dirFd + "/" + name;
}

// fd of the regular file at file, opened with flags; throws ENOENT when it
// does not exist and ENOTREG / ELOOP / ENXIO for anything else.
function openRegular(file, flags) {
    var st = fs.lstatSync(file);
    if (!st.isFile()) throw failure("ENOTREG", file);
    var fd = fs.openSync(file, flags | NB);
    var now = fs.fstatSync(fd);
    if (!now.isFile() || now.dev !== st.dev || now.ino !== st.ino) {
        fs.closeSync(fd);
        throw failure("ENOTREG", file);
    }
    return fd;
}

// Write data to file in place (inode and owner kept) and end at mode, set by
// an explicit fchmod before the data goes in — a creation mode alone would
// not narrow an existing file. owner: optional { uid, gid }.
function writeFile(file, data, mode, owner) {
    var fd;
    try {
        fd = openRegular(file, C.O_WRONLY);
    } catch (error) {
        if (error.code !== "ENOENT") throw error;
        fd = fs.openSync(file, C.O_WRONLY | C.O_CREAT | C.O_EXCL | NB, mode);
        if (!fs.fstatSync(fd).isFile()) {
            fs.closeSync(fd);
            throw failure("ENOTREG", file);
        }
    }
    try {
        if (owner) fs.fchownSync(fd, owner.uid, owner.gid);
        fs.fchmodSync(fd, mode);
        fs.ftruncateSync(fd, 0);
        fs.writeSync(fd, data, 0);
    } finally {
        fs.closeSync(fd);
    }
}

// Open <srvRoot>/<name>/rootfs/etc/pki/tls/{private,certs} component by
// component. Returns null when the container has no such tree (ENOENT),
// throws ELOOP/ENOTDIR when a component is a symlink or not a directory.
// The caller must close() the result.
function openPki(srvRoot, name) {
    if (!name || name.indexOf("/") >= 0 || name === "." || name === "..") return null;
    var fds = [];
    function step(parent, comp) {
        var fd = fs.openSync(parent === null ? comp : at(parent, comp), DIR);
        fds.push(fd);
        return fd;
    }
    var fd;
    try {
        // host side: anything that is not a <srv>/<C>/rootfs directory is not a container
        fd = step(null, path.join(srvRoot, name, "rootfs"));
    } catch (error) {
        return null;
    }
    try {
        ["etc", "pki", "tls"].forEach(function (comp) {
            fd = step(fd, comp);
        });
        var tls = path.join(srvRoot, name, "rootfs/etc/pki/tls");
        var pki = { path: tls, private: step(fd, "private"), certs: step(fd, "certs") };
        pki.close = function () {
            fds.forEach(function (f) {
                fs.closeSync(f);
            });
        };
        return pki;
    } catch (error) {
        fds.forEach(function (f) {
            fs.closeSync(f);
        });
        if (error.code === "ENOENT") return null;
        error.file = path.join(srvRoot, name, "rootfs/etc/pki/tls");
        throw error;
    }
}

// Throws EMOVED when <pki.path>/<dir> no longer names the directory open in
// pki[dir]: it was renamed or replaced after openPki (nothing was done
// outside the rootfs, but the caller should know).
function checkBound(pki, dir) {
    var file = path.join(pki.path, dir);
    var now = fs.fstatSync(pki[dir]);
    var st;
    try {
        st = fs.lstatSync(file);
    } catch (error) {
        throw failure("EMOVED", file);
    }
    if (!st.isDirectory() || st.dev !== now.dev || st.ino !== now.ino) throw failure("EMOVED", file);
}

// The container root's shifted uid/gid, taken from the open directory; none
// when it is owned by host root (no uid shift).
function dirOwner(dirFd) {
    var st = fs.fstatSync(dirFd);
    return st.uid !== 0 ? { uid: st.uid, gid: st.gid } : null;
}

// Deploy privkey/fullchain into /srv/<domain>/rootfs/etc/pki/tls. Never
// throws: per-file failures are returned. The key goes first; if it cannot
// be written no certs file is touched, so the container keeps a matching
// key/certificate pair.
function deployContainer(srvRoot, domain, privkey, fullchain) {
    var result = { deployed: false, errors: [] };
    function fail(file, error) {
        result.errors.push({ file: error.file || file, error: error.code || error.message });
    }
    var pki;
    try {
        pki = openPki(srvRoot, domain);
    } catch (error) {
        fail(path.join(srvRoot, domain), error);
        return result;
    }
    if (!pki) return result;

    try {
        var key = path.join(pki.path, "private/localhost.key");
        try {
            writeFile(at(pki.private, "localhost.key"), privkey, 0o600, dirOwner(pki.private));
            checkBound(pki, "private");
        } catch (error) {
            fail(key, error);
            return result;
        }

        var owner = dirOwner(pki.certs);
        ["localhost.crt", domain + ".pem", "localhost.pem"].forEach(function (name) {
            try {
                writeFile(at(pki.certs, name), fullchain, 0o644, owner);
            } catch (error) {
                fail(path.join(pki.path, "certs", name), error);
            }
        });
        try {
            checkBound(pki, "certs");
        } catch (error) {
            fail(null, error);
        }
        result.deployed = result.errors.length === 0;
        return result;
    } finally {
        pki.close();
    }
}

// Strip private keys from certs/<name>.pem and certs/localhost.pem — only
// those two: postfix.pem, sendmail.pem etc. are legitimate — and narrow a
// wide private/localhost.key to 0600. Writes nothing on a clean container.
function cleanContainer(pki, name) {
    var changes = [];
    function each(dir, file, fn) {
        var shown = path.join(pki.path, dir, file);
        try {
            var action = fn(at(pki[dir], file));
            if (action) changes.push({ file: shown, action: action });
        } catch (error) {
            if (error.code !== "ENOENT") changes.push({ file: shown, action: "error", error: error.code || error.message });
        }
    }

    Array.from(new Set([name + ".pem", "localhost.pem"])).forEach(function (cert) {
        each("certs", cert, function (file) {
            var fd = openRegular(file, C.O_RDWR);
            try {
                var text = fs.readFileSync(fd, "utf8");
                KEY.lastIndex = 0;
                if (!KEY.test(text)) return null;
                fs.ftruncateSync(fd, 0);
                fs.writeSync(fd, text.replace(KEY, ""), 0);
                return "stripped";
            } finally {
                fs.closeSync(fd);
            }
        });
    });

    each("private", "localhost.key", function (file) {
        var fd = openRegular(file, C.O_RDONLY);
        try {
            var st = fs.fstatSync(fd);
            if ((st.mode & 0o777) === 0o600) return null;
            var dir = fs.fstatSync(pki.private);
            if (dir.uid !== 0 && st.uid === 0) fs.fchownSync(fd, dir.uid, dir.gid);
            fs.fchmodSync(fd, 0o600);
            return "narrowed";
        } finally {
            fs.closeSync(fd);
        }
    });

    ["certs", "private"].forEach(function (dir) {
        try {
            checkBound(pki, dir);
        } catch (error) {
            changes.push({ file: path.join(pki.path, dir), action: "error", error: error.code });
        }
    });
    return changes;
}

// cleanContainer over every <srvRoot>/<C> with a pki tree — whether or not
// the container is in the datastore or reaches letsencrypt_deploy. Never
// throws; returns [{ file, action: stripped|narrowed|error, error? }].
function sweepContainers(srvRoot) {
    var names;
    try {
        names = fs.readdirSync(srvRoot);
    } catch (error) {
        return [{ file: srvRoot, action: "error", error: error.code || error.message }];
    }
    var changes = [];
    names.forEach(function (name) {
        var pki = null;
        try {
            pki = openPki(srvRoot, name);
            if (pki) changes = changes.concat(cleanContainer(pki, name));
        } catch (error) {
            changes.push({ file: error.file || path.join(srvRoot, name), action: "error", error: error.code || error.message });
        } finally {
            if (pki) pki.close();
        }
    });
    return changes;
}

module.exports = { writeFile, deployContainer, sweepContainers };
