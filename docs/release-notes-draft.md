# Peraviz v0.x.x

- Added a production native main-thread dynamic apply batch for large independent open Vector Prism emitters. It preserves individual physical identities, meshes, shaders, culling and exact optical fallbacks while bypassing the per-output GDScript loop; no GPU instancing or draw-call reduction is claimed.
- Corrected the scene-state method parameter that shadowed the public last-loaded file type, preserving the serialized key and project-loading behavior.

- Added adaptive native source/Color calculation batches and a bounded asynchronous completed-snapshot pipeline for large independent non-gobo scenes. Small/shared and temporal gobo workloads keep the exact serial path. Godot polls completed generation-valid data without waiting for workers; scene/renderer retirement preserves held values and safely retires native jobs.
- Corrected two isolated GDScript ownership warnings in scene asset diagnostics and the externally accessed last-loaded file type.

- Added a production compiled serial evaluation plan with dependency-driven target scheduling, shared immutable scalar mappings and instance-local source/ModeMaster caches. Removed repeated source decoding, live ordered-tree nominations and unrelated wheel scans while preserving selected-mode semantics, independent outputs, temporal gobo behavior and the direct native presentation boundary. No new GDTF effects, workers or renderer backend are introduced.

- Connected native DMX evaluation directly to physical composition and Render Group reduction. Live Intensity/Color/BeamOptics no longer make an intermediate Godot round trip; independent Pan/Tilt, wheel and gobo updates retain their sectioned contracts. Reused semantic buffers and dense dirty nominations reduce avoidable allocation while preserving exact physical identities, held replay and renderer generations. Deterministic coverage includes compact and independently controlled 1,000-output workloads; no FPS gain is claimed.

- Corrected dotted GDTF model basenames and standard model-directory lookup, and fitted fixture meshes to declared dimensions without losing embedded GLB transforms or changing MVR object/truss scaling. Preserved partial-fixture representation and added staged, source/model-aware diagnostics with affected-instance counts and visibility/bounds checks after scene activation. Regression coverage now checks actual 3DS/GLB meshes and full application geometry setup.

- Fixed Unicode MVR/GDTF paths and metadata at the native/Godot boundary and native Windows model/XML file access. Extraction caches use ASCII content identities while preserving Unicode resources, shared leases and deterministic cleanup. Model lookup now preserves ZIP entry identity and explicit extensions, rejects ambiguous matches, and reports distinct mesh failures once per asset with scene geometry counts. Synthetic integration coverage now requires actual embedded 3DS/GLB surfaces through scene replacement and unload.

- Fixed PVZ project opening performing saved visual restoration after reporting scene readiness. Saved visual settings and universe offset now precede resource construction; saved receiver startup and original PVZ preference publication remain inside the loading generation. Bulk visual changes rebuild dense groups once instead of once per physical member, preventing repeated global resource recreation for aggregated fixtures.

- Restored coherent renderer-resource installation in one main-thread turn: individual, shared and aggregate bindings finish before rendering can consume an intermediate configuration. Native preparation remains asynchronous; model construction and initial light defaults remain budgeted.
- Hidden fixture inspectors now defer row Controls, and visible tables build eight fixture rows per frame with revision-safe replacement. Finalization phases have distinct labels. Fixed unused-signal/integer-division warnings and added `--peraviz-load-trace` as an alternative to the telemetry environment variable.

- Corrected render-readiness failure propagation and misleading activation completion. Loading now distinguishes activation from final render acknowledgment, defers explicitly for an unavailable window, and fails missing acknowledgments while drawable without publishing an incomplete scene. Opt-in bounded breadcrumbs locate engine-draw versus callback/continuation stalls; the owner Windows first-render blocker remains unconfirmed.

- Split initial graphics activation into batches of at most 16 visual instances, with visible progress, to avoid submitting the full hidden scene at once. Original visibility, transforms, shared resources and DMX generation gating are preserved, including cancellation.
- Fixed premature loading completion: an opaque loading shield now remains over the completed scene during initial graphics submission. Load telemetry distinguishes import chunks from full event-loop/render gaps. Shader/driver stalls during loading remain measurable; headless timing is not a Windows responsiveness guarantee.
- Scene loading now shows animated feedback before preparation, performs CPU parsing/classification in one owned native task, and batches main-thread node/target construction. Phase labels identify the current operation. Partial scenes remain hidden and DMX application waits for registration and actual initial rendered frames; cancellation/reload retires the setup generation.

