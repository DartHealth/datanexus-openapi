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
WS = " \t\n\v\f\r"  # cmark-gfm's whitespace; Python's \s also takes NBSP, U+3000 and \x1f
ATTR = "[A-Za-z_:][A-Za-z0-9_.:-]*"
# A CommonMark open tag up to an attribute's opening quote. A quoted value holds no
# ` < or >, so a code span, comment or \< (/< by now) can't have swallowed the <
TAG = re.compile(rf"""(?<!/)<[A-Za-z][A-Za-z0-9-]*(?:[{WS}]+{ATTR}(?:[{WS}]*=[{WS}]*(?:[^{WS}"'=<>`]+|'[^'`<>]*'|"[^"`<>]*"))?)*[{WS}]+{ATTR}[{WS}]*=[{WS}]*\Z""")


def decode(s):
    while (d := unquote(s)) != s:
        s = d
    return s.replace("\\", "/")


def split(url):
    """The URL's parts and its decoded, lowercased host. The authority is split
    off before decoding: github.com%2F~@host is userinfo on host, not a path."""
    u = urlsplit("//" + re.sub(r"^([a-z][a-z0-9+.-]*:)?/+", "", url, flags=re.I))
    return u, decode(u.hostname or "").lower()


def trim(bare):
    """A bare autolink drops trailing punctuation, then an unbalanced ) or ]."""
    while True:
        s = bare.rstrip(PUNCT)
        for close, open_ in ((")", "("), ("]", "[")):
            if s.endswith(close) and s.count(close) > s.count(open_):
                s = s[:-1]
        if s == bare:
            return bare
        bare = s


def extent(t, i):
    """The URL starting at t[i], ended by what opened it, and for a Markdown
    link destination or an HTML attribute the text glued after its end."""
    before, rest = t[:i], t[i:]
    if before.endswith(('="', "='")):  # an HTML attribute ends at its quote; markup follows
        url, _, after = rest.partition(before[-1])
        glued = re.split(f"[{WS}<]", after, maxsplit=1)[0]
        # GFM autolinks on through the quote and > unless a real open tag closes there
        return url, "" if re.match("/?>", glued) and TAG.search(before[:-1]) else glued
    bare = re.split(f"[{WS}<]", rest, maxsplit=1)[0]  # a GFM bare autolink runs to whitespace or <
    if before.endswith("<"):
        return bare.split(">", 1)[0], ""
    if before.endswith("]("):  # ends at the matching )
        depth = 1
        for j, c in enumerate(bare):
            depth += {"(": 1, ")": -1}.get(c, 0)
            if not depth:
                return bare[:j], bare[j + 1:]  # glued text runs on: a [ there may open no link
    if before.count("[") > before.count("]") and "](" in bare:  # link text ends at its ](
        cut = bare.split("](", 1)[0]
        # GFM autolinks past a [ that opens no link text, and no check of the [
        # has held, so a production URL never ends here: its path runs on and fails
        try:
            prod = split(cut)[1] in PROD
        except ValueError:
            prod = True
        if not prod:
            bare = cut
    return trim(bare), ""


def check(url, glued, n, secret):
    """Returns the failure for one URL (scheme:// or // and what follows), or None."""
    try:
        u, host = split(url)
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
    # or an attribute's quote can carry a record path as well
    glued = trim(decode(glued))
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
                found += [(t, m.start(), "", None) for m in urls]
                # A name right after a URL's // is that URL's host, checked with it. One
                # right after a % is an escape's tail (%7Binstance%7D) until the last
                # layer, where any % left is literal
                hosts = {m.end() for m in urls}
                found += [(t, m.start(), "//", m.end()) for m in NAME.finditer(t) if m.start() not in hosts
                          and (i == len(layers) - 1 or t[m.start() - 1:m.start()] != "%")]
            for t, start, prefix, end in found:
                # GFM never autolinks a schemeless name, so it ends with its hostname
                # unless what follows could carry a path, port or userinfo (\ is / by now)
                if end and not re.match(r"[/?#:@%]", t[end:]):
                    url, glued = t[start:end], ""
                else:
                    url, glued = extent(t, start)
                failure = check(prefix + url, glued, n, secret)
                if failure:
                    failures[failure] = None
    for failure in failures:
        print(failure)


main(sys.argv[1])
