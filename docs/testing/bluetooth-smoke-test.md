# Bluetooth smoke test (real devices)

CI cannot test Bluetooth. It type-checks the radio adapters and runs the whole
stack above them over a loopback link, but nothing in CI advertises, scans,
pairs, or moves a byte over a radio. **This checklist is the only thing that
does.** Run it before merging any change to `lib/core/transport/ble/`, and once
in full before a release.

Two files carry all the untested risk — `bluetooth_low_energy_scanner.dart` and
`bluetooth_low_energy_host.dart`. They are excluded from the CI coverage floor
for exactly that reason (`tool/check_coverage.dart`), so this document is what
stands in its place.

## What you need

- **Two phones.** At least one Android/Android pass and one **Android + iOS**
  pass — the cross-OS case is the one ADR-0002 committed to and the one most
  likely to break.
- A debug build on both (`flutter run`), so you can read the console.
- Bluetooth on, app permissions not yet granted on at least one device (so the
  permission path gets exercised rather than skipped).

Record the OS versions you tested on in the PR. "Works on my phone" is not a
result anyone can reproduce.

---

## 1. Permissions and readiness

| # | Step | Expected |
|---|------|----------|
| 1.1 | Launch with Bluetooth **off** | The game list shows the "Bluetooth is off" banner. No crash, no empty screen. |
| 1.2 | Turn Bluetooth on, without touching the app | Banner disappears on its own within a second or two. **No retry tap needed** — this is the adapter-state stream working. |
| 1.3 | Turn Bluetooth off again mid-app | Banner reappears. |
| 1.4 | Deny the Bluetooth permission prompt (Android), then tap Host | A message asking for permission, with an **Open Settings** button that actually opens this app's settings page. |
| 1.5 | Grant permission in Settings, return to the app | Hosting proceeds. |

## 2. Host and discover

| # | Step | Expected |
|---|------|----------|
| 2.1 | Device A: open Pool → type a name → **Host a game** | "Waiting for a player", showing the name typed. |
| 2.2 | Device B: open Pool → **Join a game** | Device A appears in the list **within 10 seconds**, under the name A typed. |
| 2.3 | Check the proximity label on B | "Right here" with the phones touching; "Nearby"/"Far away" as you separate them. |
| 2.4 | Device B: tap A | Both devices reach the Pool table. Neither hangs on "Connecting". |
| 2.5 | Check both HUDs | A (host) shows "Your turn"; B shows "Waiting for &lt;A's name&gt;". Names are the ones typed, not device names or ids. |

**If 2.2 fails**, the advertisement is the suspect: iOS centrals can only scan
by advertised service UUID, so the service UUID must be in the advertisement
packet and not only in the GATT table (ADR-0006).

## 3. Bytes in both directions

| # | Step | Expected |
|---|------|----------|
| 3.1 | Device A: take a shot | Balls move on **both** screens. B's table matches A's — same balls pocketed, same final positions. |
| 3.2 | Watch B during the shot | Motion is smooth, not a single jump at the end. (If it jumps, host broadcasts are not getting through mid-shot.) |
| 3.3 | After the balls stop, check turn | Both devices agree whose turn it is. B's controls unlock, A's lock. |
| 3.4 | Device B: take a shot | It is applied on A and rendered on both. This is the client→host direction. |
| 3.5 | Device B: drag while it is **A's** turn | Nothing happens. No shot is sent. |
| 3.6 | Play a full rack to a winner | Both devices show the same winner, with names. Only the host sees **Rematch**. |
| 3.7 | Host taps Rematch | Both tables reset. |

## 4. Losing the connection

| # | Step | Expected |
|---|------|----------|
| 4.1 | Mid-game, force-quit the app on B | A shows "Connection lost" naming B, within a few seconds. A does not freeze. |
| 4.2 | Tap "Back to games" on A | Returns to the game list cleanly. No stuck route, no crash. |
| 4.3 | Repeat, but instead walk B out of range (~30 m or through a wall) | Same overlay on A. |
| 4.4 | Mid-game, turn Bluetooth **off** on B | Both devices show the overlay. |
| 4.5 | After any of the above, start a fresh game | Hosting and joining work again. Nothing is left advertising or connected from the dead session. |

## 5. The awkward cases

These are the ones that find real bugs.

| # | Step | Expected |
|---|------|----------|
| 5.1 | Both devices tap **Host** | Neither finds the other; both time out with "No game found nearby" (they are both advertising, neither scanning). Not a hang. |
| 5.2 | Get a game running with A+B, then a **third** device scans and tries to join A | The third device fails to connect. A and B's game is unaffected — no stutter, no dropped turn. This is single-occupancy (ADR-0009 addendum). |
| 5.3 | Device B joins, then immediately backgrounds the app before the handshake finishes | A reports the failure and returns to a usable state, rather than waiting forever. |
| 5.4 | Start hosting on A, then cancel before anyone joins | A stops advertising: B's scan no longer lists it. |
| 5.5 | Play for 5+ minutes continuously | No slowdown on either device, no growing lag between A's table and B's. |
| 5.6 | Lock B's screen mid-game, then unlock | Either play resumes, or the connection-lost overlay appears. **Not** a silently dead game that still looks playable. |

## 6. What to record

For each pass, note in the PR:

- Both devices (model + OS version) and which hosted.
- Any step that failed, with the console output from **both** devices.
- Whether the host's `droppedFrameCount` climbed during normal play. It should
  stay at zero; a rising count on a healthy link means the two builds disagree
  about the protocol.

---

**A failure in section 3 or 4 blocks the merge.** Sections 1, 2 and 5 failures
are judgement calls — record them as issues if you ship anyway, and say so in
the PR rather than leaving the checklist half-ticked.
