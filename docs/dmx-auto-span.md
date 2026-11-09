# DMX Auto Span project policy

Auto Span is a Peraviz compatibility inference. GDTF channel/GeometryReference
semantics and exact MVR break identities resolve first. Source GDTF/MVR XML,
archives and canonical patch entries remain read-only. Multiple fixtures can
legitimately read the same physical universe and slot; no policy establishes
exclusive DMX ownership or rewrites incoming packets.

## Project settings and behavior

Advanced Settings → DMX contains one **DMX Auto Span** selector:

| Identifier | Label | Behavior |
| --- | --- | --- |
| `off` | Off (strict) | Infer no continuation; retain independently complete supported controls and warn about omitted controls/groups. |
| `auto_safe` | Automatic — only if free | Default for new/legacy projects and ordinary MVR import. Admit the complete continuation only if all required slots are reliably free. Otherwise use strict fallback. |
| `auto_overlap` | Allow overlaps | Admit eligible complete continuations even when overlapping, warn, and let every fixture interpret identical input bytes independently. |

Only `auto_span_policy` is saved in `.pvz`'s existing `dmx_settings.json`.
Missing values default to `auto_safe`; invalid values normalize to that default
with a warning. Reset restores it. PVZ import installs the saved policy before
native preparation; ordinary MVR import starts with the default policy. The
selector is hidden in basic settings and does not appear in the viewer controls.

## Deterministic native planning

`auto_span_policy.cpp` runs only at setup/repatch boundaries. It borrows selected
GDTF modes and authored MVR patches; occupancy is a temporary map keyed by the
actual MVR universe and slot pair, with a set of occupants per slot. For each
break it conservatively reserves the footprint through its highest declared byte,
including holes. Explicit breaks and unsupported-but-known source offsets still
participate in occupancy. Missing/unreliable modes or patches mark their known
universes unknown; unbounded malformed patches conservatively make occupancy
unknown globally. Unknown is never proof of free space.

All candidates and their continuation proposals are collected before admission.
In `auto_safe`, competing inferred continuations all fall back to strict; neither
wins by MVR order. Same-universe co-patching is valid and does not itself deny a
free continuation. `auto_overlap` admits every eligible candidate and preserves
all other fixture bindings. Occupancy never enters transport or evaluation.

New status diagnostics distinguish standard routing, applied inference, denial by
overlap/unknown occupancy, applied overlaps, unsupported modes and strict omission.
Warnings carry UUIDs, original patches, requested continuation ranges, other UUIDs
and actual overlap slots. Details are bounded (256 planning rows, up to eight
slot/occupant examples per fixture); a summary retains aggregate status counts.
Existing nonblocking import diagnostics aggregate warnings rather than opening
modal dialogs. Ordinary deliberate co-patching is not an MVR error.

## Eligibility and strict retention

Auto Span admits exactly one effective GDTF break with supported direct Color,
Dimmer, Pan/Tilt or Zoom semantics. A lone numbered break selects its exact MVR
break entry; its number is never added to a physical universe. Wheel, gobo,
shutter, unknown attributes, unresolved/nested references and multibreak Auto Span
retain existing semantic guards and actionable diagnostics.

Strict fallback is bounded to supported direct scalar/Color modes, including
independent explicit breaks. Any ordered control needing an unavailable byte is
omitted as a whole. Activation dependents are pruned transitively; a Color target
is omitted if any required input is unavailable. Other complete controls and
physical output IDs survive. Explicit Dimmer authority is classified before
pruning, so a missing Dimmer never accidentally grants implicit RGB intensity.
Geometry-only strict fixtures are an intentional warning, not a fatal setup error.
Unsupported temporal/wheel/gobo overflow still uses the existing strict guard;
no partial interpretation of those domains is claimed.

