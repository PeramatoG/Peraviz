# Peraviz application and project icons

The app icon uses the supplied framed gold pear and stage lighting artwork. The project icon is the original isolated yellow pear. Original brand art and splash are unchanged.

- Application: `app/peraviz_app_{256,512,1024}.png`, `app/peraviz_app.ico`, `app/peraviz_app.icns` and Linux hicolor PNGs.
- Project: `project/peraviz_project_{256,512,1024}.png`, `project/peraviz_project.ico`, `project/peraviz_project.icns`. Run the generator to produce the remaining Linux MIME icons.

The uploaded application icons are canonical; their Git blobs were moved without changing bytes. To regenerate, use the exact supplied brand image (not necessarily byte-identical to the repository brand art):

```sh
python -m pip install Pillow
python tools/generate_peraviz_icons.py --brand-art PATH_TO_PNG
```

## Windows

Godot and Inno Setup use the application ICO. Windows packaging stages the separate PVZ ICO as a real filesystem resource. The installer displays the repository GPL-3.0 license, follows the Windows light/dark setting (Inno Setup >= 6.6), and registers .pvz per-user without overriding Windows UserChoice or another existing handler. MVR associations remain untouched.

File-open contract: `Peraviz.exe -- --open-project "C:\\Shows\\Example.pvz"`. Explicit file-open requests take priority over restoring the last file and use the existing PVZ loader. Malformed requests do not load a different project.

## Verification before release

Run Windows package CI and startup tests. Install on Windows 10/11 with light and dark modes; verify setup, executable, taskbar, desktop shortcuts, GPL page, PVZ icon and double-click on a valid project with spaces/non-ASCII characters. Test missing/corrupt project, last-project restoration precedence, upgrade and uninstall; confirm .mvr and other handlers remain unchanged. Linux/macOS packaging and associations remain future work.
