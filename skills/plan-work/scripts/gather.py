#!/usr/bin/env python3
"""Snapshot everything /plan-work plans from, as one JSON file.

Reads GitHub (gh), git, the production revision (public sign-in page), the
autofix queue (bin/prod-read, read-only) and the daily-task traces. Writes
tmp/plan_work/snapshot.json and prints a short summary. Run from the repo root.
"""
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path.cwd()
OUT = ROOT / "tmp/plan_work"
sys.path.insert(0, str(ROOT / ".claude/skills/resolve-honeybadger/scripts"))
import find_fixed_faults  # noqa: E402  (reuses its prod-revision reader)

MIGRATION = re.compile(r"^db/migrate/")
DESTRUCTIVE = re.compile(r"remove_column|drop_table|rename_column|rename_table|change_column\b|\.update_all|execute\s|UPDATE\s", re.I)
BILLING = re.compile(r"stedi|claim|invoice|era|payment|stripe|superbill|billing|ledger|payer", re.I)
CLOSES = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", re.I)
BUG_LABELS = {"bug", "honeybadger", "fix-didnt-work"}
IMPACT = ["impact: blocking", "impact: important", "impact: annoying", "impact: nice-to-have"]


def sh(*args, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check).stdout


def gh_json(*args):
    return json.loads(sh("gh", *args))


def is_ancestor(sha, rev):
    if not sha or not rev:
        return None
    r = subprocess.run(["git", "merge-base", "--is-ancestor", sha, rev], capture_output=True)
    return r.returncode == 0 if r.returncode in (0, 1) else None


def risk(paths, number=None):
    """Deploy risk from the files a PR touches; reads migration bodies only when there are any."""
    flags = []
    migrations = [p for p in paths if MIGRATION.match(p)]
    if migrations:
        flags.append("migration")
        diff = sh("gh", "pr", "diff", str(number), check=False) if number else ""
        added = [l for part in diff.split("diff --git ")[1:] if MIGRATION.match(part.split(" b/", 1)[-1])
                 for l in part.splitlines() if l.startswith("+")]
        if DESTRUCTIVE.search("\n".join(added)):
            flags.append("destructive-migration")
    if any(BILLING.search(p) for p in paths if p.startswith("app/")):
        flags.append("billing")
    if any(p in ("Gemfile.lock", "config/importmap.rb", "package.json") for p in paths):
        flags.append("dependencies")
    if any(p.startswith(("config/", "Dockerfile", "fly")) and not p.startswith("config/locales") for p in paths):
        flags.append("config")
    return flags


def pr_stage(pr):
    bodies = [c["body"] for c in pr.get("comments", [])]
    has = lambda h: any(b.lstrip().startswith(h) for b in bodies)  # noqa: E731
    if has("## Review decisions"):
        return "ready-to-merge" if not pr["isDraft"] else "settled-still-draft"
    if has("## Cold review"):
        return "needs-settle"
    if "autofix" in pr["labels"] or pr["headRefName"].startswith(("issue_", "fix/honeybadger-")):
        return "autofix-building"
    return "draft" if pr["isDraft"] else "open"


def open_prs():
    fields = "number,title,isDraft,labels,headRefName,createdAt,additions,deletions,files,comments,body,mergeable,url"
    prs = gh_json("pr", "list", "--state", "open", "--limit", "100", "--json", fields)
    out = []
    for pr in prs:
        pr["labels"] = [l["name"] for l in pr["labels"]]
        paths = [f["path"] for f in pr["files"]]
        out.append({
            "number": pr["number"], "title": pr["title"], "url": pr["url"], "draft": pr["isDraft"],
            "labels": pr["labels"], "branch": pr["headRefName"], "created": pr["createdAt"][:10],
            "size": pr["additions"] + pr["deletions"], "files": len(paths), "mergeable": pr["mergeable"],
            "stage": pr_stage(pr), "closes": sorted({int(n) for n in CLOSES.findall(pr["body"] or "")}),
            "risk": risk(paths, pr["number"]),
        })
    return out


