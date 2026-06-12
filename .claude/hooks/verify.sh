#!/usr/bin/env bash
# Stop gate: don't let the agent finish while `flutter analyze` is unhappy.
# exit 2 keeps the agent working; it clears to exit 0 once analysis is clean.
# (Full test suite is enforced in CI, not here, to avoid slow local loops.)
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -f pubspec.yaml ] || exit 0
command -v flutter >/dev/null 2>&1 || exit 0
if ! flutter analyze >/tmp/pa_analyze.log 2>&1; then
  echo "flutter analyze reported issues — resolve them before finishing:" >&2
  tail -n 40 /tmp/pa_analyze.log >&2
  exit 2
fi
exit 0
