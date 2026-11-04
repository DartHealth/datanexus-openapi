#!/usr/bin/env bash
# Refreshes openapi.json from production's live spec, pins the published
# servers value, checks the result, and prints what changed for the PR body.
# Usage: scripts/refresh-spec.sh
# Env: SPEC_URL (default: production), SPEC_DIR (default: repo root)
set -euo pipefail

spec_url="${SPEC_URL:-https://datanexus.darthealth.com/api/openapi}"
dir="${SPEC_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
here="$(cd "$(dirname "$0")" && pwd)"
servers='[{"url":"https://datanexus.darthealth.com"},{"url":"https://{instance}.darthealth.com","description":"Your Data Nexus API host is issued at provisioning.","variables":{"instance":{"default":"datanexus"}}}]'

tmp="$(mktemp -d)"
staged=''
trap 'rm -rf "$tmp"; if [ -n "$staged" ]; then rm -f -- "$staged"; fi' EXIT

curl -fsS --retry 3 --max-time 30 "$spec_url" -o "$tmp/raw.json"
jq --sort-keys --indent 2 --argjson servers "$servers" '.servers = $servers' "$tmp/raw.json" > "$tmp/openapi.json"

if [ -f "$dir/openapi.json" ]; then
  cp "$dir/openapi.json" "$tmp/previous.json"
else
  echo '{"paths":{},"components":{"schemas":{}}}' > "$tmp/previous.json"
fi

ops='[.paths // {} | to_entries[] | .key as $p | .value | keys[]
      | select(IN("get","put","post","delete","patch","head","options","trace"))
      | "\(ascii_upcase) \($p)"]'
schemas='[.components.schemas // {} | keys[]]'

# Check the candidate in a scratch root before it replaces anything.
mkdir -p "$tmp/root"
cp "$tmp/openapi.json" "$tmp/root/openapi.json"
"$here/check-spec.sh" "$tmp/root" >&2  # stdout carries only the change report

# If openapi.json is unreadable the report fails and nothing is replaced:
# delete it and re-run.
report="$(jq -rn --slurpfile old "$tmp/previous.json" --slurpfile new "$tmp/openapi.json" "
  def ops: $ops; def schemas: $schemas;
  (\$new[0] | ops) as \$no | (\$old[0] | ops) as \$oo |
  (\$new[0] | schemas) as \$ns | (\$old[0] | schemas) as \$os |
  \"Operations added: \((\$no - \$oo) | if length == 0 then \"none\" else join(\", \") end)\",
  \"Operations removed: \((\$oo - \$no) | if length == 0 then \"none\" else join(\", \") end)\",
  \"Schemas added: \((\$ns - \$os) | if length == 0 then \"none\" else join(\", \") end)\",
  \"Schemas removed: \((\$os - \$ns) | if length == 0 then \"none\" else join(\", \") end)\"
")"

# Replace openapi.json only once everything above, including writing the
# report, has succeeded. Staging in the same directory makes the mv a single
# rename, so it is never half-written; mktemp keeps concurrent runs apart.
staged="$(mktemp "$dir/.openapi.json.refresh.XXXXXX")"
cp "$tmp/openapi.json" "$staged"
chmod 644 "$staged"  # mktemp makes it 0600, and mv would carry that over
printf '%s\n' "$report"
mv "$staged" "$dir/openapi.json"
