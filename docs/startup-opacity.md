# Opaque startup splash

The startup card uses the same root Window as the Viewer. The transparent
version introduced on 2026-11-26 enabled global per-pixel transparency before
Vulkan initialization. The owner reproduced desktop leakage through the main
3D sky on two Windows computers and confirmed that bypassing the splash and
disabling transparency removed it.

Godot 4.7.1 selects Vulkan swapchain composite alpha using the global
per-pixel transparency permission. Switching off Window.transparent later is
not a reliable substitute for disabling the permission before startup.

Keep the 222 x 268 borderless card opaque, preserve the 1366 x 768 Viewer
reference viewport, and keep Forward+ / Vulkan as the Windows preference.
Restore normal decorations, resizability and maximized mode at handoff.
The navigation cube's independent transparent SubViewport and optical
material alpha are unaffected. The splash does not need another process.

## Validation

The headless test `tests/gdscript/test_startup_opacity.gd` checks the global
settings, initial viewport opacity, splash panel style and dimensions.
It does not validate the native Windows compositor or graphical handoff.

Windows manual checklist (Godot 4.7.1, matching export templates):

- Remove any diagnostic override.cfg from the exported app directory.
- Start the exported application normally; confirm the branded rectangular,
  borderless card appears and the decorated, resizable maximized Viewer follows.
- Confirm the console reports forward_plus and vulkan on supported hardware.
- Place a high-contrast application behind Peraviz; check Day, Dusk, Night
  and Blackout Night, before and after loading MVR/PVZ.
- Restore, maximize, minimize, move between monitors and test DPI scaling.
- Confirm the navigation cube, transparent scenery, beams and haze still work.
- Verify no stretched splash or unexpected always-on-top state remains.

Real Windows graphics validation is pending; no Godot upgrade is included.

## Main window sizing follow-up

After the opacity fix the owner observed the Viewer remaining at the splash
size. The editor's embedded game host owns its dimensions and cannot be
resized by the project. Keep Viewer-sized default overrides for editor runs;
only export templates start at 222 x 268. A standalone editor run still
shrinks to the splash size from its startup script; the initial dark boot
frame may be larger. Embedded and headless runs keep their existing native
window-operation bypass.

For native runs restore normal flags and a monitor-fitted windowed rectangle,
mount the Viewer, then reapply the normal size and maximize on subsequent
frames. Check the actual native client dimensions; if still too small,
restore a usable windowed rectangle once rather than forcing fullscreen.
The startup log reports the resulting mode and client size. No change to
transparency settings or the independent F11 presentation mode.

Manual validation: test an exported Windows build and a non-embedded editor
run; check the compact splash, decorated maximized main window and the normal
restore size. Test the editor's embedded run separately (host-controlled size).
Test a smaller monitor, a secondary monitor and non-default DPI. Headless
checks cover configuration, rectangle calculation and splash-size detection,
not native window-manager behavior.

## Native handoff and startup timing

Keep the compact opaque card visible while the Viewer is instantiated,
mounted and initialized. Managed startup yields between phases; direct and
headless scene loads retain synchronous setup. The previous native sizing and
opacity fixes are retained. Explicit PVZ and remembered-file requests are
released once after normal-window draw feedback (or a bounded timeout).
No extra process or global transparency is used.

Use the `[PeravizStartup]` log lines to compare initial dimensions, resource
readiness, instantiation, mount, initialization phases and compact/normal
draw waits. These are wall-clock observations, not GPU profiling. Engine boot
before splash `_ready()`, child `_ready()` calls, shader compilation and
individual expensive operations may still block. Headless tests verify phase
ordering and the file-release gate, not native presentation. Test cold/warm
installed Windows launches with and without a remembered project; confirm
the compact card remains visible until handoff, native UI responds and the
normal Viewer is usable. Do not alter Vulkan or opacity to mask startup latency.
