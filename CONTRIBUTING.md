# Contributing to <DISPLAY NAME>

<DISPLAY NAME> is a Flutter app of small mini-games played locally over
Bluetooth between two phones, with no server. This guide is how we work day to
day. The authoritative rules live in [CLAUDE.md](CLAUDE.md) and the design in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — when this guide and those
disagree, those win.

## Ground rules

- **Module per game.** Each mini-game lives in `lib/games/<id>/` and is reached
  only through `MiniGameRegistry`. Never import another game's internals, and
  adding a game must not edit existing games.
- **Never trust the peer.** Every inbound frame is parsed through
  `PeerMessage.fromWire`, which validates and throws on anything malformed.
  There is no server — this validation is the security boundary.
- **Host-authoritative multiplayer.** One device runs the simulation and
  broadcasts authoritative state; the client sends inputs and renders what it's
  told. Don't run independent physics on both devices (see
  [ADR-0003](docs/adr/0003-state-synchronization.md)).
- **Decisions get an ADR.** Record architectural choices in `docs/adr/` with
  `/adr <title>` before or with the code.

## The loop: branch → build → review → gate → ship

1. **Branch per change.** Cut a short-lived branch off `main`:
   `feat/<id>-<slug>`, `fix/<slug>`, `refactor/<slug>`, `docs/<slug>`, or
   `chore/<slug>`. Keep `main` releasable; don't push to it directly.
2. **Build the smallest slice that works.**
3. **Review.** Run `/review` on the diff and hand it to the right subagent(s).
4. **Gate.** Satisfy the local hooks and green CI (below).
5. **Ship.** Open a pull request into `main` and merge once CI is green and the
   review has signed off.

## Commits — Conventional Commits

Every commit message starts with a
[Conventional Commits](https://www.conventionalcommits.org/) type: `feat:`,
`fix:`, `refactor:`, `test:`, `docs:`, `chore:`. Keep each commit to one logical
change, and keep refactors in their own commits, separate from features.

```
feat(pool): add cue aiming and shot power
fix(transport): drop frames with out-of-order sequence numbers
test(peer-message): cover oversized and malformed frames
docs: document the host-authoritative sync model
```

## Review gates

Three layers guard every change; all must pass before merge.

- **Hooks (local, automatic).** Editing a Dart file auto-runs `dart format`.
  When the agent stops, a hook runs `flutter analyze` and blocks on any
  issue — under `very_good_analysis`, warnings are failures. A Bash guard
  refuses obviously destructive commands.
- **Review subagents.** Reach for `security-reviewer` whenever transport,
  permissions, or inbound-data handling changes; `code-reviewer` after any
  non-trivial change; `maintenance` when duplication or coverage gaps appear.
- **CI (required).** Each pull request runs `dart format --set-exit-if-changed`,
  `flutter analyze`, and `flutter test --coverage`, plus debug Android and iOS
  builds. Branch protection requires CI green before merge.

Before you push, run the same checks locally:

```
dart format .
flutter analyze
flutter test
```

## Adding a mini-game

Scaffold the module with the slash command:

```
/new-minigame <id>
```

That creates `lib/games/<id>/<id>_descriptor.dart` implementing
`MiniGameDescriptor`. Then:

1. Register it in `lib/main.dart` with one line via `MiniGameRegistry` — that is
   the only edit outside your game's folder.
2. Build the Flame game and rules alongside the descriptor.
3. Ship tests for the rules/scoring. A host simulation must have a determinism
   test: same inputs → same state.

Games depend on `core/`; `core/` never imports `games/`.

## Definition of done

- Code formatted (`dart format .`) and `flutter analyze` clean.
- Tests written and passing (`flutter test`).
- `docs/` and `CHANGELOG.md` updated; an ADR added if the change was
  architectural.
- Reviewed by the relevant subagent(s).
