/*
   haproxy/siteredirect.js — send a whole site to one URL (sc set-ve-redirect).

   Container keys, set by commands/set-ve-redirect.sh:
     redirect       the target URL; every request for the VE and www.VE, http and
                    https, goes to exactly this URL ('redirect location', the path
                    is not appended: a Facebook page has no /tech-rider/...)
     redirect_code  302 for a temporary redirect; absent means 301

   Unlike http-redirect/https-redirect ('redirect prefix', always 301, path
   appended), which stay as they are for host moves. /.well-known is exempt,
   so certificate renewal keeps working.

   Used by haproxy.js at the head of both frontends' redirect rules, so these
   win over the www. and http->https redirects of the same names.
   CommonJS because haproxy.js requires it synchronously.
*/

// Characters haproxy takes inside one unquoted word: no space, no quote, and
// no '#', which starts a comment in haproxy.cfg.
const URL_RE = /^https?:\/\/[A-Za-z0-9.-]+(:[0-9]+)?(\/[A-Za-z0-9._~:/?@!$&()*+,;=%\[\]-]*)?$/;
const CODES = [301, 302];

function valid_redirect(url) {
    return typeof url === "string" && URL_RE.test(url);
}

// site_redirect(c, container, exceptions): the rules for one frontend, "" when unset.
// A hand-edited bad value throws: rendering stops and haproxy keeps its previous config.
function site_redirect(c, container, exceptions) {
    const url = container.redirect;
    if (url === undefined) return "";
    if (!valid_redirect(url)) throw new Error("container " + c + ": invalid redirect " + JSON.stringify(url));
    const code = container.redirect_code === undefined ? 301 : Number(container.redirect_code);
    if (!CODES.includes(code)) throw new Error("container " + c + ": invalid redirect_code " + JSON.stringify(container.redirect_code));
    let str = "";
    for (const host of [c, "www." + c]) str += "\n    redirect location " + url + " code " + code + " if { hdr(host) -i " + host + " }" + exceptions;
    return str;
}

module.exports = { site_redirect, valid_redirect };

// node siteredirect.js valid URL: exit 0 when set-ve-redirect may store it
if (require.main === module) process.exit(valid_redirect(process.argv[2]) ? 0 : 1);
