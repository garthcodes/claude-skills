#!/usr/bin/env python3
"""
PreToolUse hook (matcher: Bash) — production guard.

Production (Fly app PROD_APP, below) is live. This hook pauses any Bash command that
targets production and forces an explicit user approval prompt, overriding any
permission allowlist entries. Staging-targeted commands (<PROD_APP>-staging /
fly.staging.toml) pass through untouched.

Output contract: on a production-targeting command, emit a PreToolUse
permissionDecision of "ask" and exit 0. On no match, print nothing. On any
internal error, fail CLOSED (ask) — never silently allow.
"""
import json
import re
import sys

# Your production Fly app name. Staging is assumed to be f"{PROD_APP}-staging".
PROD_APP = "<app-name>"
STAGING_APP = f"{PROD_APP}-staging"

# Shell separators that delimit independent command invocations.
SEGMENT_SPLIT = re.compile(r"(?:&&|\|\||;|\||\n)")

# fly/flyctl used as a command word (not e.g. the filename fly.toml).
FLY_CMD = re.compile(r"(?:^|[\s;&|(`])(?:fly|flyctl)\s+\w")

# Explicit staging targeting within one invocation.
STAGING_TARGET = re.compile(
    r"--config[=\s]+\S*fly\.staging\.toml|(?:^|\s)(?:-a|--app)[=\s]+" + re.escape(STAGING_APP) + r"(?![\w-])"
)

# Explicit production app flag anywhere (covers scripts wrapping fly).
PROD_APP_FLAG = re.compile(r"(?:^|\s)(?:-a|--app)[=\s]+" + re.escape(PROD_APP) + r"(?![\w-])")

# bin/deploy defaults to needing approval unless first arg is exactly "staging".
BIN_DEPLOY = re.compile(r"(?:^|[\s;&|(`])(?:\./)?bin/deploy(?![\w-])(?!\s+staging(?![\w-]))")

# The TRUNCATE-everything rake namespace.
PRODUCTION_RESET = re.compile(r"\bproduction_reset\b")

GCLOUD_CMD = re.compile(r"(?:^|[\s;&|(`])gcloud\s+\w")
GSUTIL_CMD = re.compile(r"(?:^|[\s;&|(`])gsutil\s+\w")
GCLOUD_MUTATING = re.compile(
    r"\b(?:add-iam-policy-binding|remove-iam-policy-binding|set-iam-policy|"
    r"create|delete|undelete|destroy|update|rotate|enable|disable|import|deploy|"
    r"rm|mv|rsync)\b"
    r"|\bstorage\s+cp\b|\bsecrets\s+versions\s+add\b|\bconfig\s+set\b"
)
GSUTIL_MUTATING = re.compile(
    r"\b(?:rm|cp|mv|rsync|setmeta|setacl|defacl|ch|mb|rb|compose|rewrite|retention)\b"
)

# `cat > file <<'EOF'` / `cat <<'EOF' > file` with a QUOTED delimiter: the shell does no expansion and
# nothing executes the body — it is inert text written to a file (plans, docs, PR bodies that quote
# deploy commands). Only that exact shape is exempt. Unquoted delimiters (they expand $(...)),
# heredocs piped anywhere, $(cat <<'X' ...) substitutions, and interpreter heredocs
# (`python3 - <<'EOF'`) stay fully guarded.
INERT_HEREDOC = re.compile(
    r"(?:^|[;&]\s*)cat"
    r"(?:\s+>>?\s*(?P<out1>[^\s|;&<>()]+))?"
    r"\s+<<-?\s*(?P<q>['\"])(?P<tag>\w+)(?P=q)"
    r"(?:\s*>>?\s*(?P<out2>[^\s|;&<>()]+))?\s*$"
)

ANY_HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")

def strip_inert_heredoc_bodies(command):
    """Drop the bodies of top-level inert `cat > file <<'EOF'` heredocs; every other line is checked."""
    lines = command.split("\n")
    if any(line.count("<<") > 1 for line in lines):
        return command  # several heredocs on one line: don't try to be clever
    kept, i = [], 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        inert = INERT_HEREDOC.search(line)
        other = ANY_HEREDOC.search(line)
        if inert and (inert.group("out1") or inert.group("out2")):
            tag, drop = inert.group("tag"), True
        elif other:
            tag, drop = other.group(2), False  # any other heredoc: keep its body, never look inside it
        else:
            i += 1
            continue
        i += 1
        while i < len(lines) and lines[i].strip() != tag:
            if not drop:
                kept.append(lines[i])
            i += 1
        if i < len(lines):
            kept.append(lines[i])
        i += 1
    return "\n".join(kept)


def production_reason(command):
    """Return a short reason string if the command targets production, else None."""
    command = strip_inert_heredoc_bodies(command)
    if PROD_APP_FLAG.search(command):
        return f"targets Fly app {PROD_APP}"
    if PRODUCTION_RESET.search(command):
        return "references the production_reset rake namespace"
    if BIN_DEPLOY.search(command):
        return "bin/deploy without the staging argument deploys production"

    for segment in SEGMENT_SPLIT.split(command):
        if FLY_CMD.search(segment) and not STAGING_TARGET.search(segment):
            return f"fly/flyctl command not explicitly targeting staging defaults to production ({PROD_APP})"
        if GCLOUD_CMD.search(segment) and GCLOUD_MUTATING.search(segment):
            return "mutating gcloud command against the production GCP project"
        if GSUTIL_CMD.search(segment) and GSUTIL_MUTATING.search(segment):
            return "mutating gsutil command against production Cloud Storage"
    return None


def ask(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": (
                f"Production-targeting command ({reason}) — requires explicit user "
                "approval. Production actions must never run automatically."
            ),
        }
    }))
    sys.exit(0)


def main():
    hook_input = json.load(sys.stdin)
    if hook_input.get("tool_name") != "Bash":
        return
    command = hook_input.get("tool_input", {}).get("command") or ""
    reason = production_reason(command)
    if reason:
        ask(reason)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # fail closed — never silently allow on hook error
        ask(f"prod-guard hook error, failing closed: {e.__class__.__name__}")
    sys.exit(0)
