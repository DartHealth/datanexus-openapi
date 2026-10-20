#!/usr/bin/env bash
# Runs check-spec.sh against each fixture and refresh-spec.sh against local
# files. Each failing fixture directory is named rule<N>-<case> and holds only
# the files that differ from fixtures/pass/. Usage: scripts/test/run.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
scripts="$(cd "$here/.." && pwd)"
fixtures="$here/fixtures"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
errors=0

bad() {
  echo "  not ok: $1"
  errors=$((errors + 1))
}

# A clean root passes.
if out="$("$scripts/check-spec.sh" "$fixtures/pass" 2>&1)"; then
  echo "ok: pass"
else
  bad "pass fixture failed: $out"
fi

# Each failing fixture fails, and fails on the rule its name says.
for case_dir in "$fixtures"/rule*; do
  name="$(basename "$case_dir")"
  rule="${name#rule}"
  rule="${rule%%-*}"
  root="$work/$name"
  mkdir -p "$root"
  cp -R "$fixtures/pass/." "$root/"
  cp -R "$case_dir/." "$root/"
  if out="$("$scripts/check-spec.sh" "$root" 2>&1)"; then
    bad "$name passed but should fail on rule $rule"
  elif ! printf '%s\n' "$out" | grep -q ": rule $rule:"; then
    bad "$name failed, but not on rule $rule: $out"
  else
    echo "ok: $name"
  fi
done

# A URL's credentials never appear in the failure output.
for name in rule3-credentials rule3-credentials-query; do
  root="$work/$name"
  if out="$("$scripts/check-spec.sh" "$root" 2>&1)"; then
    bad "$name: passed but should fail"
  elif printf '%s\n' "$out" | grep -qE 'deploy|s3cretTok'; then
    bad "$name: output prints the URL's userinfo: $out"
  else
    echo "ok: $name credentials are not printed"
  fi
done

# A host's query or fragment isn't part of the host: an allowed host passes
# (an @ in the query isn't a credential), a disallowed one is named without it.
root="$work/allowed-query"
mkdir -p "$root"
cp -R "$fixtures/pass/." "$root/"
for url in 'https://www.darthealth.com?utm=x' 'https://www.darthealth.com#faq' 'https://www.darthealth.com?ref=a@b'; do
  printf 'See %s\n' "$url" > "$root/docs/query.md"
  if out="$("$scripts/check-spec.sh" "$root" 2>&1)"; then
    echo "ok: allowed $url"
  else
    bad "allowed $url failed: $out"
  fi
done
out="$("$scripts/check-spec.sh" "$work/rule3-host-query" 2>&1)"
if printf '%s\n' "$out" | grep -qx 'FAIL README.md: rule 3: URL host not allowed: internal\.example-corp\.io'; then
  echo "ok: disallowed host is named without its query"
else
  bad "disallowed host with a query: $out"
fi

# refresh-spec.sh: pins servers, sorts keys, reports changes.
raw="$work/raw.json"
jq '.servers = [{"url": "/", "variables": {}}]' "$fixtures/pass/openapi.json" > "$raw"
dir="$work/refresh"
mkdir -p "$dir"
jq 'del(.paths["/api/members"])' "$fixtures/pass/openapi.json" > "$dir/openapi.json"
if out="$(SPEC_URL="file://$raw" SPEC_DIR="$dir" "$scripts/refresh-spec.sh" 2>&1)"; then
  if ! jq -e --slurpfile want "$fixtures/pass/openapi.json" '.servers == $want[0].servers' "$dir/openapi.json" >/dev/null; then
    bad "refresh: servers not pinned"
  elif ! cmp -s <(jq --sort-keys --indent 2 . "$dir/openapi.json") "$dir/openapi.json"; then
    bad "refresh: output keys not sorted"
  elif ! printf '%s\n' "$out" | grep -q "Operations added: GET /api/members"; then
    bad "refresh: change report missing the added operation: $out"
  else
    echo "ok: refresh"
  fi
else
  bad "refresh failed: $out"
fi

# refresh-spec.sh: running again with no upstream change changes nothing.
cp "$dir/openapi.json" "$work/first.json"
if ! SPEC_URL="file://$raw" SPEC_DIR="$dir" "$scripts/refresh-spec.sh" >/dev/null 2>&1; then
  bad "refresh: second run failed"
elif ! cmp -s "$work/first.json" "$dir/openapi.json"; then
  bad "refresh: second run changed openapi.json"
else
  echo "ok: refresh is idempotent"
fi

# refresh-spec.sh: a failed fetch, a non-JSON body, a leaking spec, or a spec
# with no paths leaves openapi.json untouched.
cp "$dir/openapi.json" "$work/before.json"
printf '<html>Bad gateway</html>' > "$work/html.json"
jq '.info.description = "see http://localhost:4000"' "$raw" > "$work/leak.json"
jq '.paths = {}' "$raw" > "$work/empty.json"
for src in "file://$work/missing.json" "file://$work/html.json" "file://$work/leak.json" "file://$work/empty.json"; do
  if SPEC_URL="$src" SPEC_DIR="$dir" "$scripts/refresh-spec.sh" >/dev/null 2>&1; then
    bad "refresh succeeded from $src"
  elif ! cmp -s "$work/before.json" "$dir/openapi.json"; then
    bad "refresh changed openapi.json after failing on $src"
  else
    echo "ok: refresh refuses $(basename "$src")"
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "$errors test(s) failed"
  exit 1
fi
echo "all tests passed"
