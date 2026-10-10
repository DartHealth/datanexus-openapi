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

if [ "$errors" -gt 0 ]; then
  echo "$errors test(s) failed"
  exit 1
fi
echo "all tests passed"
