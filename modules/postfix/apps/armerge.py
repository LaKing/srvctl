#!/usr/bin/python3
"""srvctl Authentication-Results merger milter.

Runs only on the gateway's 127.0.0.1:10025 reinjection (amavis -> postfix),
started by srvctl-armerge.service (modules/postfix/libs/mailauthlib.sh).
On pass 1 pyspf-milter, opendkim and opendmarc wrote their results with the
private authserv-id --internal-id; every incoming Authentication-Results and
Received-SPF had already been dropped by header_checks. Here every
Authentication-Results and Received-SPF is deleted and ONE field

    Authentication-Results: <gateway>; spf=...; dkim=...; dmarc=...

is inserted at the top, built only from the private-id fields. Messages
without such fields (internal mail) get no gateway field.

Intermediate callbacks return CONTINUE (ACCEPT would end filtering before
eom); eom returns ACCEPT, also when something fails, so mail never stalls.
"""
import argparse
import re
import sys

AR = 'Authentication-Results'
RECEIVED_SPF = 'Received-SPF'
ORDER = {'spf': 0, 'dkim': 1, 'dmarc': 2}
FOLD = re.compile(r'\r?\n[ \t]+')


def split_ar(value):
    """(authserv-id, resinfo) of a field written by our own milters."""
    value = FOLD.sub(' ', value).strip()
    head, _, rest = value.partition(';')
    words = head.split()
    return (words[0].lower() if words else ''), rest.strip()


def plan(headers, gateway_id, internal_id):
    """headers: [(name, value)] in message order.
    Returns (deletes, merged): deletes are (name, 1-based occurrence) with the
    highest occurrence first per name; merged is the new field value or None."""
    seen = {AR.lower(): 0, RECEIVED_SPF.lower(): 0}
    deletes = {AR.lower(): [], RECEIVED_SPF.lower(): []}
    parts = []
    for name, value in headers:
        key = name.lower()
        if key not in seen:
            continue
        seen[key] += 1
        deletes[key].append((name, seen[key]))
        if key == AR.lower():
            ident, rest = split_ar(value)
            ## A bare 'none' means no method ran; dkim=none or dmarc=none is kept.
            if ident == internal_id.lower() and rest and rest.lower() != 'none':
                method = rest.split('=', 1)[0].strip().lower()
                parts.append((ORDER.get(method, len(ORDER)), len(parts), rest))
    ordered = [d for key in (AR.lower(), RECEIVED_SPF.lower()) for d in reversed(deletes[key])]
    merged = None
    if parts:
        merged = gateway_id + ';\n\t' + ';\n\t'.join(p[2] for p in sorted(parts))
    return ordered, merged


def make_class(Milter, gateway_id, internal_id, log):
    class ARMerge(Milter.Base):
        def __init__(self):
            super().__init__()
            self.headers = []

        def envfrom(self, *args):
            self.headers = []
            return Milter.CONTINUE

        def header(self, name, value):
            try:
                self.headers.append((name, value))
            except Exception as exc:
                log('header: %r' % exc)
            return Milter.CONTINUE

        def eom(self):
            try:
                deletes, merged = plan(self.headers, gateway_id, internal_id)
                for name, idx in deletes:
                    self.chgheader(name, idx, None)
                if merged:
                    self.addheader(AR, merged, 0)
            except Exception as exc:
                log('eom: %r' % exc)
            return Milter.ACCEPT

        def abort(self):
            self.headers = []
            return Milter.CONTINUE

    return ARMerge


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--socket', required=True)
    parser.add_argument('--authserv-id', required=True)
    parser.add_argument('--internal-id', required=True)
    args = parser.parse_args()

    import Milter

    def log(message):
        print('srvctl-armerge: ' + message, file=sys.stderr, flush=True)

    Milter.factory = make_class(Milter, args.authserv_id, args.internal_id, log)
    Milter.set_flags(Milter.ADDHDRS | Milter.CHGHDRS)
    log('listening on %s, authserv-id %s' % (args.socket, args.authserv_id))
    Milter.runmilter('srvctl-armerge', args.socket, 600)


if __name__ == '__main__':
    main()
