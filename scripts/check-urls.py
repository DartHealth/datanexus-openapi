#!/usr/bin/env python3
"""Rule 3 of check-spec.sh for one file: every URL, whatever its scheme, and
every darthealth.com name written without one is on the allowlist, carries no
credentials, and on a production host links only the root or the spec.

Each URL is read the way a browser reads it: \\ as /, the authority split off
before anything is percent-decoded, then the host and path decoded, the host
lowercased and a numeric port dropped. Prints one failure
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
    cut = DELIMS.split(span, 1)[0]
    narrow, after = cut.rstrip(TRAILING), decode(span[len(cut):])
    wide = decode(span).rstrip(TRAILING)
    try:
        # Split before decoding: github.com%2F~@host is userinfo on host, not a path
        u = urlsplit("//" + re.sub(r"^([a-z][a-z0-9+.-]*:)?/+", "", narrow, flags=re.I))
        host = decode(u.hostname or "").lower()
    except ValueError:
        return f"a URL's host can't be parsed at line {n} (not printed)"
    if "@" in u.netloc:
        return f"a URL carries credentials at line {n} (not printed)"
    if not re.fullmatch(r"[^:]*(:[0-9]*)?", u.netloc):
        return f"a URL's port isn't a number at line {n} (not printed)"
    if re.search(r"[/?#@:]", host):
        return f"a URL's host can't be parsed at line {n} (not printed)"
    if host not in ALLOWED and not host.endswith(RESERVED):
        if secret or not re.fullmatch(r"[a-z0-9.-]+", host):
            return f"URL host not allowed at line {n} (not printed)"
        return f"URL host not allowed: {host}"
    # The path may name a record; the query can carry one too (?url=/admin/...).
    # A browser autolinks past a mid-span ) or ', so a path, query or fragment
    # after one (up to the next link or URL), or a .. anywhere, reaches past the spec
    past = re.split(r"\[|" + URL.pattern, after, maxsplit=1, flags=re.I)[0]
    if host in PROD and (decode(u.path) not in PROD_PATHS or re.search("[/:]", decode(u.query + u.fragment))
                         or re.search("[/?#]", past) or DOT_SEGMENT.search(wide)):
        return f"path not allowed on {host} at line {n} (not printed)"
    return None


def main(path):
    failures = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            line = re.sub("mailto:", "", line, flags=re.I)  # names an address, not userinfo
            # Every decoding layer: a URL nested in another's query is a URL of its
            # own, read with only the encoding left on it at that layer
            layers = [line.replace("\\", "/")]
            while (d := unquote(layers[-1]).replace("\\", "/")) != layers[-1]:
                layers.append(d)
            secret = any(SECRET.search(t) for t in layers)
            if any(USERINFO.search(t) for t in layers):
                failures[f"userinfo without a scheme at line {n} (not printed)"] = None
            spans = [t[m.start():] for t in layers for m in URL.finditer(t)]
            # A name right after a % is an escape's tail (%7Binstance%7D) until the
            # last layer, where any % left is literal
            spans += ["//" + t[m.start():] for i, t in enumerate(layers) for m in NAME.finditer(t)
                      if i == len(layers) - 1 or t[m.start() - 1:m.start()] != "%"]
            for span in spans:
                failure = check(re.split(r"[\s<]", span, maxsplit=1)[0], n, secret)
                if failure:
                    failures[failure] = None
    for failure in failures:
        print(failure)


main(sys.argv[1])
