# Live render latency diagnostics

## What is measured

`--peraviz-perf-trace` emits one `[peraviz-perf]` line per second. `rx_apply_us` measures relevant ArtDmx receipt through completion of the Godot scene/resource apply on the CPU. It does not claim render submission or visible GPU presentation latency. `pump_hz` is the number of production pumps during the interval and should normally follow render-process opportunities while DMX is active.

The previous first-frame `rows` diagnostic is the number of section rows in the consumed bootstrap snapshot, not a fixture count or lifetime counter. A Dimmer row is one compiled control target and can fan out through GDTF geometry inheritance to multiple physical output resources. Consequently, 95 controls can legitimately touch roughly one thousand output anchors in the supplied scene. A resolved target whose resources already contain the requested values is now reported as unchanged rather than failed.

## Windows reproduction

1. Run `godot.exe --path . --print-fps -- --peraviz-perf-trace`, load the project, and move Pan/Tilt continuously from grandMA3 for ten seconds.
2. Repeat with `godot.exe --path . --print-fps --gpu-profile -- --peraviz-perf-trace` and retain the `[peraviz-perf]` lines.
3. Optionally repeat with Godot's `--disable-vsync` or a controlled `--max-fps` to distinguish frame pacing from CPU apply age.

A physical GPU trace is required before claiming that beams, Forward+, V-Sync, or the GPU are the remaining bottleneck. RealFade, RealAcceleration, and actuator trajectories remain intentionally out of scope until the immediate pipeline is measured on the affected machine.
