#!/usr/bin/env bash
# Checks the published content of this repo for leaks and for a spec that
# isn't the one we mean to publish. Scans exactly openapi.json, README.md and
# the files under docs/. Usage: scripts/check-spec.sh [ROOT]  (default: repo root)
set -u

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
spec="$root/openapi.json"
failures=0

fail() {
  echo "FAIL $1: rule $2: $3"
  failures=$((failures + 1))
}

# The servers value every published spec must carry (design: openapi.json).
expected_servers='[{"url":"https://{instance}.darthealth.com","description":"Your Data Nexus API host is issued at provisioning.","variables":{"instance":{"default":"datanexus"}}}]'

# Rule 1: valid JSON, OpenAPI 3.x, at least one path
if ! jq -e '(.openapi | type == "string" and startswith("3.")) and ((.paths // {}) | length > 0)' "$spec" >/dev/null 2>&1; then
  fail "openapi.json" 1 "not valid JSON, .openapi is not 3.x, or there are no paths"
else
  # Rule 2: servers is exactly the server-variable object
  if ! jq -e --argjson want "$expected_servers" '.servers == $want' "$spec" >/dev/null; then
    fail "openapi.json" 2 ".servers is not the published server-variable object"
  fi
fi

files=()
for f in "$spec" "$root/README.md"; do
  [ -f "$f" ] && files+=("$f")
done
if [ -d "$root/docs" ]; then
  while IFS= read -r f; do files+=("$f"); done < <(find "$root/docs" -type f | sort)
fi

host_allowed() {
  case "$1" in
    darthealth.com | www.darthealth.com | datanexus.darthealth.com | trust.darthealth.com) return 0 ;;
    "{instance}.darthealth.com" | github.com | raw.githubusercontent.com | rubygems.org) return 0 ;;
    *.test | *.example | *.invalid | example.com | example.org | example.net) return 0 ;;
  esac
  return 1
}

email_allowed() {
  case "$1" in
    developers@darthealth.com | hello@darthealth.com) return 0 ;;
  esac
  host_reserved "${1#*@}"
}

host_reserved() {
  case "$1" in
    *.test | *.example | *.invalid | example.com | example.org | example.net) return 0 ;;
  esac
  return 1
}

for f in ${files[@]+"${files[@]}"}; do
  rel="${f#"$root"/}"

  # Rule 3: every http(s) URL's host is on the allowlist
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    host="${url#*://}"
    host="${host%%/*}"
    case "$host" in
      *@*) fail "$rel" 3 "URL carries credentials: ${url%%@*}@..."; continue ;;
    esac
    host="${host%%:*}"
    host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    host_allowed "$host" || fail "$rel" 3 "URL host not allowed: $host"
  done < <(grep -oiE 'https?://[^][[:space:]"'"'"'<>()`,]+' "$f" || true)

  # Rule 4: localhost or an IPv4 address
  if grep -qiE 'localhost|(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)' "$f"; then
    fail "$rel" 4 "contains localhost or an IPv4 address"
  fi

  # Rule 5: email addresses other than the allowed ones
  while IFS= read -r email; do
    [ -z "$email" ] && continue
    lower="$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')"
    email_allowed "$lower" || fail "$rel" 5 "email not allowed: $email"
  done < <(grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" || true)

  # Rule 6: SSN-shaped strings
  if grep -qE '(^|[^0-9-])[0-9]{3}-[0-9]{2}-[0-9]{4}([^0-9-]|$)' "$f"; then
    fail "$rel" 6 "contains an SSN-shaped string"
  fi

  # Rule 7: something that looks like a Data Nexus API key (exactly 20
  # url-safe base64 characters) after apikey / api_key / API_KEY
  if grep -qiE 'api_?key[^A-Za-z0-9_-]{1,3}[A-Za-z0-9_-]{20}([^A-Za-z0-9_-]|$)' "$f"; then
    fail "$rel" 7 "contains what looks like an API key"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "check-spec: OK (${#files[@]} files)"
