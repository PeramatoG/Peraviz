# Peraviz v0.x.x

Changes since the previous Peraviz release.

## Highlights

- Added a native, target-oriented GDTF runtime for Dimmer, Pan, Tilt, Zoom, physical color, seated color-wheel selection, and bounded static seated gobos.
- Added a reproducible Linux Debug CI workflow covering native, architecture, and headless Godot tests.
- Added native GDTF `Gobo(n)Pos` indexed rotation for a selected gobo, including physical Angle ranges and ModeMaster activation.

## Improvements

- Static seated gobos now use reusable normalized vector-prism resources, deterministic open-slot clearing, and cached static multi-wheel mask composition.
- Physical GDTF color evaluation now supports linked emitter/filter resources, CIE, CCT, Tint, additive color, CMY color, and seated color-wheel composition within the documented support scope.
- Beam presentation now uses target-local luminous flux, aperture, angle, Zoom, color, and intensity state without changing imported model scale.
- Added a one-metre reference cube for direct scene-scale checks and reliable Windows x64 Ninja build workflows.
- Indexed gobo angle changes now update reusable presentation resources parametrically without image composition, vectorization, mesh generation, or topology rebuilds.

## Fixes

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
