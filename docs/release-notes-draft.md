# Peraviz v0.x.x

Changes since the previous Peraviz release.

## Highlights

- Added a native, target-oriented GDTF runtime for Dimmer, Pan, Tilt, Zoom, physical color, seated color-wheel selection, and bounded static seated gobos.
- Added a reproducible Linux Debug CI workflow covering native, architecture, and headless Godot tests.
- Added native GDTF `Gobo(n)Pos` indexed rotation for a selected gobo, including physical Angle ranges and ModeMaster activation.

## New features

- Added continuous selected-gobo rotation for exact GDTF `Gobo(n)PosRotate` controls, preserving signed physical speed, indexed-angle handoff, and smooth renderer-local motion without rebuilding gobo resources.

## Improvements

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

- Corrected vector gobo silhouettes for complex concave artwork, preserved raster cut-outs and nested islands in prism caps and walls, and aligned asymmetric artwork and indexed rotation with the documented source-image convention. Adaptive cached-beam simplification now removes redundant faces and reverse-turn artifacts from large curves while retaining small star-field details.

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

## Internal changes

- Aligned the native extension with the pinned Godot 4.7 compatibility contract and strengthened test inventory, native-class registration, and headless test validation.
- Added session-owned RAII storage for extracted runtime assets and removed generated Godot editor metadata from version control.
- Added a production-integrated native GDTF gobo scalar contract with exact semantic identities, generic structured mode dependencies, ChannelSet physical ranges, and standards-based node defaults as groundwork for later visible gobo motion.
- Moved live scene playback to native DMX subscriptions, generation-safe dirty-ID handoff, bounded latest-state coalescing, direct native runtime submission, and held-state rehydration without routing raw universe payloads through scripts.
- Corrected ordered ArtDmx sequence validation and receiver-session lifecycle, reduced endpoint work on the receive thread, drained sockets until would-block, and made Technical Monitor payload capture fresh-session, budgeted, and subordinate to scene playback.
