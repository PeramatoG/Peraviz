# Beam rendering modes

Peraviz exposes two presentation modes in Visual Settings. Renderer choice does not change native GDTF or DMX interpretation.

## Modes

- **Volumetric (default):** a full cone with shader-projected shaping for haze shafts, distance attenuation, soft end fade, and selectable Low, Medium, or High quality. Low removes turbulence and reduces raymarch work.
- **Lightweight:** a lower-cost cone/prism path intended for dense scenes or limited GPUs. The name is a renderer mode, not a legacy semantic authority.

Both modes are children of the rotated `SpotLight3D` renderer anchor and extend along that anchor's local `-Z`. This renderer-child direction corresponds to mapped emitter-local `-Y`, which in turn represents official GDTF Beam source-local `-Z`. These axes are related but are not interchangeable local spaces; see [Coordinate system and transform validation](COORDINATE_SYSTEM.md).

The cone/prism mesh is authored on its own local Y axis. A +90-degree X rotation places the mesh's near `+Y` endpoint at the light origin and its length along renderer-child-local `-Z`; mesh translation then extends it from the lens by the configured visual range. Optical rotation and gobo presentation are applied in renderer-child space, without changing the official GDTF source-axis semantics.

## Shared renderer parameters

The renderer-facing optics contract includes beam angle, visual range, selected near aperture, lens/near offsets, lens shift, softness, radial and longitudinal falloff, intensity, and haze density. Setup-time native Beam profiles preserve official GDTF Beam geometry fields; live native Zoom rows update the physical full angle and normalized position for the exact Beam target.

Beam radius and angle are optical inputs. Visual beam length is a Peraviz presentation choice and is not a GDTF physical property. See [Beam geometry and visual length](BEAM_GEOMETRY_AND_VISUAL_LENGTH.md).

Lightweight Prism reuses a normalized mesh and mutates per-instance near/far parameters. Circular Beam types use circular topology, Rectangle uses `RectangleRatio`, and None/Glow do not create a projected custom beam. Official BeamRadius, measured model aperture, and the selected visual near radius remain distinct diagnostic values.

## Gobo presentation boundary

The authoritative supported gobo semantics are defined in [GDTF gobo control](GDTF_GOBO_CONTROL.md). For the bounded static seated case, registered masks can provide a vectorized Lightweight prism topology or a shader mask. Renderer orientation and masking are presentation compatibility details, not semantic support for rotation, shake, wheel spin, or moving multi-wheel composition.

Volumetric mode keeps a full cone to avoid discontinuous shaft geometry. Shader masks sample outside their UV domain as closed rather than stretching edge pixels. Any visibility floor or contribution blend is a renderer tuning safeguard and must not be described as official gobo transmission.

## Performance and tuning

- Prefer Volumetric Low for integrated GPUs and increase quality only after measuring frame time.
- Prefer Lightweight for maximum throughput or large fixture counts.
- Reuse meshes, materials, masks, and registered targets; do not rebuild them per DMX frame.
- Keep spotlight footprint projection optional. It is not an authoritative gobo-motion path.
- Treat beam intensity, haze, softness, and falloff controls as Peraviz visual tuning, not GDTF semantic values.

Current limitations include advanced photometry, Focus, Iris, Frost, prisms, shutters, gobo motion, and high-quality volumetric rectangular rendering. Consult the [GDTF support matrix](gdtf-support-matrix.md) before expanding that list.
