# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Project scaffold: mini-game registry, `PeerTransport` abstraction, validated
  `PeerMessage`, Pool descriptor stub.
- Engineering setup: CLAUDE.md, review subagents, hooks, CI, ADRs.
- `CONTRIBUTING.md`: branch/PR flow, Conventional Commits, review gates,
  `/new-minigame`, and the definition of done.

### Changed
- Adopt `package:` imports and clear all `very_good_analysis` findings.
- Align naming: package stays `bluetooth_connected_gaming`; the product display
  name is the `<DISPLAY NAME>` placeholder, and README badges point at the repo.
- Scope Git LFS to `assets/`; keep platform launcher icons in normal git so the
  iOS/Android CI builds can read them.

### Removed
- Unused `equatable` dependency.
- `flutter_nearby_connections` dependency — deferred until the transport is
  implemented; it does not build under AGP 8.11 / Kotlin 2.2 yet (see ADR-0004).
