# 0003. Host-authoritative state synchronization

Date: 2026-06-12

## Status
Accepted

## Context
Two devices must agree on game state (e.g. where the pool balls are). Running
independent physics on each device diverges due to floating-point
nondeterminism across hardware, causing desync.

## Decision
Use a **host-authoritative** model. One device is the host: it owns and advances
the simulation and broadcasts authoritative state snapshots. The client sends
inputs and renders received state — it does not simulate independently.

## Consequences
Deterministic agreement without lockstep complexity. The host's simulation
carries a determinism test (same inputs → same state). Trade-off: the host bears
the compute and is the source of truth; client-side prediction (if ever needed
for latency) is a separate, later decision.
