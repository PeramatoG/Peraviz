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
