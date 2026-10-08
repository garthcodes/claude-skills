#!/usr/bin/env python3
"""
PreToolUse hook (matcher: Bash) — production guard.

Production (Fly app PROD_APP, below) is live. This hook pauses any Bash command that
targets production and forces an explicit user approval prompt, overriding any
permission allowlist entries. Staging-targeted commands (<PROD_APP>-staging /
fly.staging.toml) pass through untouched.

Output contract: on a production-targeting command, emit a PreToolUse
permissionDecision of "ask" and exit 0 ("deny" when the session is unattended:
HB_AUTOFIX=1 or CLAUDE_UNATTENDED=1, because nobody is there to answer a prompt).
On no match, print nothing. On any internal error, fail CLOSED — never silently allow.

This is a tripwire, not a security boundary. It reads the command text, so a determined
caller can still hide a production command (a variable holding the binary name, a script
file written in an earlier tool call). The real boundary is credentials: the agent's own
Fly, database and cloud credentials should be read-only. `tooling/hooks/test_prod_guard.py`
lists what the hook does and does not catch.
"""
import json
import os
import re
import sys

# Your production Fly app name. Staging is assumed to be f"{PROD_APP}-staging".
PROD_APP = "<app-name>"
STAGING_APP = f"{PROD_APP}-staging"

# Shell separators that delimit independent command invocations. `&` (background) and command
# substitution (`$(...)`, backticks, subshell parens) start a new command too.
SEGMENT_SPLIT = re.compile(r"(?:&&|\|\||;|\||&|\n|\$\(|`|\(|\))")

# Quote and escape characters the shell removes before running a word: `"fly"`, `fl''y` and `f\ly`
# all run fly. Deleting them first means the patterns below see the word the shell will run.
QUOTE_CHARS = re.compile(r"[\"'\\]")

# fly/flyctl/flyadmin as a word anywhere in a segment: after whitespace, a path (`/opt/homebrew/bin/fly`)
# or an assignment (`F=fly`), and followed by whitespace or the end. `fly.toml` doesn't match.
FLY_WORD = re.compile(r"(?:^|[\s/=])(?:fly|flyctl|flyadmin)(?=\s|$)")

# Explicit staging targeting. Only checked in the text AFTER the fly word, with any `# comment` removed,
# so `fly status -a <app>-staging & fly deploy` and `fly deploy # -a <app>-staging` don't count as staging.
STAGING_TARGET = re.compile(
    r"--config[=\s]+\S*fly\.staging\.toml(?=\s|$)|(?:^|\s)(?:-a|--app)[=\s]+" + re.escape(STAGING_APP) + r"(?![\w.-])"
)
SHELL_COMMENT = re.compile(r"(?:^|\s)#.*$")

# Segments whose command word only reads or prints text. A fly word inside them is an argument
# (`grep fly docs/`, `gh pr create --body "...flyadmin deploy..."`), not a command, unless the segment
# also writes a file (`echo fly deploy > x.sh`).
TEXT_ONLY_COMMANDS = {
    "grep", "egrep", "fgrep", "rg", "ag", "ack", "echo", "printf", "cat", "head", "tail", "less",
    "wc", "ls", "git", "gh",
}
ASSIGNMENT = re.compile(r"^\w+=")
PLACEHOLDER = re.compile(r"<[\w.-]+>")

# Explicit production app flag anywhere (covers scripts wrapping fly).
PROD_APP_FLAG = re.compile(r"(?:^|\s)(?:-a|--app)[=\s]+" + re.escape(PROD_APP) + r"(?![\w-])")

# bin/deploy defaults to needing approval unless first arg is exactly "staging".
BIN_DEPLOY = re.compile(r"(?:^|[\s;&|(`])(?:\./)?bin/deploy(?![\w-])(?!\s+staging(?![\w-]))")

# The TRUNCATE-everything rake namespace.
PRODUCTION_RESET = re.compile(r"\bproduction_reset\b")

GCLOUD_CMD = re.compile(r"(?:^|[\s/=])gcloud\s+\w")
GSUTIL_CMD = re.compile(r"(?:^|[\s/=])gsutil\s+\w")
GCLOUD_MUTATING = re.compile(
    r"\b(?:add-iam-policy-binding|remove-iam-policy-binding|set-iam-policy|"
    r"create|delete|undelete|destroy|update|rotate|enable|disable|import|deploy|"
    r"rm|mv|rsync)\b"
    r"|\bstorage\s+cp\b|\bsecrets\s+versions\s+(?:add|access)\b|\bconfig\s+set\b"
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

# Only heredocs written to a document file are exempt; a body written to a script (or to a file the
# same command then runs) is checked like any other command.
INERT_OUTPUT_EXT = re.compile(r"\.(?:md|txt|json|html|csv|log|patch|diff)$")


def strip_inert_heredoc_bodies(command):
    """Drop the bodies of top-level inert `cat > file.md <<'EOF'` heredocs; every other line is checked."""
    lines = command.split("\n")
    if any(line.count("<<") > 1 for line in lines):
        return command  # several heredocs on one line: don't try to be clever
    kept, i = [], 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        inert = INERT_HEREDOC.search(line)
        other = ANY_HEREDOC.search(line)
        out = inert and (inert.group("out1") or inert.group("out2"))
        if out and INERT_OUTPUT_EXT.search(out) and not runs_file(command, out):
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


def runs_file(command, path):
    """True when the command also executes `path` (bash x.md, sh x.md, source x.md, . x.md, ./x.md)."""
    name = re.escape(path.lstrip("./"))
    return re.search(r"(?:\b(?:bash|sh|zsh|source)\s+|(?:^|[\s;&|])\.\s+|(?:^|[\s;&|])\./)(?:\./)?" + name + r"(?![\w.])", command) is not None


def command_word(segment):
    """The segment's command name: first word after any leading VAR=value assignments, path stripped."""
    for word in segment.split():
        if not ASSIGNMENT.match(word):
            return word.rsplit("/", 1)[-1]
    return ""


def text_only(segment):
    writes_file = ">" in PLACEHOLDER.sub("", segment)  # `<app-name>` is a placeholder, not a redirect
    return command_word(segment) in TEXT_ONLY_COMMANDS and not writes_file


def production_reason(command):
    """Return a short reason string if the command targets production, else None."""
    command = QUOTE_CHARS.sub("", strip_inert_heredoc_bodies(command))
    if PROD_APP_FLAG.search(command):
        return f"targets Fly app {PROD_APP}"
    if PRODUCTION_RESET.search(command):
        return "references the production_reset rake namespace"
    if BIN_DEPLOY.search(command):
        return "bin/deploy without the staging argument deploys production"

    for segment in SEGMENT_SPLIT.split(command):
        if text_only(segment):
            continue
        fly = FLY_WORD.search(segment)
        if fly and not STAGING_TARGET.search(SHELL_COMMENT.sub("", segment[fly.end():])):
            return f"fly command not explicitly targeting staging defaults to production ({PROD_APP})"
        if GCLOUD_CMD.search(segment) and GCLOUD_MUTATING.search(segment):
            return "mutating gcloud command against the production GCP project"
        if GSUTIL_CMD.search(segment) and GSUTIL_MUTATING.search(segment):
            return "mutating gsutil command against production Cloud Storage"
    return None


def unattended():
    return os.environ.get("HB_AUTOFIX") == "1" or os.environ.get("CLAUDE_UNATTENDED") == "1"


def ask(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny" if unattended() else "ask",
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
