Run a full review of the current uncommitted changes.

1. Run `git diff` to gather the changes.
2. If transport, permissions, or peer-data handling changed, invoke the
   `security-reviewer` subagent.
3. Invoke the `code-reviewer` subagent on the diff.
4. Consolidate findings into one prioritized list (High → Low) with `file:line`
   and concrete fixes, and a single overall verdict.
Do not fix anything yet — just report.
