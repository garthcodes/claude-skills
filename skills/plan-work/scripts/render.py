#!/usr/bin/env python3
"""Render tmp/plan_work/plan.json into tmp/plan_work/plan-work.html (the published page)."""
import json
from pathlib import Path

ROOT = Path.cwd()
plan = json.loads((ROOT / "tmp/plan_work/plan.json").read_text())
template = (Path(__file__).resolve().parent.parent / "assets/template.html").read_text()
# "</" would end the <script> block early; JSON allows the escaped form.
data = json.dumps(plan, ensure_ascii=False).replace("</", "<\\/")
out = ROOT / "tmp/plan_work/plan-work.html"
out.write_text(template.replace("/*__PLAN__*/", data))
print(out)