- Repeated fixtures reuse immutable selected-mode geometry templates and spectral preparation. Native classification and Godot descendant binding use setup indexes; opt-in phase summaries and reference switches support deterministic comparisons. Physical outputs, mechanical transforms and PR #105 aggregation remain unchanged.

- Raised the generic Jolt body capacity to 65,536 so large scenes can retain existing per-mesh fixture-picking shapes (the 250 × 50-emitter generated case exceeded the previous 10,240 limit).

- Fixed false missing-palette rejection from unrelated GDTF ColorMixReset/ColorCalibrationMode controls. Wheel requirements now follow parsed Color selection/motion identity or explicit links; unlinked unsupported ColorEffects retains approximation status, while genuinely unresolved references keep conservative fallback.

- Color-wheel presentation now permits combined shafts for compatible compact emitters, including explicitly approximate Spin/FX behavior, while preserving canonical physical state and control authority. Gobo/projector and incompatible optical dependencies retain individual fallback; unsupported effect fidelity remains explicitly diagnosed. Startup presentation revision is 4.

- Render Group startup diagnostics now distinguish native optical fallback from Godot resource rejection and identify the compact-row extension build. Dynamic Color tracing separates physical composition, reduction and lens RID submission, with a trace-only lens isolation option. Color row ownership uses a setup index, Zoom skips unaffected lens materials, and two GDScript warnings are resolved.

Changes since the previous Peraviz release.

## Highlights

- Added native compact-source Render Emitter Groups: compatible multi-emitter heads retain physical lenses and exact DMX state while rendering one Vector Prism shaft. Aggregates mix independent pixel colors in linear light, keep static origins, use incremental native accumulation and publish renderer-sized payloads. Exact wheel/gobo ownership and one startup summary expose conservative fallbacks; separated cells, bars, divergent emitters and different mechanical lineages remain individual. Shared Control Groups are retained. The owner confirmed approximately 40 FPS with active Color after PR #105 (previously approximately 23 FPS); setup changes do not claim an additional Windows playback gain.

- Added selected-DMXMode presentation Control Groups for compatible open Wash/Spot outputs. Shared Color/Dimmer shaft and source-compatible lens materials avoid redundant renderer mutations while retaining every physical Beam, canonical identity, Color gain, held state and normal Pan/Tilt transform. Wheel/gobo, ambiguous controls, differing scales and explicit realtime/debug light paths remain individual.

- Added a native, target-oriented GDTF runtime for Dimmer, Pan, Tilt, Zoom, physical color, seated color-wheel selection, and bounded static seated gobos.
- Added a reproducible Linux Debug CI workflow covering native, architecture, and headless Godot tests.
- Added native GDTF `Gobo(n)Pos` indexed rotation for a selected gobo, including physical Angle ranges and ModeMaster activation.

## New features

- Added a discreet viewer FPS overlay, enabled by default and sampled four times per second, with a persistent View → Show FPS preference.

- Added continuous selected-gobo rotation for exact GDTF `Gobo(n)PosRotate` controls, preserving signed physical speed, indexed-angle handoff, and smooth renderer-local motion without rebuilding gobo resources.
- Added live comparison of Vector Prism, one auto-sized Shared Haze volume, and Shared Haze with physical gobo shadows without changing resolved GDTF or DMX behavior.
- Added an experimental shader beam proxy with shared low-poly topology, texture-driven gobos, bounded adaptive slice tiers, and screen-depth clipping.

## Improvements

- Corrected Vector Prism profile provenance, bounded FieldAngle support and Zoom diagnostics. Strengthened coherent axial decay, removed accidental double-face/overdrive gain, and normalized gobo contour energy with cached coverage analysis.
- Added generic open Spot/Wash/Fresnel/PC surface-profile data and cached configurable gobo footprint softness. Realtime open lights are an opt-in developer diagnostic; production retains bounded projector/realtime ownership, measured surface-light inventory and independent shaft/surface gains. Scalable open footprints remain deferred.

- Smoothed Vector Gobo Prism shafts with shared BeamAngle/FieldAngle light profiles, optical-distance decay and a zero-energy tail. Removed both artificial end caps, normal-driven intensity bands, opacity floors and the unused depth-texture dependency.
- Added independent shaft and surface intensity controls with project-settings migration, and corrected surface distance attenuation. Gobo footprints share the shaft profile; open circular profile data include fitted native angular attenuation for explicit diagnostic use. Grouped/batched surface-light scalability remains future work.

- Corrected the Vector Gobo Prism artwork X conversion to match the surface projector without mirroring the gobo, while retaining shared optical state and synchronized Zoom/rotation.

