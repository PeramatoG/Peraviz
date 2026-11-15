# Application UI and editing handoff

## Layout and interaction

`test.tscn` remains the production entry scene. At the end of the application's
initialization, `AppShell.configure()` resolves the existing controls and mounts
the application layout. The existing controllers retain their instances and
signals when their tools move to optional child windows. No MVR or renderer
resource is recreated for layout changes.

The shared theme is `scripts/ui/application_theme.tres`, with pure-black panels,
white text and amber/yellow/orange focus and selection. Confirmed Art-Net packet
reception uses pure green; listening uses amber, stopped uses gray, and errors
use pure red. Status labels remain explicit, independently of color.
`ui_palette.gd` supplies the matching presentation/status constants. Original bundled SVG
icons in `assets/ui` use the repository MIT license and need no runtime network.
The left Scene Explorer starts at 270 logical pixels, the contextual Inspector
at 320. Drag either divider to resize. The toolbar and View menu independently
toggle panels. Tab hides tools and restores the previous panel choices. The
application toolbar always remains available. Reset Layout restores both panels
and their default widths. Below 1200 logical pixels the Inspector temporarily
collapses; its preference and width remain available when the window expands.
View offers 100%, 125% and 150% UI scale, stored in UserPreferences.

| Action | Shortcut / gesture |
| --- | --- |
| Open MVR or PVZ | Ctrl+O |
| Save PVZ | Ctrl+S |
| Hide / restore tools | Tab, or toolbar icon |
| Nonexclusive fullscreen | F11, or toolbar icon |
| Leave fullscreen, then hidden tools; otherwise clear selection | Escape |
| Select | Left click; Ctrl-click adds/removes |
| Frame selection, or fit scene if empty | F |
| Fit entire scene | Shift+F; double middle-click; default cube Home |
| Orbit | Right drag; Shift+middle drag; drag the navigation cube; arrow keys |
| Pan | Middle drag, Shift+right drag; Shift+arrows |
| Zoom | Wheel; Alt+arrows |
| Front, side, top view | Keypad 1, 3, 7; navigation cube faces |
| Reset orbit / restore Home | Keypad 5 resets orbit; cube Home restores its saved/default view |
| Projection mode | WCS / cube context menu: Parallel, Perspective, or Perspective with orthographic faces |
| Edge/corner views | Click cube edges/corners (26 available directions) |
| Roll / adjacent face | Arrow controls shown over an active face view |
| Save Home | Cube context menu → Set current view as Home (current scene/session) |
| Coordinate diagnostics (explicit diagnostics session) | C |

Left drag no longer starts orbit: a selection click must not capture the mouse
or change the camera. Right-drag orbit and middle-drag pan retain their existing behavior; Shift+middle
adds CAD-style orbit. Cube clicks and drags are consumed by the widget and never
select scene objects or capture the mouse. Releases outside the widget are safe.
The compass and WCS label refer to the existing Godot Y-up world frame; this does
not introduce a second coordinate system. Cube Home restores an isometric
perspective and fits the scene. Pole views are exact, with a stable camera up
vector. Orthographic wheel zoom adjusts extent, and projection changes preserve
the unobscured viewport center. The compact cube is a real beveled 3D model with separate ray-selectable meshes
for its 26 surfaces. Its isolated 256×256 SubViewport contains only that model,
3D text and compass, never the imported MVR world. It redraws on orientation or
hover changes and rests with updates disabled; the main scene is not duplicated.
Inactive opacity, compass letters/ring, saved Home, snap-after-drag and three
projection modes follow the documented CAD behavior. Top/bottom compass turns
use camera roll, since yaw at a pole cannot rotate the scene. Camera projection,
compass visibility and snap/fit preferences extend UserPreferences; Home is
session-scoped and resets on scene publication. See [navigation cube](navigation-cube.md)
for the source references, precise behavior and ownership constraints.
Text editors and search inputs shield application/camera shortcuts. Child
windows and popups receive Escape before the main shell. Fullscreen hides the
entire application UI, FPS and auxiliary windows, leaving only a small exit icon
at the top right. Escape, F11 or that icon restores the prior window mode,
position, size, panel choices and visible tool windows. Transient menus stay
closed. Camera navigation remains available; hidden UI shortcuts stay inactive.
The viewport action strip uses matching outlined icons and descriptive tooltips.
Move and Rotate remain disabled with future-editing tooltips.

Names and Fixture IDs identify objects in normal use. UUIDs are hidden in the
Inspector and explorer tooltips by default. Tools > Show object UUIDs exposes
them for technical work and remembers that explicit preference. UUID search
remains supported without exposing identifiers in the ordinary interface.

Art-Net start/stop is always in the main toolbar, beside the receiver state.
Stopped, listening and receiving are distinct. Tools offers DMX connection
controls, the existing technical monitor, MVR-xchange, and fixture diagnostics.
The existing scale cube and optional FPS are in View. FPS appears in amber at
the right of the bottom status bar, outside the viewport toolbar. It defaults
off only when no explicit choice was saved. Visual Settings keeps Graphics and Beams,
Environment, Fake Smoke, Geometry and explicit advanced diagnostics/DMX policy;
serialized settings and Reset still use their existing project ownership.

