## What & why
<!-- One or two sentences. Link the issue/milestone. -->

## Checklist
- [ ] `dart format .` applied
- [ ] `flutter analyze` is clean
- [ ] Tests added/updated and `flutter test` passes
- [ ] Module boundaries respected (no cross-game imports; `core/` doesn't import `games/`)
- [ ] Peer-facing changes validate all inbound data via `PeerMessage.fromWire`
- [ ] ADR added/updated if this was an architectural decision
- [ ] CHANGELOG updated under Unreleased
- [ ] **If this touches `lib/core/transport/ble/`:** the real-device smoke test
      (`docs/testing/bluetooth-smoke-test.md`) was run, and the devices/OS
      versions are recorded below. CI cannot test Bluetooth — nothing else
      covers those files.

## Notes for reviewer
<!-- Anything the security-reviewer / code-reviewer subagents should focus on. -->
