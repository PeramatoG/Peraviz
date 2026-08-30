# Realtime DMX runtime

## Standards boundary

The ArtDmx sequence field uses `0x00` to disable sequence ordering. Ordered values use `0x01` through `0xff`, including `0xff -> 0x01` wrap.

Peraviz applies an additional bounded latest-source policy: sequence zero accepts the packet and clears the ordered baseline, so the next non-zero value establishes a new baseline. A numeric IPv4/UDP source change and every fresh receiver start also reseed tracking. For an established ordered stream, forward cycle distances 1–127 are accepted; duplicates and distances 128–254 are rejected as stale. This half-cycle ambiguity policy is a Peraviz operational choice, not a normative Art-Net rule.

## Production scene path

The native visual runtime derives universe and relevant-offset interests from installed `CompiledRuntimeScene` source programs. A setup-time native call publishes those interests as an immutable `RealtimeSubscription`: a 32,768-bit universe membership table plus one 512-bit relevant-slot mask per used universe.

The Art-Net worker records compact metadata for every valid packet without copying or hashing its payload. Unsubscribed universes stop there. Subscribed packets compare relevant slots only and update `RealtimeUniverseMailbox`, which retains at most one held snapshot and one dirty bit per universe. The first valid subscribed payload, including an all-zero payload, initializes state. Bursts overwrite the pending snapshot and increment a coalescing counter.

Once per Godot frame, `PeravizDmxReceiver.pump_visual_runtime()` consumes deduplicated mailbox states and submits their bytes directly to `PeravizVisualRuntimeCore`. Raw universe payloads do not cross GDExtension into GDScript on the production scene path. Godot receives only the compact sectioned visual frame and mutates cached renderer targets.

Active counters distinguish valid, malformed, sequence-rejected, relevant, irrelevant, unchanged, updated, coalesced, monitor-captured, and native-consumed states. Two fixed 32-bucket power-of-two histograms report approximate p50/p95/max RX-to-native-submit and native-submit-to-Godot-apply ages. The production raw-universe bridge byte counter is fixed at zero by the direct native pump contract; diagnostic payload APIs are excluded from that scene-path counter.

Subscription replacement preserves held snapshots when the new relevant mask is identical or narrower. Adding a newly relevant offset invalidates that universe's held snapshot until a fresh valid ArtDmx payload proves all subscribed values. A semantic runtime rebuild reconfigures the subscription and submits proven held snapshots directly to the new native runtime generation, preserving held Dimmer, Pan/Tilt, Zoom, wheel, and gobo state without requiring a changed console value.

## Technical Monitor isolation

Always-on quick status uses compact metadata only. Opening Technical Monitor explicitly enables a separate latest-payload cache for all observed universes; closing it disables further full-payload capture. The diagnostic cache is latest-state only and never feeds or backpressures the scene mailbox. An unrelated universe becomes inspectable only after a packet arrives while capture is enabled.

## Current limits

Compiled setup remains version 7 and the visual protocol remains 2.3. Pan/Tilt still uses immediate physical-degree evaluation in this pass: GDTF `RealFade` and `RealAcceleration`, native actuator trajectories, no-new-DMX physical ticking, and the advisory load generator remain follow-up checkpoints and are not claimed here.