## Selection and viewport contract

`SceneSelection` is the sole application selection state. Its `ids` contain
stable imported IDs, normally canonical MVR UUIDs. It borrows the application's
published node index and derives reverse node identity at scene publication.
`SceneRegistry` remains the fixture/anchor authority. Explorer TreeItems are a
presentation of the actual reconstructed node parents, not a second editable
MVR graph. Internal GDTF/geometry shells are omitted from the explorer. Source
layers are not emitted as nodes by the current native parser; the explorer
preserves the hierarchy exposed by that parser, including GroupObjects.

`changed` updates the explorer, the one read-only contextual inspector and a
bright amber geometry overlay with a yellow/orange silhouette. Manual fixture diagnostics read/write the same
selection and only apply manual values when the user enables manual testing.
Scene retirement clears selection before target destruction. The inspector
handles zero, one or many objects and does not allocate a property grid for
every imported fixture. Missing GDTF and unbound fixtures remain inspectable.

The main root viewport, World3D, camera and native RenderingServer owners remain
unchanged. The existing Control is the unobscured navigation rectangle, not a
new SubViewport. Camera framing uses its available fraction of the root viewport;
the camera translation makes the orbit target project into that rectangle's
center. Picking and highlighting use root-viewport pixels and the same camera.
Opaque UI covers the rest of the existing render. This intentionally avoids
MVR viewport textures, duplicate scene rendering and a native resource migration; it does
not claim reduced GPU work for pixels behind panels.

Fixture picking reuses existing colliders. Non-fixture trusses/SceneObjects use
on-demand cached world model AABBs, retired with the scene. These are conservative
bounds, not exact triangle hits: empty spaces inside a complex model's box can
select it. This is an explicit limitation for the preview. GroupObjects select
through the explorer. Bounds for framing exclude runtime light/shaft subtrees.
The selection highlight shares only the selected source meshes and draws an
unshaded amber fill plus a screen-space inverted-hull outline. It creates no
bounding box and does not change original materials, material overlays, native
lens admission, photometry, shadows or project settings. Separate highlight
instances live outside imported geometry. Nonvisual RemoteTransform3D links
follow source and ancestor motion through engine notifications, without a
GDScript per-frame traversal. Source visibility signals keep native-hidden lenses
hidden. This preserves the native lens admission rule forbidding visual children
under source meshes. Overlapping group/fixture selections deduplicate sources;
light/beam subtrees are excluded. LOD cache `meshes_changed` refreshes shared
geometry on explicit quality changes. Deselect, source retirement and scene
reload remove links/overlays. The extra selection-only draw passes scale with
selected geometry; no GPU speedup is claimed.

## Preferences and runtime cost

All new layout values extend `user_preferences.cfg`. `sidebar_open` is retained
as the Explorer preference so old explicit choices migrate directly. Existing
advanced mode, module choices, visual settings tab and FPS choice are retained.
Missing new fields gain defaults. Layout and UI scale never enter MVR or PVZ
fixture definitions. Selection and packet data are transient.

No panel toggle scans the scene, changes the native runtime or recreates
resources. Scene publication creates lightweight TreeItems; only search changes
scan those items. Binding/unbound row lookups are indexed at setup to keep
explorer label population from adding repeated linear fixture scans. Live DMX
updates neither reconstruct the hierarchy nor refresh inspector rows. Selection
highlighting uses shared materials/meshes and engine transform notifications;
only the isolated navigation widget requests a tiny redraw when orientation or hover changes. No general
floating dock framework or permanent empty lower tool panel was introduced.

## Initial audit and cleanup

The audit covered project.godot/test.tscn, load_scene, AppShell, UiController,
FixtureDebugController, DmxController, fixture inspection, quick DMX panel,
MVR-xchange panel, status presenter, visibility policy, preferences, FPS, scale,
geometry controls, DMX monitor, editor camera, visual settings/panel scripts,
SceneRegistry and FixtureRowProvider. Reference searches also included runtime
bridges, scene resources, GDScript/integration tests and CI workflow scripts.

