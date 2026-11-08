# Optional native DMX Auto Span

Auto Span is a Peraviz routing policy, disabled by default. GDTF channels,
GeometryReference expansion and effective break identities are resolved first.
MVR Address entries remain the sole standard fixture patch authority. Neither
source XML nor patch entries are changed by the override.

Setup callers can pass an explicit UUID set to the native compiler:

```cpp
peraviz::gdtf_runtime::RuntimeRoutingOptions routing;
routing.auto_span_fixture_uuids.insert(fixture_uuid);
auto compiled = peraviz::gdtf_runtime::compile_runtime_scene(scene, -1, routing);
```

The set belongs to the caller's Peraviz setup configuration. The compiler borrows
it only during compilation; the derived `CompiledRuntimeScene` remains the sole
playback setup authority. Callers must recompile/reinstall through the existing
exclusive setup transaction when changing it, and use the existing mailbox
subscription replacement and held-state replay. The argument defaults to an empty
set. This PR provides the C++ interface only; GUI, Godot configuration binding,
`.pvz` storage, AutoPatch and export are deferred.

Admission requires exactly one effective GDTF break and supported direct Color,
Dimmer, Pan/Tilt or Zoom channel semantics. A lone numbered break still selects its
exact MVR break entry; its number is never added to the physical universe. Explicit
multibreak fixtures remain strict and cannot opt in. Wheel, gobo, shutter and unknown
attribute programs reject Auto Span atomically with an actionable compilation
issue. Existing nested/unresolved reference and malformed patch guards still apply.

For MVR start universe U, start channel C and relative one-based byte offset O,
`A = (C - 1) + (O - 1)` uses 64-bit arithmetic. Each byte routes to MVR universe
`U + A / 512`, channel `A % 512 + 1`. The configured universe offset then determines
the internal Art-Net Port-Address. Every byte is validated before installing any
fixture bindings; addresses outside 0–32767 reject the complete fixture. There
are no boundary gaps and no rollover at the highest universe. Ordered multibyte
sources keep their coarse/fine byte order.

GDTF 1.2's [DMXAddress definition and GeometryReference Tables 48–49](https://github.com/mvrdevelopment/spec/blob/main/gdtf-spec.md)
allow a four-byte absolute address or Universe.Address. Values above 512 are not
intrinsically malformed GDTF. Peraviz's current reference-routing subset still
supports only first-break GeometryReference offsets and diagnoses other valid
forms as unsupported. Auto Span handles the subsequent MVR patch adjustment; it
does not reinterpret explicit breaks or expand that reference-offset subset.

## Native evaluation ownership

Each physical Color target is installed once, retaining its canonical fixture,
geometry and render-target IDs. Its first source universe chooses an evaluation
owner, which is a scheduling context rather than the authority for every input.
The compiled dependency plan uses collision-free physical universe/slot keys for
remote bytes and local slot keys for the owner. Setup binds every ordered byte
directly to its physical held universe frame, and builds physical-universe to
evaluation-owner adjacency. Receiver subscriptions are the deduplicated union of
physical bytes actually required by installed plans, including activation masters.

Submission replaces a physical held frame and marks its precompiled dependent
owners pending. Consumption compares each pending owner's compact input interests
with its previous values and nominates only affected sources and consumers. The
owner evaluates each color target at most once from the latest held values of all
participating universes. Two universes submitted in one coordinator cycle produce
one final target row; packet order is irrelevant. A missing initial universe
contributes zero until its first snapshot; short submitted frames retain the
existing zero/missing-byte behavior. Unchanged input creates no renderer update.

Serial and native worker decoding use the same setup-bound byte views. Worker
jobs still read frozen inputs and write scratch; the native coordinator commits
physical state and complete snapshots. No worker mutates Godot nodes and no new
live lookup dictionary, scene-tree search or allocation is introduced by these
bindings. Existing color cooking, implicit intensity gain, dense presentation,
material emission and Glow policy retain their owners. Renderer refresh consumes
existing authoritative presentation state; scene replacement rebinds views and
rehydrates every subscribed held universe through the normal coordinator.

## Verification boundary

`auto_span_test.cpp` imports synthetic GDTF/MVR ZIPs with sixty Overwrite references
and 180 RGB bytes, verifies contiguous mapping and native renderer-ready Color
rows, reverse packet order, boundary red-to-blue changes, independent co-patched
fixtures, unchanged suppression, subscription replacement/reload, strict multibreak
compatibility, source archive fidelity and Port-Address rejection. Split 16-bit
Color and Dimmer sources verify byte order and final gain/intensity. Existing
native and headless presentation regressions cover the retained renderer paths.
These tests do not establish graphical performance, vendor-wide compatibility,
external hardware timing or full GDTF/MVR conformance.
