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

# A root missing a file every published copy needs fails on rule 1.
for req in README.md docs/when-to-use.md; do
  root="$work/missing-${req//\//-}"
  mkdir -p "$root"
  cp -R "$fixtures/pass/." "$root/"
  rm "$root/$req"
  if out="$("$scripts/check-spec.sh" "$root" 2>&1)"; then
    bad "missing $req passed but should fail on rule 1"
  elif ! printf '%s\n' "$out" | grep -q "^FAIL $req: rule 1:"; then
    bad "missing $req failed, but not on rule 1: $out"
  else
    echo "ok: missing $req"
  fi
done

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
# The script lowercases hosts, so match case-insensitively.
for name in rule3-credentials rule3-credentials-query rule3-credentials-fragment rule3-credentials-subdomain-password rule3-port-token rule3-nested-url-encoded-credentials \
  rule3-credentials-protocol-relative rule3-credentials-no-scheme rule3-credentials-no-scheme-subdomain-password; do
  root="$work/$name"
  if out="$("$scripts/check-spec.sh" "$root" 2>&1)"; then
    bad "$name: passed but should fail"
  elif printf '%s\n' "$out" | grep -qiE 'deploy|s3cretTok'; then
    bad "$name: output prints the URL's userinfo: $out"
  else
    echo "ok: $name credentials are not printed"
  fi
done

# A path on the production host never appears in the failure output: it may name a record.
for name in rule3-admin-path rule3-prod-path-dotdot rule3-prod-path-encoded-dotdot rule3-prod-path-openapi-dotdot \
  rule3-prod-path-comma-dotdot rule3-prod-path-protocol-relative rule3-prod-path-no-scheme rule3-prod-path-api \
  rule3-prod-path-backslash rule3-prod-path-paren-dotdot rule3-prod-path-quote-dotdot rule3-prod-path-query-path \
  rule3-prod-path-adjacent-link rule3-prod-path-comma-link rule3-prod-host-encoded-path rule3-prod-host-nested-double-encoded \
  rule3-prod-path-paren-encoded-dotdot rule3-prod-path-query-encoded-path rule3-prod-path-query-backslash; do
  out="$("$scripts/check-spec.sh" "$work/$name" 2>&1)"
  if printf '%s\n' "$out" | grep -qE 'sponsor_members|admin/users|api/members'; then
    bad "$name: output prints the path: $out"
  else
    echo "ok: $name path is not printed"
  fi
done

# A host's query or fragment isn't part of the host: an allowed host passes
# (an @ in the query isn't a credential), a disallowed one is named without it.
root="$work/allowed-query"
mkdir -p "$root"
cp -R "$fixtures/pass/." "$root/"
for url in 'https://www.darthealth.com?utm=x' 'https://www.darthealth.com#faq' 'https://www.darthealth.com?ref=a@b' \
  'https://www.darthealth.com.' 'https://www.darthealth.com, then' 'https://www.darthealth.com;' 'https://www.darthealth.com:' \
  'https://datanexus.darthealth.com?ref=x' 'https://datanexus.darthealth.com/?ref=x' 'https://datanexus.darthealth.com#top' \
  'https://customer.darthealth.com.example/' 'customer.darthealth.com.au' \
  'https://datanexus.darthealth.com/api/openapi' 'https://datanexus.darthealth.com/api/openapi?ref=x' 'https://datanexus.darthealth.com/api/openapi#top' \
  'https://datanexus.darthealth.com/api/openapi, then fetch it.' 'https://datanexus.darthealth.com/api/openapi.' \
  'Email hello@darthealth.com' 'mailto:hello@darthealth.com'; do
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
cp -R "$fixtures/pass/." "$dir/"
jq 'del(.paths["/api/members"])' "$fixtures/pass/openapi.json" > "$dir/openapi.json"
# stderr is dropped so a check-spec call that loses its >&2 shows up in stdout.
if out="$(SPEC_URL="file://$raw" SPEC_DIR="$dir" "$scripts/refresh-spec.sh" 2>/dev/null)"; then
  mode="$(stat -c %a "$dir/openapi.json" 2>/dev/null || stat -f %Lp "$dir/openapi.json")"
  if ! jq -e --slurpfile want "$fixtures/pass/openapi.json" '.servers == $want[0].servers' "$dir/openapi.json" >/dev/null; then
    bad "refresh: servers not pinned"
  elif ! cmp -s <(jq --sort-keys --indent 2 . "$dir/openapi.json") "$dir/openapi.json"; then
    bad "refresh: output keys not sorted"
  elif [ "$out" != "$(printf '%s\n' "Operations added: GET /api/members" "Operations removed: none" \
    "Schemas added: none" "Schemas removed: none")" ]; then
    bad "refresh: stdout is not exactly the expected change report: $out"
  elif [ "$mode" != 644 ]; then
    bad "refresh: openapi.json mode is $mode, want 644"
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

# refresh-spec.sh: a change report that fails (here, on an unreadable
# previous copy) leaves openapi.json untouched.
corrupt="$work/corrupt"
mkdir -p "$corrupt"
cp -R "$fixtures/pass/." "$corrupt/"
printf '{"openapi": "3.0.0",' > "$corrupt/openapi.json"
cp "$corrupt/openapi.json" "$work/corrupt-before.json"
if SPEC_URL="file://$raw" SPEC_DIR="$corrupt" "$scripts/refresh-spec.sh" >/dev/null 2>&1; then
  bad "refresh succeeded over an unreadable openapi.json"
elif ! cmp -s "$work/corrupt-before.json" "$corrupt/openapi.json"; then
  bad "refresh changed openapi.json after its change report failed"
else
  echo "ok: refresh leaves openapi.json untouched when its report fails"
fi

# refresh-spec.sh: a report that cannot be written (stdout open read-only, so every
# write fails with EBADF; a closed fd 1 gets reused by the next open on Linux)
# leaves openapi.json untouched, so a retry still reports the change.
closed="$work/closed-stdout"
mkdir -p "$closed"
cp -R "$fixtures/pass/." "$closed/"
jq 'del(.paths["/api/members"])' "$fixtures/pass/openapi.json" > "$closed/openapi.json"
cp "$closed/openapi.json" "$work/closed-before.json"
if SPEC_URL="file://$raw" SPEC_DIR="$closed" "$scripts/refresh-spec.sh" 1</dev/null 2>/dev/null; then
  bad "refresh succeeded with a closed stdout"
elif ! cmp -s "$work/closed-before.json" "$closed/openapi.json"; then
  bad "refresh changed openapi.json before its report was written"
elif compgen -G "$closed/.openapi.json.refresh.*" >/dev/null; then
  bad "refresh left a staged file behind after failing"
else
  echo "ok: refresh leaves openapi.json untouched when its report can't be written"
fi

if [ "$errors" -gt 0 ]; then
  echo "$errors test(s) failed"
  exit 1
fi
echo "all tests passed"