| Candidate | Classification and disposition |
| --- | --- |
| `test.tscn` | Production startup; preserved. All original controller NodePaths resolve before controls are mounted into the new shell. |
| Old fixture GridContainer | Superseded; removed eight Labels per fixture and asynchronous row-builder state. Readiness tests now assert constant inspector node count and cancellation contract. |
| AppShell section registration and load_scene section bridges | No callers in scripts, scenes, native sources, tests or CI; removed registration dictionaries/methods and dead wrappers. |
| Unused side-panel/DMX setup bridge wrappers | No callers found; removed. The actual controller host and setup methods remain. |
| `test.gd` / UID | Unreferenced legacy HelloWorld/HUD ping experiment; removed after repository reference search. |
| Native HelloWorld | CI `.github/scripts/check_native_extension.gd` still checks its registration; retained. |
| Manual test, fixture sliders and shutter trace | Useful diagnostics; retained in Tools > Diagnostics. No longer own ordinary selection. |
| Coordinate gizmos | Useful developer diagnostics; retained behind explicit debug policy and C shortcut. |
| Gobo debug controls | Retained in advanced Visual Settings; not shown in basic settings. |
| DMX monitor, packet/tick counters, universe offset | Production connection settings and useful technical diagnostics; optional Tools windows. |
| MVR-xchange | Production discovery/join/update; its existing controller and panel are retained in an optional window. |
| Scale reference | Production view helper; retained, View menu. |
| FPS | Optional diagnostic; retained, defaults off for unsaved preferences. |
| Performance trace, model reports, renderer investigation presets | Developer/regression infrastructure; preserved. Experimental renderers still require `PERAVIZ_DIAGNOSTIC_RENDERERS=1`. |
| Multiple permanent badges | Consolidated to receiver state plus bottom scene status; other values remain in status tooltip. |
| Legacy module preference keys/visibility policy | Retained for migration and existing callers; no destructive deletion based solely on uncertain usage. |

No native semantic, parser, protocol, runtime or writer code changes are part of
this UI implementation. Import performance investigations remain out of scope.

## Next milestone: MVR document editing

Connect editing commands to `AppShell.selection.ids` and the inspector's
selection-change boundary. Add an explicit document command/undo service owned
by the next milestone; controls must issue validated native/document operations,
refresh affected published rows and persist through the official archive/export
path. Do not mutate the node transform or create a parallel patch authority as
a shortcut. Current Inspector controls intentionally expose no editing action.

Standard per-fixture Pan/Tilt inversion belongs to **MVR**, via optional boolean
`DMXInvertPan` and `DMXInvertTilt` Fixture children. The current
`SceneModel::FixturePatch` and Godot bridge expose neither flag; the Inspector
reports unavailable metadata instead of inventing false values. Follow-up points:

1. `native/src/mvr_scene_loader.cpp::parse_fixture_patch()` reads Fixture children;
   add optional/known flags to `native/src/scene_model.h::FixturePatch` there.
2. Carry the flags through the loader/compiled setup contracts, with versioned
   codec tests and Perastage-neutral semantics. Do not edit GDTF ChannelFunctions;
   the former GDTF `DMXInvert` attribute was removed in GDTF 1.0.
3. Integrate at native selected-mode source evaluation in
   `native/src/runtime/visual_runtime_plan.cpp` and
   `native/src/runtime/visual_runtime_evaluation.cpp::read_raw_value()` /
   `evaluate_source_program()`, before normalized/physical mapping. Audit both
   cached/serial and parallel-prefetch callers, then the Pan/Tilt application
   cases in `native/src/runtime/peraviz_visual_runtime.cpp`. Preserve source bit depth,
   mode guards and qualified component ownership. Invert resolved DMX values
   before physical evaluation; do not negate final Godot angles.
4. Implement safe MVR writing/export, undo, reload and mixed multi-selection
   semantics together with the editing foundation, then enable corresponding
   inspector actions. A future Peraviz-only visualization correction must have
   a different explicit name and must not impersonate these MVR flags.

Patch/mode mutation, transforms, multi-edit commands, inversion evaluation,
writing/export and general docking are intentionally deferred.

## Windows manual release checklist

Run with Godot 4.7.1 and the matching extension. Repeat at 1366×768, 1920×1080
and 2560×1440, with Windows DPI 100%, 125%, 150% and both monitors if available.

1. Start with a clean preference file; check debug tools/FPS are absent. Open a
   small MVR, a large MVR, one with missing GDTF and then a saved PVZ. Confirm
   patch/mode, geometry and project visualization restoration.
2. Resize both panels, hide each independently, use Tab twice, restart, reset
   layout, resize narrow/wide and change UI scale. Confirm no blank dock space,
   reachable toolbar controls, remembered widths and no preference overwrites.
3. Search UUID/name/fixture ID, select different object kinds, Ctrl-select,
   click empty viewport, frame selection, fit scene and replace the MVR. Check
   explorer/inspector/highlight sync and safe stale-selection retirement.
4. Orbit/pan/zoom, drag dividers and type F/C/Tab in search and number inputs.
   Confirm no selection click rotates the camera or UI drag moves it.
5. Enter/leave F11 from windowed and maximized modes, with panels hidden/shown.
   Check that only the exit icon remains, including with open tool/file windows.
   Exit using Escape, F11 and the icon; confirm windows, FPS, panel widths and
   prior Hide Tools choices restore correctly.
6. Start/stop Art-Net, send real packets, inspect universes and native traces;
   verify stopped/listening/receiving states, shutter/strobe, temporal playback
   and responsiveness with inspector open, hidden and fullscreen.
7. Discover/join/update a real MVR-xchange station; save/reopen PVZ and verify
   visual settings, Reset and session preference behavior.

Linux headless assertions do not establish Windows DPI, window-manager behavior,
real network discovery/hardware reception, GPU equivalence or large-MVR timings.
See validation evidence for the commands actually executed.
