# 0000. Record architecture decisions

Date: 2026-06-12

## Status
Accepted

## Context
We want decisions and their reasoning to live in the repo so context survives
across sessions and tools, instead of evaporating with chat history.

## Decision
We use Architecture Decision Records (Michael Nygard's format). Each significant
decision is a numbered file in `docs/adr/`. Use `docs/adr/template.md` as the
starting point (or `/adr <title>`). ADRs are immutable once Accepted; to reverse
one, write a new ADR that supersedes it.

## Consequences
Decisions are reviewable, greppable, and explain themselves later. New
contributors (human or agent) can reconstruct *why*, not just *what*.
