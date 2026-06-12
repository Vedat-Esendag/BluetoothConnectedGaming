#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit): auto-format the edited Dart file. Never blocks.
input=$(cat)
file=$(printf '%s' "$input" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')
if [ -n "$file" ] && printf '%s' "$file" | grep -q '\.dart$' && [ -f "$file" ]; then
  dart format "$file" >/dev/null 2>&1 || true
fi
exit 0
