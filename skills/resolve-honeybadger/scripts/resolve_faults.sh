#!/usr/bin/env bash
# Mark Honeybadger faults resolved.
#
# Usage: resolve_faults.sh [--project ID] FAULT_ID [FAULT_ID ...]
#
# The project id comes from --project or $HB_PROJECT_ID.
# The personal auth token comes from the macOS Keychain item named by
# $HB_KEYCHAIN_SERVICE (default "honeybadger-token") and is read here only,
# never printed and never put on a command line: curl reads it from stdin
# (--config -), so it doesn't show up in `ps`.
# One-time setup, in a regular Terminal (prompts for the token,
# Honeybadger -> Profile -> Authentication):
#   security add-generic-password -U -a "$USER" -s honeybadger-token -w
#
# Prints "<fault_id> resolved" or "<fault_id> FAILED <http code>" per fault,
# then "RESULT: resolved=N failed=M". Exits non-zero if any failed.
set -euo pipefail

project=${HB_PROJECT_ID:-}
service=${HB_KEYCHAIN_SERVICE:-honeybadger-token}
if [ "${1:-}" = "--project" ]; then
  project=$2
  shift 2
fi
[ -n "$project" ] || { echo "Set HB_PROJECT_ID or pass --project ID." >&2; exit 2; }
[[ "$project" =~ ^[0-9]+$ ]] || { echo "Project id must be numeric." >&2; exit 2; }
[ $# -gt 0 ] || { echo "usage: $0 [--project ID] FAULT_ID..." >&2; exit 2; }

if ! token=$(security find-generic-password -s "$service" -w 2>/dev/null); then
  echo "No Keychain item '$service'. Create it with:" >&2
  echo "  security add-generic-password -U -a \"\$USER\" -s $service -w" >&2
  exit 3
fi

resolved=0
failed=0
for id in "$@"; do
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    echo "$id FAILED not-a-fault-id"
    failed=$((failed + 1))
    continue
  fi
  # printf is a shell builtin, so the token never appears in a process's argv.
  code=$(printf 'user = "%s:"\n' "$token" | curl -s -o /dev/null -w '%{http_code}' -m 20 --config - -X PUT \
    -H 'Content-Type: application/json' -d '{"fault":{"resolved":true}}' \
    "https://app.honeybadger.io/v2/projects/$project/faults/$id")
  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    echo "$id resolved"
    resolved=$((resolved + 1))
  else
    echo "$id FAILED $code"
    failed=$((failed + 1))
  fi
done

echo "RESULT: resolved=$resolved failed=$failed"
[ "$failed" -eq 0 ]
