# 0001. Stack: Flutter + Flame + forge2d

Date: 2026-06-12

## Status
Accepted

## Context
A 2D mini-game collection with local multiplayer, intended cross-platform reach,
built by a solo developer who values one codebase, clean Git/CI tooling, and
maintainable code. Pool needs a real 2D physics engine.

Options considered: native Swift + Kotlin (best Bluetooth APIs, but two
codebases — poor fit for "many mini-games"); Godot 4 (a real engine, strong
physics, but less mature local-Bluetooth plugin story); Flutter + Flame
(one codebase, mature tooling, mature local-multiplayer packages).

## Decision
Build on **Flutter** with **Flame** (game loop/rendering) and **flame_forge2d**
(Box2D physics). Lint with `very_good_analysis`.

## Consequences
One codebase across iOS/Android; excellent analyze/test/CI tooling; Dart is close
to the team's existing TypeScript. Physics fidelity is good enough for 2D games.
Trade-off: not a full native engine, and a performance ceiling vs. native — fine
for 2D mini-games. Bluetooth specifics are decided separately in ADR-0002.
