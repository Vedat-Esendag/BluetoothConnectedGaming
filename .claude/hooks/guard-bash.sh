#!/usr/bin/env bash
# PreToolUse(Bash) guard: block obviously destructive commands. exit 2 = block.
input=$(cat)
if printf '%s' "$input" | grep -Eq 'rm[[:space:]]+-rf?[[:space:]]+(/|~|\$HOME)([[:space:]]|"|$)|:\(\)\{[[:space:]]*:|mkfs|dd[[:space:]]+if=|>[[:space:]]*/dev/sd|git[[:space:]]+push[[:space:]]+[^|]*--force[^|]*\b(main|master)\b'; then
  echo "Blocked: this command matches a destructive pattern. If you truly intend it, run it yourself in a terminal." >&2
  exit 2
fi
exit 0
