#!/usr/bin/env python3
"""Rule 3 of check-spec.sh for one file: every URL, whatever its scheme, and
every darthealth.com name written without one is on the allowlist, carries no
credentials, and on a production host links only the root or the spec.

Each URL is normalized the way a browser reads it (percent-decoded, \\ as /,
lowercase host, numeric port dropped) before it is checked. Prints one failure
message per line and nothing when the file passes. Never prints userinfo, a
production path, or a host from a line that carries userinfo.
Usage: check-urls.py FILE
"""
import re
import sys
from urllib.parse import unquote, urlsplit

ALLOWED = {
    "darthealth.com", "www.darthealth.com", "datanexus.darthealth.com", "trust.darthealth.com",
    "{instance}.darthealth.com", "github.com", "raw.githubusercontent.com", "rubygems.org",
    "example.com", "example.org", "example.net",
}
RESERVED = (".test", ".example", ".invalid")
# A client's production instance: only its root or its spec, never /swaggerui,
# whose Try it out sends a reader's key and requests to that client
PROD = {"datanexus.darthealth.com", "{instance}.darthealth.com"}
PROD_PATHS = {"", "/", "/api/openapi", "/api/openapi/"}

# A URL starts at scheme:// or at a protocol-relative //host.with.a.dot
URL = re.compile(r"[a-z][a-z0-9+.-]*:/{2,}|(?<![a-z0-9+./:-])/{2,}(?=[^/?#\s]*\.[\w%{}-])", re.I)
# A darthealth.com subdomain, as a whole hostname: .com.au is another domain
NAME = re.compile(r"(?<![a-z0-9{}-])(?:[a-z0-9{}-]+\.)+darthealth\.com(?![a-z0-9-]|\.[a-z0-9-])", re.I)
USERINFO = re.compile(r"(^|[^/A-Za-z0-9._~%+-])[A-Za-z0-9._~%+-]+:[^/?#@\s]*@")
# Anything userinfo-shaped; a line with it has no host printed, as a host may be a password
SECRET = re.compile(r"(:|//)\S*@")
DELIMS = re.compile(r"[)\]\"'`>]")  # ends a Markdown or HTML link
TRAILING = ".,;:!?*_~)]\"'`>"  # sentence punctuation and link closers
DOT_SEGMENT = re.compile(r"(^|/)\.\.?(/|[?#]|$)")


def decode(s):
    while (d := unquote(s)) != s:
        s = d
    return s.replace("\\", "/")


def check(span, n, secret):
    """Returns the failure for one URL (scheme:// or // and what follows), or None."""
    # A Markdown or HTML delimiter ends the link; a browser autolinks to whitespace
    narrow = decode(DELIMS.split(span, 1)[0]).rstrip(TRAILING)
    wide = decode(span).rstrip(TRAILING)
    try:
        u = urlsplit("//" + re.sub(r"^([a-z][a-z0-9+.-]*:)?/+", "", narrow, flags=re.I))
        host = u.hostname or ""
    except ValueError:
        return f"a URL's host can't be parsed at line {n} (not printed)"
    if "@" in u.netloc:
        return f"a URL carries credentials at line {n} (not printed)"
    if not re.fullmatch(r"[^:]*(:[0-9]*)?", u.netloc):
        return f"a URL's port isn't a number at line {n} (not printed)"
    if host not in ALLOWED and not host.endswith(RESERVED):
        if secret or not re.fullmatch(r"[a-z0-9.-]+", host):
            return f"URL host not allowed at line {n} (not printed)"
        return f"URL host not allowed: {host}"
    # The path may name a record; the query can carry one too (?url=/admin/...),
    # and a .. anywhere a browser autolinks could climb out of the spec
    if host in PROD and (u.path not in PROD_PATHS or re.search("[/:]", u.query + u.fragment)
                         or DOT_SEGMENT.search(wide)):
        return f"path not allowed on {host} at line {n} (not printed)"
    return None


def main(path):
    failures = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            line = re.sub("mailto:", "", line, flags=re.I)  # names an address, not userinfo
            raw, decoded = line.replace("\\", "/"), decode(line)
            secret = bool(SECRET.search(raw) or SECRET.search(decoded))
            if USERINFO.search(raw) or USERINFO.search(decoded):
                failures[f"userinfo without a scheme at line {n} (not printed)"] = None
            # Decoded, a URL nested in another's query is a URL of its own
            spans = [t[m.start():] for t in (raw, decoded) for m in URL.finditer(t)]
            spans += ["//" + decoded[m.start():] for m in NAME.finditer(decoded)]
            for span in spans:
                failure = check(re.split(r"[\s<]", span, maxsplit=1)[0], n, secret)
                if failure:
                    failures[failure] = None
    for failure in failures:
        print(failure)


main(sys.argv[1])
