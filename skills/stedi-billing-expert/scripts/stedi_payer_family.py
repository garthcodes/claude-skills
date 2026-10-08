#!/usr/bin/env python3
"""Look up payers in Stedi's payer directory and resolve carrier families.

Read-only and free. Uses the TEST key only (STEDI_TEST_API_KEY): the payer
directory is shared between test and production, so a production key is never
needed and is never read.

Usage (run from the repo root so .env is found):

  # Where does a name on an insurance card / legacy export route?
  python3 .claude/skills/stedi-billing-expert/scripts/stedi_payer_family.py --like "Surest"
  python3 .claude/skills/stedi-billing-expert/scripts/stedi_payer_family.py --like 25463

  # Every payer Stedi files under a corporate family (by group id or name)
  python3 .claude/skills/stedi-billing-expert/scripts/stedi_payer_family.py --group-id FIVMG
  python3 .claude/skills/stedi-billing-expert/scripts/stedi_payer_family.py --group-name "UnitedHealth Group" --states TX,OK --medical

  # Machine-readable
  python3 .claude/skills/stedi-billing-expert/scripts/stedi_payer_family.py --group-id FIVMG --json > uhg.json

Group lookups page the whole directory (~3,700 payers, ~37 requests) because
the API has no server-side group filter; the result is cached for a day in
--cache (default: ~/.cache/stedi-payer-family/payers.json). --refresh forces a re-fetch.

See ../references/payer-directory.md for how each field maps onto the app's
`payers` / `payer_groups` tables and the rules for turning a family into rows.
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://healthcare.us.stedi.com/2024-04-01"
# Default --states filter: the practice's operating states, e.g. STEDI_OPERATING_STATES=TX,OK
DEFAULT_STATES = os.environ.get("STEDI_OPERATING_STATES", "")


def api_key():
    if os.environ.get("STEDI_TEST_API_KEY"):
        return os.environ["STEDI_TEST_API_KEY"]
    # Fall back to the checkout's .env. Only the test key is ever read.
    if os.path.exists(".env"):
        with open(".env") as f:
            for line in f:
                line = line.strip()
                if line.startswith("STEDI_TEST_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    sys.exit("No STEDI_TEST_API_KEY in env or .env (the production key is never used)")


def get(path, key):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Key " + key})
    for attempt in range(4):
        try:
            return json.load(urllib.request.urlopen(req))
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")[:300]
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(1.5 * (attempt + 1))
                continue
            sys.exit(f"HTTP {e.code} for {path}: {body}")
        except urllib.error.URLError:
            time.sleep(1.5 * (attempt + 1))
    sys.exit(f"gave up on {path}")


def search(query, key, page_size=25):
    # pageSize must be 10..100 — 8 is a 400.
    d = get(f"/payers/search?query={urllib.parse.quote(query)}&pageSize={page_size}", key)
    return [item["payer"] for item in d.get("items", [])]


def full_directory(key, cache, refresh):
    if not refresh and os.path.exists(cache) and time.time() - os.path.getmtime(cache) < 86400:
        return json.load(open(cache))
    payers, token = [], None
    while True:
        path = "/payers?pageSize=100" + (f"&pageToken={urllib.parse.quote(token)}" if token else "")
        d = get(path, key)
        payers.extend(d["items"])  # list endpoint returns bare payer objects
        token = d.get("nextPageToken")
        if not token:
            break
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache, "w") as f:
        json.dump(payers, f)
    return payers


def operates_in(p, states):
    ops = set(p.get("operatingStates", []))
    return not ops or "NATIONAL" in ops or bool(ops & states)


def row(p):
    ts = p.get("transactionSupport", {})
    return {
        "displayName": p.get("displayName"),
        "primaryPayerId": p.get("primaryPayerId"),
        "stediId": p.get("stediId"),
        "parentPayerGroupId": p.get("parentPayerGroupId"),
        "parentPayerGroupName": p.get("parentPayerGroupName"),
        "operatingStates": p.get("operatingStates", []),
        "programs": p.get("programs", []),
        "coverageTypes": p.get("coverageTypes", []),
        "professionalClaimSubmission": ts.get("professionalClaimSubmission"),
        "eligibilityCheck": ts.get("eligibilityCheck"),
        "claimStatus": ts.get("claimStatus"),
        "claimPayment": ts.get("claimPayment"),  # ERA support lives here, not claimPaymentAdvice
        "aliases": p.get("aliases", []),
        "names": p.get("names", []),
        "enrollment": p.get("enrollment", {}),
    }


def print_table(rows):
    fmt = "%-48s %-8s %-6s %-22s %-12s %-10s %-9s %-9s %-9s"
    print(fmt % ("name", "edi", "stedi", "group", "states", "programs", "837P", "270", "ERA(835)"))
    for r in rows:
        print(fmt % (
            (r["displayName"] or "")[:48], r["primaryPayerId"], r["stediId"],
            (r["parentPayerGroupName"] or "-")[:22],
            ",".join(r["operatingStates"])[:12] or "-",
            ",".join(x[:4] for x in r["programs"])[:10] or "-",
            (r["professionalClaimSubmission"] or "")[:9],
            (r["eligibilityCheck"] or "")[:9],
            (r["claimPayment"] or "")[:9]))
        if r["names"]:
            print("      also known as: " + "; ".join(r["names"][:6]) + (" …" if len(r["names"]) > 6 else ""))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--like", help="name or payer ID to search (uses /payers/search)")
    mode.add_argument("--group-id", help="Stedi parentPayerGroupId, e.g. FIVMG")
    mode.add_argument("--group-name", help="Stedi parentPayerGroupName, e.g. 'UnitedHealth Group'")
    ap.add_argument("--states", default=DEFAULT_STATES, help="keep payers operating in these states or NATIONAL/blank (default $STEDI_OPERATING_STATES); '' = no filter")
    ap.add_argument("--medical", action="store_true", help="keep only payers whose coverageTypes include medical")
    ap.add_argument("--claims-supported", action="store_true", help="keep only professionalClaimSubmission == SUPPORTED")
    ap.add_argument(
        "--cache",
        default=os.path.join(os.path.expanduser("~"), ".cache", "stedi-payer-family", "payers.json"),
    )
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    key = api_key()
    if a.like:
        payers = search(a.like, key)
    else:
        allp = full_directory(key, a.cache, a.refresh)
        if a.group_id:
            payers = [p for p in allp if p.get("parentPayerGroupId") == a.group_id]
        else:
            payers = [p for p in allp if (p.get("parentPayerGroupName") or "").lower() == a.group_name.lower()]
        states = {s.strip().upper() for s in a.states.split(",") if s.strip()}
        if states:
            payers = [p for p in payers if operates_in(p, states)]
        if a.medical:
            payers = [p for p in payers if "medical" in p.get("coverageTypes", [])]
        if a.claims_supported:
            payers = [p for p in payers if p.get("transactionSupport", {}).get("professionalClaimSubmission") == "SUPPORTED"]
        payers.sort(key=lambda p: p.get("displayName", ""))

    rows = [row(p) for p in payers]
    if a.json:
        json.dump(rows, sys.stdout, indent=2)
    else:
        print_table(rows)
        print(f"\n{len(rows)} payer(s)")
        if a.like and rows:
            groups = {(r["parentPayerGroupId"], r["parentPayerGroupName"]) for r in rows if r["parentPayerGroupId"]}
            for gid, gname in sorted(groups, key=lambda g: g[1]):
                print(f"family: --group-id {gid}  ({gname})")


if __name__ == "__main__":
    main()