- Unified Vector Gobo Prism and surface-projector optical geometry in a shared presentation state. Repeated Zoom and gobo motion now derive absolute bases without cumulative compensation drift; hidden Zoom changes remain synchronized through blackout and held-state restoration.

- Consolidated the stable performance foundation and its current 24–25 FPS reference, while keeping batching, instancing, grouping and further scalability work explicitly deferred. Recorded Vector Gobo Prism visual follow-ups without implementing them.

- Moved physical-output lighting composition and dirty coalescing into bounded native dense state with generation-safe indices and pre-bound renderer handles. Added independent-output allocation/capacity regressions and opt-in compose/adapter/mutation telemetry; the current visual backends remain in use.

- Added bounded interval and explicit lifetime DMX latency statistics, plus opt-in CPU/GPU renderer timing, memory/message-buffer, mailbox and presentation-state size diagnostics for sustained-playback investigations.
- Fixed repeated short-payload warning accumulation and stale scene/presentation caches, proxy identities and native helper Object ownership; added deterministic sustained-DMX and fan-out stability regressions.

- Reduced live DMX renderer-apply overhead with changed-domain commits, final committed-state guards, opt-in accounting, and one physical-output commit per snapshot. Performance tracing is no longer enabled automatically for editor runs.
- Removed trace-only counter and result-allocation work from the production Transform, Intensity, and Color row path, and expanded opt-in color dirty-state diagnostics to distinguish real DMX changes from fan-out and composition no-ops.
- Added one-time physical-output fan-out reporting and a concise warning when diagnostic Shared Haze exceeds the effective Forward+ clustered-element budget.
- Clarified physical-output fan-out with a compact histogram and color-output count, and made presentation diagnostics report the renderer mode that currently owns resources.
- Added opt-in live DMX performance tracing with direct CPU receive-to-renderer-apply latency, truthful interval renderer counters, per-domain timing, and full, transforms-only, and no-beams A/B modes.
- Reduced redundant light, material, beam parameter, and visibility writes while preserving held state for disabled realtime spotlights and later reactivation.
- Coalesced simultaneous intensity and color updates into one renderer commit per physical emitter output, reducing live playback CPU work without merging independently controlled lenses.
- Packed each volumetric beam's live color and intensity into one renderer update, deriving constant brightness response outside per-pixel shader work while retaining dark-beam suppression and physical-output commit diagnostics.
- Correctly treats GDTF BeamType None and Glow as emission-only outputs without projected beam instances.
- Correctly classifies resolved Dimmer updates that already match cached renderer state as unchanged instead of failed.

- Static seated gobos now use reusable normalized vector-prism resources, deterministic open-slot clearing, and cached static multi-wheel mask composition.
- Physical GDTF color evaluation now supports linked emitter/filter resources, CIE, CCT, Tint, additive color, CMY color, and seated color-wheel composition within the documented support scope.
- Beam presentation now uses target-local luminous flux, aperture, angle, Zoom, color, and intensity state without changing imported model scale.
- Added a one-metre reference cube for direct scene-scale checks and reliable Windows x64 Ninja build workflows.
- Indexed gobo angle changes now update reusable presentation resources parametrically without image composition, vectorization, mesh generation, or topology rebuilds.

## Fixes

- Made Peraviz arguments after Godot's `--` authoritative, added explicit startup diagnostic configuration and real resource tests for distinct full/no-beams/transforms-only behavior. Corrected current dense visibility reporting and isolated legacy compatibility telemetry.
- Fixed a dense handle/Callable shutdown cycle reproducing 2,193 leaked ObjectDB instances for 1,095 outputs. Added load/unload/reload and loaded-scene shutdown checks, and removed proven unreachable fixed-row presentation helpers.

- Fixed fresh-checkout script loading by replacing the dense beam cache's global class dependency with explicit preloads. Preserved live light visibility during resource discovery, added explicit dense-install failure handling and real-application beam/footprint lifecycle checks from a clean Godot cache. Windows runs with compilation errors are invalid for performance acceptance; full visual review comes first.

- Corrected conflicting SpotLight Node/RID visibility and missing bound-prism unchanged guards in the native dense presentation bridge. Diagnostic no-beams now suppresses light/beam/gobo renderer work after one cleanup while preserving held state and emissive apertures. Added actual mutation counters and a 1,095-output regression; canonical Windows performance validation remains pending.

