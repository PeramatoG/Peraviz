# Realtime DMX runtime foundations

## Standards boundary

ArtDmx sequence `0` disables ordering for that packet. Ordered values use the `1` through `255` cycle, including `255 -> 1`. Peraviz rejects duplicates and values on the stale half of that cycle. A changed UDP source endpoint reseeds the stream. The half-cycle rule is a bounded Peraviz restart policy: forward distances of 1–127 are accepted, while 0 and 128–254 are rejected until a source change or an unsequenced packet is observed.

## Scene subscription and latest-state policy

`RealtimeSubscription` compiles scene universes into a 32,768-bit membership table and each universe's relevant slots into a 512-bit mask. It is immutable after construction and is replaced with an atomic shared-pointer publication. The RX-facing lookup therefore takes no setup mutex.

`RealtimeUniverseMailbox` retains at most one held snapshot and one dirty bit per subscribed universe. The first valid frame initializes the held state, including an all-zero frame. Later frames compare only relevant slots. A burst overwrites the pending state, increments the coalescing counter, and exposes one deduplicated universe ID; consuming dirty state does not erase the held rehydration snapshot. Unsubscribed universes do not allocate mailbox slots or enter its dirty set.

These components are the production handoff foundation, but this pass does not yet connect them to the Godot-facing receiver and visual runtime. Until that coordinator is installed, the existing compatibility cache and raw universe bridge remain authoritative. Monitor payload separation, native Pan/Tilt trajectories, setup contract 8, bridge latency histograms, and the no-new-DMX native tick remain follow-up work and are not claimed here.
