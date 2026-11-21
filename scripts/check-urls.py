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
PUNCT = "?!.,:;*_~'\"`"  # trailing punctuation a bare autolink drops
DOT_SEGMENT = re.compile(r"(^|/)\.\.?(/|[?#]|$)")


def decode(s):
    while (d := unquote(s)) != s:
        s = d
    return s.replace("\\", "/")


def extent(t, i):
    """The URL starting at t[i], ended by what opened it, and for a Markdown
    link destination the text glued after its closing )."""
    before, rest = t[:i], t[i:]
    if before.endswith(('="', "='")):  # an HTML attribute ends at its quote; markup follows
        return rest.split(before[-1], 1)[0], ""
    bare = re.split(r"[\s<]", rest, maxsplit=1)[0]  # a GFM bare autolink runs to whitespace or <
    if before.endswith("<"):
        return bare.split(">", 1)[0], ""
    if before.endswith("]("):  # ends at the matching )
        depth = 1
        for j, c in enumerate(bare):
            depth += {"(": 1, ")": -1}.get(c, 0)
            if not depth:
                return bare[:j], re.split(r"\[", bare[j + 1:], maxsplit=1)[0]
    while True:  # a bare autolink drops trailing punctuation, then an unbalanced )
        s = bare.rstrip(PUNCT)
        if s.endswith(")") and s.count(")") > s.count("("):
            s = s[:-1]
        if s == bare:
            return bare, ""
        bare = s


def check(url, glued, n, secret):
    """Returns the failure for one URL (scheme:// or // and what follows), or None."""
    try:
        # Split before decoding: github.com%2F~@host is userinfo on host, not a path
        u = urlsplit("//" + re.sub(r"^([a-z][a-z0-9+.-]*:)?/+", "", url, flags=re.I))
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
    # The path may name a record; the query can carry one too (?url=/admin/...),
    # a .. can climb out of the spec, and text glued after a Markdown link's )
    # can carry a record path as well
    glued = decode(glued).rstrip(PUNCT)
    if host in PROD and (decode(u.path) not in PROD_PATHS or re.search("[/:]", decode(u.query + u.fragment))
                         or DOT_SEGMENT.search(decode(url)) or (glued != "#" and re.search("[/?#]", glued))):
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
            found = []
            for i, t in enumerate(layers):
                urls = list(URL.finditer(t))
                found += [(t, m.start(), "") for m in urls]
                # A name right after a URL's // is that URL's host, checked with it. One
                # right after a % is an escape's tail (%7Binstance%7D) until the last
                # layer, where any % left is literal
                hosts = {m.end() for m in urls}
                found += [(t, m.start(), "//") for m in NAME.finditer(t) if m.start() not in hosts
                          and (i == len(layers) - 1 or t[m.start() - 1:m.start()] != "%")]
            for t, start, prefix in found:
                url, glued = extent(t, start)
                failure = check(prefix + url, glued, n, secret)
                if failure:
                    failures[failure] = None
    for failure in failures:
        print(failure)


main(sys.argv[1])
