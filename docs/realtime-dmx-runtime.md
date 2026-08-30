# Realtime DMX runtime

## Standards boundary

The ArtDmx sequence field uses `0x00` to disable sequence ordering. Ordered values use `0x01` through `0xff`, including `0xff -> 0x01` wrap.

Peraviz applies an additional bounded latest-source policy: sequence zero accepts the packet and clears the ordered baseline, so the next non-zero value establishes a new baseline. A numeric IPv4/UDP source change and every fresh receiver start also reseed tracking. For an established ordered stream, forward cycle distances 1–127 are accepted; duplicates and distances 128–254 are rejected as stale. This half-cycle ambiguity policy is a Peraviz operational choice, not a normative Art-Net rule.

## Production scene path

The native visual runtime derives universe and relevant-offset interests from installed `CompiledRuntimeScene` source programs. A setup-time native coordinator publishes those interests as an immutable `RealtimeSubscription`: a 32,768-bit universe membership table plus one 512-bit relevant-slot mask per used universe.

The Art-Net worker records compact metadata for every valid packet without copying or hashing its payload. Unsubscribed universes stop there. Subscribed packets compare relevant slots only and update `RealtimeUniverseMailbox`, which retains at most one held snapshot and one dirty state per universe. The first valid subscribed payload, including an all-zero payload, initializes state. Bursts overwrite the held snapshot and increment the coalescing counter.

A clean-to-dirty transition appends one generation-tagged universe token to a fixed 32,768-entry ring. Further changes overwrite held state without appending another token. The main-thread coordinator drains only queued tokens, snapshots held data, and clears token ownership under the same short mutex used by publish. A publish before the snapshot is coalesced into that delivery; a publish after it receives a new token. Subscription replacement increments the generation and retires the ring, so removed or re-added universes cannot resurrect stale tokens. Consumer cost therefore scales with dirty universes rather than all patched universes.

Once per Godot frame, `PeravizDmxReceiver.pump_visual_runtime()` calls the pure native `RealtimeDmxCoordinator`, which submits the drained frames directly to `PeravizVisualRuntimeCore`. Raw universe payloads do not cross GDExtension into GDScript on the production scene path. Godot receives only the compact sectioned visual frame and mutates cached renderer targets. The removed `get_dirty_universes`, `consume_universe`, and changed-frame compatibility APIs are not production alternatives.

Subscription replacement preserves held snapshots when the new relevant mask is identical or narrower. Adding a newly relevant offset invalidates that universe's held snapshot until a fresh valid ArtDmx payload proves all subscribed values. A semantic runtime rebuild reconfigures the subscription and submits proven held snapshots directly to the new native runtime generation, preserving held Dimmer, immediate Pan/Tilt, Zoom, wheel, and gobo state without requiring a changed console value.

## Technical Monitor isolation

Always-on quick status uses compact metadata only. Opening Technical Monitor starts a fresh payload generation: previous-session payloads immediately become unavailable, and a universe appears only after a packet arrives in the new session. Closing the window disables full-payload capture; traffic received while closed cannot populate the next session.

Scene sequence, metadata, and mailbox work always happens before diagnostics. `MonitorCaptureBudget` permits at most four full cache copies/hashes per socket drain wake and at most one capture per millisecond globally. Further valid packets increment `monitor_payload_skipped_budget` and continue through cheap metadata/scene processing without diagnostic payload work. The cache is latest-state only and has no packet queue. Under pressure, Technical Monitor fidelity degrades while the receiver continues draining scene traffic.

## Counters and latency

Receiver statistics distinguish received datagrams, valid parsed ArtDmx, accepted ArtDmx, malformed packets, sequence rejection, relevant/irrelevant packets, unchanged relevant packets, mailbox updates/coalescing, dirty states consumed, monitor captures and budget skips, drain wake count, and maximum datagrams drained in one wake. `overload_dropped` remains a deprecated zero-valued UI alias and does not claim packet loss. `frames_written` is a deprecated alias of `valid_artdmx_accepted`.

Two fixed 32-bucket power-of-two histograms report approximate p50/p95/max RX-to-native-submit and native-submit-to-Godot-apply ages. The production raw-universe bridge byte counter is zero by the direct native coordinator contract; diagnostic payload APIs are outside that scene-path counter. Visual-runtime statistics continue to report generated section rows by domain.

## Advisory load harness

Build native tests, then run:

```bash
native-build/peraviz_native_visual_runtime_tests --benchmark <relevant-universes> <unrelated-universes> <burst> <iterations> <monitor-off|monitor-on>
native-build/peraviz_native_visual_runtime_tests --udp-benchmark <unrelated-packets> <relevant-burst> <iterations> <monitor-off|monitor-on>
```

The harness uses the production subscription, mailbox, coordinator, visual runtime, monitor cache, and capture budget. Correctness assertions verify latest-only bursts, unchanged suppression, one dirty delivery with thousands of patched universes, and monitor degradation. Timings are engineering observations, not CI thresholds.

Observed in the August 2026 Linux container using a release-unspecified local CMake build:

| Scenario | p50 pump | p95 pump | max pump | Relevant / irrelevant | Coalesced | Monitor captured / skipped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 relevant, 2,000 unrelated, burst 1,000, 100 iterations, monitor off | 1 us | 4 us | 16 us | 100,100 / 200,000 | 99,900 | 0 / 0 |
| 256 relevant, 2,000 unrelated, burst 1,000, 100 iterations, monitor on | 2 us | 38 us | 47 us | 100,100 / 200,000 | 99,900 | 200 / 199,800 |
| 4,096 patched, one dirty per iteration, 100 iterations | 1 us | 3 us | 16 us | 10,100 / 0 | 9,900 | 0 / 0 |

The actual UDP/ArtDmx scenario with 1,000 unrelated datagrams plus a 100-packet relevant burst for 20 iterations received and accepted all 22,000 datagrams in both runs. Monitor-off RX-to-native was 1,243 us p50 / 1,369 us p95 / 1,380 us max; monitor-on was 1,233 us / 1,333 us / 1,995 us and deliberately retained 73 of 22,000 diagnostic payloads. These scheduler-sensitive numbers are advisory; the deterministic assertions require the final relevant state, exact mailbox coalescing, and bounded diagnostic loss, not a latency threshold.

## Current limits

Compiled setup remains version 7 and the visual protocol remains 2.3. Pan/Tilt remains immediate physical-degree evaluation. GDTF `RealFade` and `RealAcceleration`, native actuator trajectories, and no-new-DMX physical ticking are intentionally deferred to the next coherent branch.