- Kept Shader Beam Proxy resources under their active renderer's ownership so ordinary DMX updates no longer hide and immediately reshow them, and made Quick Preset retain its selected value with a clear Custom state after manual edits.
- Enabled directional shadow split blending for smoother cascaded directional-shadow transitions. This isolated option has a moderate cost and does not change spotlight projectors, volumetric fog, or beam rendering.
- Restored crisp surface gobo projection on Godot 4.7 by managing the projector's required shadow state, and prevented Visual Settings refreshes from replacing held beam intensity with zero when optional metadata is absent.
- Corrected fog shader compilation and kept projector and native-shadow spotlight instances active during DMX playback.
- Restored Vector Gobo Prism as the startup reference, rebound native renderer targets after gobo topology replacement, and changed Fog Volume to an analytic local-beam frustum without forcing global haze.
- Replaced the user-facing per-emitter fog experiment with one auto-sized shared haze volume, synchronized native gobo texture and rotation across surface projectors and shadow masks, and removed stale presentation resources during live mode switching.
- Prevented missing optional gobo metadata from flooding the Godot debugger and limited native haze lights to authoritative active physical outputs.
- Kept rotating gobo footprints on the imported optical centerline by composing roll through the emitter basis instead of Euler angles, and made Visual Settings presets scalable through a dropdown.
- Fixture-generated lights now start fail-closed at zero energy before authoritative output arrives, while normal environment daylight and shadows remain independent.

- Corrected vector gobo silhouettes for complex concave artwork, preserved raster cut-outs and nested islands in prism caps and walls, and aligned asymmetric artwork and indexed rotation with the documented source-image convention. Adaptive cached-beam simplification now reduces large curves more aggressively, removes redundant faces and reverse-turn artifacts, and retains small star-field details.

- Prevented beam-optics debug axes from appearing as red shafts during normal playback, stopped Dimmer changes from requesting expensive beam-topology work, and restored beams that first receive a zero Dimmer value before becoming visible.

- Preserved selected gobos and continuous rotation across renderer refreshes, asset updates, and DMX runtime binding rebuilds, so held lighting state no longer requires a new Art-Net value change to reappear.
- Fixed inconsistent continuous gobo rotation and clear/reselect recovery across repeated fixtures by making selection and motion state belong to the physical Beam/wheel layer instead of fixture-derived binding IDs.

- Corrected indexed gobo presentation so asymmetric gobos rotate around the beam axis without tilting, stretching, or changing beam size at intermediate angles.
- Restored live Dimmer, Pan, Tilt, and Zoom installation after the version 7 packed runtime migration, with validated setup decoding and retained version 6 compatibility.
- Restored live native Dimmer, Pan, Tilt, and Zoom updates after the compiled runtime setup contract was extended for future gobo motion.
- Retained extracted GDTF models and gobo media for the active scene so imported fixture assets remain available and repeated fixtures reuse cached content.
- Corrected contradictory zero-transmission color-filter handling while preserving coherent black filters and diagnostics for malformed data.
- Fixed Art-Net startup on Windows when another compatible lighting application already uses UDP port 6454.
- Corrected seated color-wheel selection boundaries, diagnostics, and renderer updates.
- Reduced noisy DMX diagnostics and prevented monitor text from stretching viewer panels.
- Corrected beam aperture, visual length, and multi-emitter brightness behavior.

## Documentation

- Consolidated runtime architecture, GDTF capability, static gobo, build, environment, and coordinate guidance into focused current sources of truth, including unambiguous source, mapped-scene, and renderer-child optical axes.
- Documented the mode-aware physical-output, control-group, and render-group architecture that will guide emitter aggregation, batching, and future beam-renderer performance work without weakening GDTF semantics.

## Internal changes

- Kept native target-application regression coverage aligned with canonical physical-output commit and signature-skip behavior.
- Aligned the native extension with the pinned Godot 4.7 compatibility contract and strengthened test inventory, native-class registration, and headless test validation.
- Added session-owned RAII storage for extracted runtime assets and removed generated Godot editor metadata from version control.
- Added a production-integrated native GDTF gobo scalar contract with exact semantic identities, generic structured mode dependencies, ChannelSet physical ranges, and standards-based node defaults as groundwork for later visible gobo motion.
- Moved live scene playback to native DMX subscriptions, generation-safe dirty-ID handoff, bounded latest-state coalescing, direct native runtime submission, and held-state rehydration without routing raw universe payloads through scripts.
- Corrected ordered ArtDmx sequence validation and receiver-session lifecycle, reduced endpoint work on the receive thread, drained sockets until would-block, and made Technical Monitor payload capture fresh-session, budgeted, and subordinate to scene playback.
