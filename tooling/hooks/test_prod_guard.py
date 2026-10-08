#!/usr/bin/env python3
"""Tests for claude-hook-prod-guard.py. Run: python3 -m unittest tooling/hooks/test_prod_guard.py

Each case is a Bash command the agent might send. "asks" cases must be paused for approval
("deny" when unattended); "allowed" cases must pass through silently.
"""
import importlib.util
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

HOOK = Path(__file__).with_name("claude-hook-prod-guard.py")
spec = importlib.util.spec_from_file_location("prod_guard", HOOK)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

PROD = guard.PROD_APP
STAGING = guard.STAGING_APP

ASKS = [
    # plain production commands
    "fly deploy",
    "flyctl deploy",
    "flyadmin deploy",
    f"fly status -a {PROD}",
    f"bin/rails runner x --app={PROD}",
    "bin/deploy",
    "./bin/deploy production",
    "bin/rails production_reset:all",
    # quoting, paths and wrappers
    '"fly" deploy',
    "fl''y deploy",
    "f\\ly deploy",
    "/opt/homebrew/bin/fly deploy",
    "~/.fly/bin/flyctl deploy",
    'bash -c "fly deploy"',
    "sh -c 'flyadmin ssh console'",
    'eval "fly deploy"',
    "env FOO=1 fly deploy",
    "echo deploy | xargs fly",
    "find . -name x -exec fly deploy ;",
    "F=fly; $F deploy",
    # separators that start a new command
    f"fly status -a {STAGING} & fly deploy",
    f"echo $(fly deploy) -a {STAGING}",
    f"echo `fly deploy` -a {STAGING}",
    f"(fly deploy) && fly status -a {STAGING}",
    # staging flag that isn't really this invocation's
    f"fly deploy # -a {STAGING}",
    "fly deploy --config fly.staging.toml.bak",
    # text tools that write a file
    "echo fly deploy > deploy.sh",
    # heredocs: only document files are exempt
    "cat > deploy.sh <<'EOF'\nfly deploy\nEOF",
    "cat > notes.md <<'EOF'\nfly deploy\nEOF\nbash notes.md",
    "cat <<EOF | bash\nfly deploy\nEOF",
    # text printed by an exempt command and run by another segment
    "echo fly deploy | sh",
    "echo flyadmin deploy | bash",
    "printf 'fly deploy' | xargs -I{} sh -c {}",
    "echo fly deploy | tee deploy.sh",
    # git / gh can run commands themselves
    'git -c core.sshCommand="fly deploy" fetch',
    "git config alias.x '!fly deploy'",
    "gh alias set x '!fly deploy' --shell",
    "gh extension exec fly deploy",
    # shell syntax that still runs fly
    "fl\\\ny deploy",
    "{fly,} deploy",
    "$'fly' deploy",
    # gcloud / gsutil
    "gcloud secrets versions access latest --secret=x",
    "gcloud secrets versions add x --data-file=-",
    "gcloud run deploy web",
    "gsutil rm gs://bucket/x",
]

ALLOWED = [
    "git status",
    "bundle exec rspec spec/models",
    f"fly status -a {STAGING}",
    f"fly deploy --app {STAGING}",
    f"flyctl logs -a={STAGING}",
    "fly deploy --config fly.staging.toml",
    "bin/deploy staging",
    "cat fly.toml",
    "ls config/fly",
    "grep -rn 'fly deploy' docs/",
    "rg flyadmin skills/",
    'git commit -m "docs: explain fly deploy"',
    'gh pr create --title x --body "run flyadmin deploy after merge"',
    "cat > plan.md <<'EOF'\nfly deploy\nEOF",
    'gh issue comment 12 --body "flyadmin deploy is next"',
    "git log --grep fly",
    "gcloud projects list",
    "gsutil ls gs://bucket",
]


def run_hook(command, env_extra=None):
    env = {k: v for k, v in os.environ.items() if k not in ("HB_AUTOFIX", "CLAUDE_UNATTENDED")}
    env.update(env_extra or {})
    out = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True, text=True, env=env, check=True,
    ).stdout.strip()
    return json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else None


class ProdGuardTest(unittest.TestCase):
    def test_production_commands_are_paused(self):
        for command in ASKS:
            with self.subTest(command=command):
                self.assertIsNotNone(guard.production_reason(command))

    def test_ordinary_and_staging_commands_pass(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertIsNone(guard.production_reason(command))

    def test_asks_when_attended(self):
        self.assertEqual(run_hook("fly deploy"), "ask")
        self.assertIsNone(run_hook("git status"))

    def test_denies_when_unattended(self):
        self.assertEqual(run_hook("fly deploy", {"HB_AUTOFIX": "1"}), "deny")
        self.assertEqual(run_hook("fly deploy", {"CLAUDE_UNATTENDED": "1"}), "deny")

    def test_fails_closed_on_bad_input(self):
        out = subprocess.run([sys.executable, str(HOOK)], input="not json", capture_output=True, text=True).stdout
        self.assertEqual(json.loads(out)["hookSpecificOutput"]["permissionDecision"], "ask")

    def test_ignores_other_tools(self):
        out = subprocess.run(
            [sys.executable, str(HOOK)], input=json.dumps({"tool_name": "Read", "tool_input": {}}),
            capture_output=True, text=True,
        ).stdout
        self.assertEqual(out, "")


if __name__ == "__main__":
    unittest.main()