def undeployed(prod):
    merged = gh_json("pr", "list", "--state", "merged", "--limit", "60", "--json", "number,title,mergeCommit,mergedAt,files")
    out = []
    for pr in merged:
        sha = (pr.get("mergeCommit") or {}).get("oid")
        if is_ancestor(sha, prod) is False:
            out.append({"number": pr["number"], "title": pr["title"], "merged": pr["mergedAt"],
                        "risk": risk([f["path"] for f in pr["files"]], pr["number"])})
    return out


def open_issues(prs):
    issues = gh_json("issue", "list", "--state", "open", "--limit", "200", "--json", "number,title,labels,createdAt,url")
    with_pr = {n for pr in prs for n in pr["closes"]} | {int(m.group(1)) for pr in prs if (m := re.match(r"issue_(\d+)$", pr["branch"]))}
    out = []
    for i in issues:
        labels = [l["name"] for l in i["labels"]]
        if "autofix-log" in labels:
            continue
        out.append({
            "number": i["number"], "title": i["title"], "url": i["url"], "labels": labels, "created": i["createdAt"][:10],
            "bug": bool(BUG_LABELS & set(labels)),
            "user_reported": "user-reported" in labels,
            "impact": next((x for x in IMPACT if x in labels), None),
            "autofix": "queued" if "autofix-queue" in labels else "started" if "autofix" in labels else None,
            "needs_decision": "needs-decision" in labels,
            "has_pr": i["number"] in with_pr,
        })
    return out


def autofix_state():
    r = subprocess.run(["bin/prod-read"], stdin=open(HERE / "autofix_state.rb"), capture_output=True, text=True)
    line = next((l for l in reversed(r.stdout.splitlines()) if l.startswith("{")), None)
    return json.loads(line) if line else {"error": (r.stderr or r.stdout)[-300:]}


def daily(today):
    sp = ROOT / "tmp/legacy_claim_status"
    stamps = [p.name for p in (sp / "archive").glob("20*")] if (sp / "archive").exists() else []
    stamps += [datetime.fromtimestamp(p.stat().st_mtime).date().isoformat() for p in sp.glob("*.json")]
    try:
        faults = json.loads(sh("python3", str(ROOT / ".claude/skills/resolve-honeybadger/scripts/find_fixed_faults.py")))
        resolvable = sum(1 for f in faults.get("faults", []) if f.get("ready"))
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        resolvable = None
    return {
        "legacy-claim-status": {"last_run": max(stamps) if stamps else None},
        "resolve-honeybadger": {"resolvable_faults": resolvable},
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sh("git", "fetch", "-q", "origin")
    prod = find_fixed_faults.deployed_sha()
    prs = open_prs()
    snap = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="minutes"),
        "today": date.today().isoformat(),
        "prod_revision": prod,
        "main_head": sh("git", "rev-parse", "origin/main").strip(),
        "undeployed_merged": undeployed(prod),
        "open_prs": prs,
        "open_issues": open_issues(prs),
        "autofix": autofix_state(),
        "daily": daily(date.today().isoformat()),
    }
    (OUT / "snapshot.json").write_text(json.dumps(snap, indent=2))
    stages = {}
    for pr in prs:
        stages[pr["stage"]] = stages.get(pr["stage"], 0) + 1
    print(f"wrote {OUT / 'snapshot.json'}")
    print(f"prod {(prod or '?')[:8]}  main {snap['main_head'][:8]}  undeployed merged PRs: {len(snap['undeployed_merged'])}")
    print(f"open PRs by stage: {stages}")
    print(f"open issues: {len(snap['open_issues'])} (bugs {sum(i['bug'] for i in snap['open_issues'])})")
    af = snap["autofix"]
    print("autofix:", "ERROR " + af["error"] if "error" in af else f"running {len(af['running'])} queued {len(af['queued'])} paused={af['paused']}")


if __name__ == "__main__":
    main()
