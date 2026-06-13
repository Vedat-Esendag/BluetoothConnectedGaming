#!/usr/bin/env bash
# Injects a short reminder of the working agreement + current branch at session start.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
ctx="NearPlay — branch: ${branch}. Rules: module-per-game (lib/games/<id>/, registry only); never trust the peer (validate via PeerMessage.fromWire); host-authoritative sync; ADR for architectural decisions. Loop: decide (council) -> build -> review (subagents) -> gate (hooks/CI) -> ship. See CLAUDE.md."
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(printf '%s' "$ctx" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$ctx")"
exit 0
