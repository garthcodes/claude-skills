#!/usr/bin/env python3
"""List Honeybadger fault ids that recently merged PRs / closed issues fixed.

Usage: find_fixed_faults.py [--since YYYY-MM-DD] [--deployed-sha SHA]

Reads GitHub with `gh`, reads the production revision from the
honeybadger-revision meta tag on a public page of your app ($APP_URL plus
$APP_REVISION_PATH, default /users/sign_in; or pass --deployed-sha), and checks each fix PR's
merge commit against it with `git merge-base --is-ancestor`.

Prints JSON: {"since", "deployed_sha", "faults": [...], "mentions_only": [...]}.
Each fault: {"fault_id", "fixes": [{"pr", "title", "merged_at", "role",
"merge_sha", "deployed", "via"}], "ready": bool}. role = "primary" (the PR fixes the
fault itself) or "follow-up" (it closes a "Follow-up to HB #id" issue).
ready = at least one primary fix (or, with none, any fix) is in production.
mentions_only = ids that appear only in PR/issue bodies (docs syncs, notes);
never resolve those on this evidence alone.
"""
import argparse
import os
import datetime as dt
import json
import re
import subprocess
import sys
import urllib.request

# Honeybadger fault ids are numeric; adjust if yours are a different length.
FAULT_ID = os.environ.get("HB_FAULT_ID_PATTERN", r"(1\d{8})")
TITLE_ID = re.compile(r"(?:HB|honeybadger)[^0-9\n]{0,12}#?" + FAULT_ID, re.I)
# A line that starts "Fixes Honeybadger fault #id" or is the PR's own
# "- [ ] Resolve HB fault id" to-do. Looser matching picks up docs-sync PRs
# that list old fix branches (fix/honeybadger-<id>) and tooling PRs that
# quote fault ids in passing.
BODY_FIX = re.compile(
    r"^[ \t]*(?:[-*][ \t]*)?(?:\[[ xX]\][ \t]*)?(?:fixes|fixed|resolves?)[ \t]+(?:the[ \t]+)?"
    r"(?:honeybadger|HB)?[ \t]*(?:fault)?[ \t]*\[?#?" + FAULT_ID,
    re.I | re.M,
)
BRANCH_ID = re.compile(r"honeybadger-" + FAULT_ID)
ANY_ID = re.compile(r"\b" + FAULT_ID + r"\b")
FOLLOW_UP = re.compile(r"follow-?up", re.I)


def gh(args):
    out = subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def deployed_sha():
    base = os.environ.get("APP_URL")
    if not base:
        print("Set APP_URL (your production app's https URL) or pass --deployed-sha.", file=sys.stderr)
        sys.exit(2)
    url = base.rstrip("/") + os.environ.get("APP_REVISION_PATH", "/users/sign_in")
    with urllib.request.urlopen(url, timeout=20) as resp:
        html = resp.read().decode("utf-8", "replace")
    m = re.search(r'name="honeybadger-revision" content="([0-9a-f]{40})"', html)
    return m.group(1) if m else None


def is_deployed(merge_sha, prod_sha):
    if not merge_sha or not prod_sha:
        return None
    r = subprocess.run(["git", "merge-base", "--is-ancestor", merge_sha, prod_sha], capture_output=True)
    if r.returncode in (0, 1):
        return r.returncode == 0
    return None  # commit unknown locally — caller should `git fetch origin`


def main():
    ap = argparse.ArgumentParser()
    yesterday = (dt.date.today() - dt.timedelta(days=1)).isoformat()
    ap.add_argument("--since", default=yesterday, help="YYYY-MM-DD, default yesterday")
    ap.add_argument("--deployed-sha", help="override the production revision")
    args = ap.parse_args()

    subprocess.run(["git", "fetch", "-q", "origin"], check=False)
    prod = args.deployed_sha or deployed_sha()

    prs = gh(["pr", "list", "--state", "merged", "--search", f"merged:>={args.since}", "--limit", "200",
              "--json", "number,title,body,mergedAt,headRefName,mergeCommit,closingIssuesReferences"])
    issues = gh(["issue", "list", "--state", "closed", "--search", f"closed:>={args.since}", "--limit", "200",
                 "--json", "number,title,body,stateReason,closedAt"])
    issue_by_num = {i["number"]: i for i in issues}

    fixes = {}  # fault_id -> {pr_number: fix}
    mentioned = set()

    def add(fid, pr, role, via):
        entry = fixes.setdefault(fid, {}).get(pr["number"])
        if entry and entry["role"] == "primary":
            return
        fixes[fid][pr["number"]] = {
            "pr": pr["number"], "title": pr["title"], "merged_at": pr["mergedAt"], "role": role,
            "merge_sha": (pr.get("mergeCommit") or {}).get("oid"),
            "deployed": is_deployed((pr.get("mergeCommit") or {}).get("oid"), prod), "via": via,
        }

    for pr in prs:
        body = pr.get("body") or ""
        mentioned.update(ANY_ID.findall(body))
        for fid in TITLE_ID.findall(pr["title"]):
            add(fid, pr, "primary", "PR title")
        for fid in BRANCH_ID.findall(pr.get("headRefName") or ""):
            add(fid, pr, "primary", "branch name")
        for fid in BODY_FIX.findall(body):
            add(fid, pr, "primary", "PR body says it fixes the fault")
        closing = [c["number"] for c in pr.get("closingIssuesReferences") or []]
        closing += [int(n) for n in re.findall(r"(?i)(?:closes|fixes|resolves) #(\d+)", body)]
        for num in set(closing):
            issue = issue_by_num.get(num)
            if not issue or issue.get("stateReason") == "NOT_PLANNED":
                continue
            role = "follow-up" if FOLLOW_UP.search(issue["title"]) else "primary"
            for fid in TITLE_ID.findall(issue["title"]):
                add(fid, pr, role, f"closes issue #{num}")

    for issue in issues:
        mentioned.update(ANY_ID.findall(issue.get("body") or ""))

    faults = []
    for fid, by_pr in sorted(fixes.items()):
        fx = sorted(by_pr.values(), key=lambda f: f["merged_at"])
        primaries = [f for f in fx if f["role"] == "primary"] or fx
        faults.append({"fault_id": int(fid), "fixes": fx, "ready": any(f["deployed"] for f in primaries)})

    json.dump({
        "since": args.since,
        "deployed_sha": prod,
        "faults": faults,
        "mentions_only": sorted(int(m) for m in mentioned - set(fixes)),
    }, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
