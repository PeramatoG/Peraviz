# Navigation cube: reference and implementation

The behavior was checked against Autodesk's primary AutoCAD documentation:

- [About the ViewCube](https://help.autodesk.com/cloudhelp/2023/ENU/AutoCAD-Core/files/GUID-E6D3896C-AF39-4F5C-A57C-CACE2A1117F9.htm): synchronized orientation feedback, active/inactive appearance and interactive compass.
- [About Reorienting the View](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Core/files/GUID-A90F5F1C-B338-4BDE-9D05-F26BFFE3B3A5.htm): 26 selectable regions, selection-centered pivot, drag, adjacent faces and quarter-turn roll.
- [ViewCube Menu](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Core/files/GUID-3CE31F02-64A5-4BB8-9461-4C4F659C63B7.htm): Home, saved Home and projection modes.
- [ViewCube Settings](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Core/files/GUID-78043EE2-114B-4F08-BFD7-7E5E429708A9.htm): sizing, opacity, drag snapping, view transitions and optional fit/compass.

## Supported interactions

The 136×162 logical-pixel widget is smaller than the first implementation. Its
cube is actual 3D geometry: six large face quads, twelve beveled edge quads and
eight corner triangles. The widened bevel gives the edge and corner targets
more clickable area without enlarging the widget. Picking intersects the same
triangles it renders.
Labels are oriented Label3D nodes, rather than text on a fixed image.

Click faces for axial views, edges for two-axis views and corners for isometric
views. Drag the cube to orbit. It follows ordinary mouse/keyboard navigation as
well, including camera roll. Near a predefined direction, drag release snaps
within 10° when Snap to closest view is enabled. Camera smoothing supplies the
transition; input is consumed by the widget and release outside it is safe.

Cube interactions center the camera pivot on the current selected bounds, or
retain the current view center for empty selection. They rotate the camera;
canonical MVR transforms are never edited. With the existing target-centered
camera, starting a cube action recenters a noncentral selection before orbit.

Click compass letters to view from a cardinal direction; drag its ring to turn
about the world vertical. At top/bottom poles, compass actions use camera roll
so they actually turn the view. On an active axial face, four arrow buttons move
to adjacent faces; two curved arrows roll the camera by ±90°. The scene remains
upright during normal orbit. Explicit face-roll actions can rotate its screen up.

The small bundled Home SVG restores the default isometric fit or a saved Home.
Set current view as Home remembers direction, roll, position, extent, distance
and projection for the current scene/session. Publishing a scene clears it.
Right-click or use the WCS menu for Home and navigation settings:

- Parallel: keep orthographic projection for every direction.
- Perspective: keep perspective for every direction.
- Perspective with orthographic faces: use true parallel projection on face views
  and perspective on angled views (the default).
- Snap after dragging, fit scene after view changes and compass visibility.

The navigation preferences use the existing UserPreferences file. The WCS label
refers to Peraviz's established **Y-up** world; user-defined coordinate frames,
North-direction editing and canonical MVR editing are outside this milestone.
No Autodesk artwork, assets or code are bundled; the behavior is implemented
independently with Godot resources.

## Renderer ownership

`navigation_cube.gd` owns input, menus and camera commands.
`navigation_cube_model.gd` owns only the small mesh model, labels and compass.
A transparent 256×256 SubViewport has an independent World3D and camera. It never
uses the imported scene's World3D, registry, materials, lights or native target
IDs. It requests UPDATE_ONCE for orientation/hover changes and rests disabled;
there is no continuous second render of the MVR. Tests assert world isolation.

This limited widget viewport is intentional to provide the requested real 3D
control. It does not migrate the main scene to a SubViewport or change its camera
references, native renderer resources, project persistence or scene ownership.
The main camera still projects/picks in root viewport coordinates. The tiny UI
texture has a cost; no frame-time or GPU performance improvement is claimed.
