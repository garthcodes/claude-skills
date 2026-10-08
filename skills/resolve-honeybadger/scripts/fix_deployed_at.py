#!/usr/bin/env python3
"""When did each fix first reach production?

Usage: fix_deployed_at.py --since YYYY-MM-DD MERGE_SHA [MERGE_SHA ...]

Reads Honeybadger's production deploy list (your deploy script reports every
deploy with its git revision) and, for each merge commit, finds the earliest deploy
whose revision contains it. Prints JSON {merge_sha: created_at | null}; null
means no recorded production deploy contains it yet (or the commit isn't known
locally: run `git fetch origin` first).

The project id comes from $HB_PROJECT_ID. The token comes from the macOS
Keychain item named by $HB_KEYCHAIN_SERVICE (default "honeybadger-token"),
is sent only in an in-process HTTP header and is never printed (same item as
resolve_faults.sh). Exit 3 when it's missing.
"""
import argparse
import os
import base64
import datetime as dt
import json
import subprocess
import sys
import urllib.parse
import urllib.request

KEYCHAIN_SERVICE = os.environ.get("HB_KEYCHAIN_SERVICE", "honeybadger-token")


def api():
    project = os.environ.get("HB_PROJECT_ID", "")
    if not project.isdigit():
        print("Set HB_PROJECT_ID to your production Honeybadger project id.", file=sys.stderr)
        sys.exit(2)
    return f"https://app.honeybadger.io/v2/projects/{project}/deploys"


def token():
    r = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"No Keychain item '{KEYCHAIN_SERVICE}' (see resolve_faults.sh).", file=sys.stderr)
        sys.exit(3)
    return r.stdout.strip()


def deploys(since, auth):
    # Honeybadger filters by Unix timestamp.
    after = int(dt.datetime.fromisoformat(since).replace(tzinfo=dt.timezone.utc).timestamp())
    url = f"{api()}?" + urllib.parse.urlencode({"environment": "production", "created_after": after})
    found = []
    while url and len(found) < 500:
        req = urllib.request.Request(url, headers={"Authorization": auth, "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            page = json.load(resp)
        found += page.get("results", [])
        url = (page.get("links") or {}).get("next")
    return found


def contains(revision, sha):
    r = subprocess.run(["git", "merge-base", "--is-ancestor", sha, revision], capture_output=True)
    return r.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True)
    ap.add_argument("shas", nargs="+")
    args = ap.parse_args()
    auth = "Basic " + base64.b64encode(f"{token()}:".encode()).decode()
    history = sorted(deploys(args.since, auth), key=lambda d: d.get("created_at") or "")
    result = {}
    for sha in args.shas:
        first = next((d for d in history if d.get("revision") and contains(d["revision"], sha)), None)
        result[sha] = first["created_at"] if first else None
    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
