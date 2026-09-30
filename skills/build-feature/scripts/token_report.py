#!/usr/bin/env python3
"""Token report for /build-feature phase agents.

Reads the sub-agent transcripts Claude Code writes under
~/.claude/projects/<project>/<session>/subagents/agent-*.jsonl and prints, per pipeline agent:
turns, peak context, total input tokens (with the cache split), output tokens, the skills and
sub-agents it invoked, and input tokens attributed to each skill segment.

Usage:
  python3 .claude/skills/build-feature/scripts/token_report.py [feature-slug] [--min-mb 0.3] [--project DIR]

Peak context is the number that matters: every tool call re-reads it. Anything above ~250k means a
phase file is letting too much into context.
"""
import argparse, collections, datetime, glob, json, os, re, sys

PHASE_MARKERS = [  # (marker in the launch prompt, label)
    ("phases/01-setup-plan.md", "A1"), ("phases/02-plan-review-tickets.md", "A2"),
    ("phases/03-implement.md", "B1"), ("phases/04-code-review.md", "B2"),
    ("phases/05-security-trace.md", "B3"), ("phases/06-system-tests.md", "C1"),
    ("phases/07-qa.md", "C2"), ("phases/08-acceptance.md", "C3"), ("phases/09-ship.md", "C4"),
    # legacy three-agent pipeline
    ("Phase 8: System Tests", "C(legacy)"), ("Phase 6: Implement", "B(legacy)"),
    ("Phase 3: Worktree Setup", "A(legacy)"),
]


def project_dir(explicit):
    if explicit:
        return explicit
    cwd = os.getcwd()
    return os.path.expanduser("~/.claude/projects/" + cwd.replace("/", "-"))


def first_text(line):
    try:
        j = json.loads(line)
        c = (j.get("message") or {}).get("content")
    except Exception:
        return line
    if isinstance(c, str):
        return c
    return " ".join(x.get("text", "") for x in c if isinstance(x, dict)) if isinstance(c, list) else ""


def classify(prompt):
    for marker, label in PHASE_MARKERS:
        if marker in prompt:
            return label
    if "/code" in prompt and "scope:" in prompt:
        return "worker"
    return None


def analyze(path):
    turns = peak = total_in = cache_read = out = 0
    skills, seg, cur = [], collections.OrderedDict(), "(pre)"
    with open(path) as f:
        for line in f:
            try:
                j = json.loads(line)
            except Exception:
                continue
            if j.get("type") != "assistant":
                continue
            u = (j.get("message") or {}).get("usage") or {}
            ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
            if ctx:
                turns += 1; total_in += ctx; peak = max(peak, ctx)
                cache_read += u.get("cache_read_input_tokens", 0); out += u.get("output_tokens", 0)
            seg[cur] = seg.get(cur, 0) + ctx
            for it in (j.get("message") or {}).get("content") or []:
                if not (isinstance(it, dict) and it.get("type") == "tool_use"):
                    continue
                inp = it.get("input") or {}
                if it.get("name") == "Skill":
                    cur = inp.get("skill", "?"); skills.append(cur)
                elif it.get("name") == "Agent":
                    skills.append("Agent:" + str(inp.get("description", ""))[:40])
    return turns, peak, total_in, cache_read, out, skills, seg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("slug", nargs="?", help="feature slug to filter on (substring of the launch prompt)")
    ap.add_argument("--min-mb", type=float, default=0.3, help="skip transcripts smaller than this")
    ap.add_argument("--project", help="override the ~/.claude/projects/<project> directory")
    a = ap.parse_args()
    pdir = project_dir(a.project)
    rows = []
    for p in glob.glob(os.path.join(pdir, "*", "subagents", "agent-*.jsonl")):
        if os.path.getsize(p) < a.min_mb * 1_000_000:
            continue
        with open(p) as f:
            prompt = first_text(f.readline())
        label = classify(prompt)
        if not label or (a.slug and a.slug not in prompt):
            continue
        m = re.search(r"FEATURE_NAME[`= :]+([a-z0-9-]+)", prompt)
        rows.append((os.path.getmtime(p), label, m.group(1) if m else "?", p, analyze(p)))
    if not rows:
        print(f"No pipeline transcripts found under {pdir}" + (f" for '{a.slug}'" if a.slug else ""))
        return 1
    rows.sort()
    grand_in = grand_out = 0
    for mtime, label, feat, p, (turns, peak, total_in, cache_read, out, skills, seg) in rows:
        grand_in += total_in; grand_out += out
        day = datetime.date.fromtimestamp(mtime)
        pct = (cache_read / total_in * 100) if total_in else 0
        print(f"\n{day} {label:10s} {feat}  turns={turns} peak={peak//1000}k "
              f"in={total_in/1e6:.1f}M (cache {pct:.0f}%) out={out//1000}k")
        if skills:
            print("  invoked:", " > ".join(skills))
        top = sorted(seg.items(), key=lambda x: -x[1])[:6]
        print("  input by segment:", ", ".join(f"{k}={v/1e6:.1f}M" for k, v in top))
    print(f"\nTOTAL: {len(rows)} agents, input {grand_in/1e6:.0f}M tokens, output {grand_out/1e3:.0f}k tokens")
    return 0


if __name__ == "__main__":
    sys.exit(main())