For MVR U.C and one-based relative byte O, the 64-bit calculation remains
`A = (C - 1) + (O - 1)`, universe `U + A / 512`, channel `A % 512 + 1`.
The configured offset converts MVR universes to internal Art-Net Port-Addresses.
Inferred routing outside 0–32767 rejects the fixture with its ordinary error;
there are no boundary gaps or maximum-universe rollover. Strict mode can still
retain complete primary controls at the last universe without inferring overflow.

GDTF 1.2's [DMXAddress and GeometryReference Tables 48–49](https://github.com/mvrdevelopment/spec/blob/main/gdtf-spec.md)
allow absolute/universe-form addresses greater than 512. Peraviz's existing
first-break reference-offset subset remains unchanged: unsupported broader forms
are not intrinsically invalid GDTF and are not generically wrapped by this policy.

## Setup generation and held state

`PeravizLoader.set_dmx_auto_span_policy()` normalizes the identifier. The loader
captures it for native preparation and reuses prepared scene, Control Groups and
Render Groups only when both policy and universe offset match. A policy mismatch
recompiles the complete dependent setup, then follows the existing exclusive
runtime/renderer install boundary. There is one effective playback scene.

A generation-owned immutable selected-mode cache is shared between planning and
compilation and retained by preparation. Policy-only rebuilds reuse that parser
data and media leases; no GDTF archive parsing or source geometry rebuilding is
required. Derived group classification and renderer routes are recomputed together.

The native compiler includes bounded **potential** direct-mode byte interests in
the existing transport subscription, across all three policies. Thus a denied or
disabled continuation can still have its latest valid input held by the mailbox.
These optional `dmx_replay_interests` setup pairs never install a control or give
an input authority; the effective scene alone determines evaluation. They avoid
subscription expansion/stale-byte problems when a policy is changed during hold.
`strict_overflow_retained` marks intentional geometry-only strict setup. Both are
native-generated cold setup metadata alongside the unchanged numeric semantic
contract; neither is persisted in a project or written to source patch fields.

Policy changes keep the receiver running, replace the subscription and rehydrate
physical/material state from its held snapshots without another packet. An input
never received by the receiver cannot be recovered. Render resource replacement
continues through the existing generation/replay path.

## Native playback and setup cost

PR #129's ordered physical byte views, held universe frames, sparse dependency
scheduling, one canonical Color target, native serial/workers/async coordinator
and compact presentation snapshots remain the evaluator. Conflict detection adds
no live fixture scans, occupancy lookups, byte masking, arbitration, GDScript color
calculation or worker-to-Godot mutation. Color cooking, implicit intensity,
material emission and Glow resources keep their existing owners.

Planning time and transient occupancy memory scale with authored/proposed
footprint slots (at most 512 per supported break/fixture), plus occupant identities
for overlaps. Occupancy maps/proposals retire after compilation. Retained memory
adds selected-mode parser cache entries and deduplicated receiver interests, plus
setup-derived potential-byte lists; no occupancy map survives into playback.
Conservative potential subscriptions may retain additional 512-byte universe
mailboxes, including universes that currently have no admitted controls. This is
the bounded cost of no-packet policy replay, not exclusive slot ownership.

## Native setup API and validation

```cpp
peraviz::gdtf_runtime::RuntimeRoutingOptions routing;
routing.policy = peraviz::gdtf_runtime::AutoSpanPolicy::AutoSafe;
auto compiled = peraviz::gdtf_runtime::compile_runtime_scene(scene, -1, routing);
```

The existing explicit UUID set remains an internal intentional override; project
UI uses only the three policies. There is no GUI per-fixture override, AutoPatch,
Align Output, source exporter or Perastage integration in this change.

Synthetic native and headless tests cover actual physical/material outputs,
shared bytes with independent semantics, 30/180-channel fixtures, deterministic
conflicts, strict whole-control omission, ordered 16/32-bit values, source fidelity,
project/default/reset/cache transitions, held loopback DMX, renderer replacement,
and existing serial/native-worker/async paths. These establish no GPU frame-rate,
vendor-wide compatibility, external hardware timing or full standards compliance.
See the [validation record](dmx-auto-span-validation.md) for commands/results.
