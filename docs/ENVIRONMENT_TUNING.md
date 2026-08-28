# Viewer environment baseline

`test.tscn` provides the source visual baseline. `DayNightEnvironmentController` owns runtime sky, ambient, and directional-light state, while Visual Settings exposes renderer and environment controls.

## Default state

The checked-in scene uses the Day preset with continuous cycling and automatic advancement disabled. Its durable comparison baseline is:

- ACES tonemapping with white point `8.0`;
- neutral background `Color(0.129412, 0.137255, 0.156863)`;
- neutral ambient color with energy `0.08` and no sky contribution;
- SSAO enabled at intensity `0.5`;
- glow and volumetric fog contribution disabled;
- image adjustment enabled with contrast and saturation `1.05`.

These values are renderer presentation settings, not GDTF photometric semantics. Apparent brightness also depends on fixture output, beam angle, distance, surface response, haze, and camera composition.

## Environment controls

Visual Settings can enable the controller, select Dawn, Day, Dusk, Night, or BlackoutNight, or use the normalized continuous cycle. Automatic cycle advancement is opt-in. It also exposes directional-light strengths, day/night ambient energy, horizon controls, and blackout permission.

For technical comparisons, keep the same preset, tonemapper, framing, fog, and visual multipliers. Record any deviations with the comparison. Use artistic presets only after validating fixture behavior against a fixed environment.
