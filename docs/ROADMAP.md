# NearPlay — Development Roadmap

Issue dependency map and critical path from scaffold to Pool being playable.  
Live tracker: https://github.com/Vedat-Esendag/BluetoothConnectedGaming/issues

---

## Critical Path (13 steps, M1 → M2)

Every link must complete before the next can start:

```
#15 → #5+#12 → #7 → #8 → #9 → #10 → #29+#16 → #13 → #17 → #19 → #22 → #23
```

---

## Dependency Graph

```
#15 (ADR-0005) ──── DECISION GATE — resolve before writing any transport code
    │
    ├── #5  (permissions) ── #7 (GATT server) ─┐
    │                        #8 (scan+connect) ─┴──► #9 (raw bytes) ──► #10 (PeerConnection)
    │                                                                          │
    │                                                                    ┌─────┴──────┐
    │                                                                    ▼            ▼
    ├── #12 (codec) ─────────────────────────────────────────────► #11 (loopback)  #29 (replay)
    │                                                                                │
    │                                                                    ┌───────────┘
    │                                                                    ▼
    │                                                               #16 (PeerTransport impl)
    │                                                                    │
    │                                                          ┌─────────┴──────────┐
    │                                                          ▼                    ▼
    │                                                     #13 (handshake)    #26 (smoke test)
    │                                                          │              #28 (reconnect)
    │                                                     ┌────┘
    ├── #6  (host/join screen) ──────────────────────────►│
    │                                                     ▼
    │                                               #17 (GameSession wiring)
    │                                                     │
    │                                          ┌──────────┘
    │                                          ▼
    │                                    #19 (Pool simulation)
    │                                          │
    │                               ┌──────────┼──────────┐
    │                               ▼          ▼          ▼
    │                          #20 (input)  #21 (render)  │
    │                                          │           │
    │                                          └─────┬─────┘
    │                                                ▼
    │                                          #22 (rules engine)
    │                                                │
    │                                                ▼
    │                                          #23 (win/loss screen)
    │
    ├── #18 (display name) ── leaf, anytime
    ├── #24 (registry tests) ─ leaf, anytime
    └── #25 (CI coverage) ──── leaf, add after #22 ships with its tests
```

---

## Phase Map

### Phase 0 — Decision Gate
Must resolve before any BLE code is written.

| Issue | Title | Status |
|-------|-------|--------|
| **#15** | Confirm transport strategy + write ADR-0005 | Ready |

### Phase 1 — Foundation (parallelizable once #15 is decided)

| Issue | Title | Blocks |
|-------|-------|--------|
| **#5** | Bluetooth permissions | #7, #8 |
| **#12** | Message encode/decode (codec) | #11, #13, #14, #16 |
| **#18** | Fix display name placeholder | nothing |
| **#24** | MiniGameRegistry unit tests | nothing |

### Phase 2 — BLE Stack (sequential)

| Issue | Title | Blocked by | Blocks |
|-------|-------|------------|--------|
| **#7** | GATT server (host) | #15, #5 | #9 |
| **#8** | Scan + connect (joiner) | #15, #5 | #9 |
| **#9** | Exchange raw bytes | #7, #8 | #10 |
| **#10** | PeerConnection wrapper | #9 | #11, #16, #29 |

### Phase 3 — Transport Layer
Build #11 (loopback) alongside #16 so M2 Pool logic can be developed without two phones.

| Issue | Title | Blocked by | Blocks |
|-------|-------|------------|--------|
| **#11** | Loopback test double | #10, #12 | enables all M2 testing without hardware |
| **#29** | Replay protection (seq tracking) | #10 | #16 |
| **#16** | Concrete PeerTransport impl | #10, #12, #29 | #13, #17, #26, #28 |

### Phase 4 — Shell Integration

| Issue | Title | Blocked by | Blocks |
|-------|-------|------------|--------|
| **#6** | Host/join screen | none | #17 |
| **#13** | Handshake + role assignment | #16 | #14, #17 |
| **#14** | State sync (Pool-scoped, see ADR-0003) | #13, #16 | #21 |
| **#17** | Wire GameSession into game.build() | #6, #13, #16 | all Pool issues |

### Phase 5 — Pool Game (M2)

| Issue | Title | Blocked by | Blocks |
|-------|-------|------------|--------|
| **#19** | Flame widget + forge2d simulation | #17 | #20, #21, #22 |
| **#20** | Shot input (aim + fire) | #19, #16 | — |
| **#21** | Client rendering (receive + render host state) | #19, #16, #14 | #22 |
| **#22** | Rules engine (8-ball logic) | #19, #21 | #23 |
| **#23** | Win/loss screen + rematch | #22, #17 | — |
| **#28** | Disconnect/reconnect flow | #16, #17 | — |

### Phase 6 — Quality and M3

| Issue | Title | Notes |
|-------|-------|-------|
| **#25** | CI coverage threshold | Add after #22 ships — meaningless at 0% game coverage |
| **#26** | Bluetooth smoke-test runbook | Write after #16 ships — can't validate before then |
| **#27** | Second mini-game (M3) | After Pool proves the module contract |
| **#37** | BLE debug/test strategy | Research done — `docs/testing-ble.md` + ADR-0006; informs #11/#16/#26 |

---

## What to Work on Right Now

1. **#15** — write ADR-0005, confirm transport library (half-day; unlocks 7+ issues)
2. **#12** — message codec (zero dependencies; can start today)
3. **#18** — fix display name (5 minutes; leaf issue)
4. **#24** — MiniGameRegistry tests (pure Dart, ~1 hour; leaf issue)

---

## Effort Notes

| Issue | Warning |
|-------|---------|
| **#19** | Budget 2–3× estimate. CLAUDE.md requires a forge2d determinism test ("same inputs → same state") — getting bit-identical physics output is non-trivial. |
| **#12** | Don't over-engineer before #15 closes. Wire format may need adjustment depending on the transport backend. |
| **#14** | Scope to Pool only (ADR-0003 model). Do **not** build a general-purpose turn system. |
| **#11** | Build this alongside #16, not before. The interface may shift while #12 and #10 are being built. |

---

## Milestone Summary

| Milestone | Issues | Exit Criteria |
|-----------|--------|---------------|
| **M1: Transport Live** | #5, #7–#16, #26, #29 | Two phones exchange PeerMessages over Bluetooth |
| **M2: Pool Playable** | #6, #17–#23, #25, #28 | Full 8-ball game, host-authoritative, no server |
| **M3: Architecture Validated** | #27 | Second game added with zero changes to existing code |
