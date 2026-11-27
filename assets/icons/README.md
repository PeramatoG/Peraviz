# Peraviz application and project icons

The app icon is derived directly from the framed gold pear and stage lighting brand art. The project icon is the existing isolated yellow pear. Keep both identities separate; never overwrite the original brand or splash.

## Generate platform files

Install Pillow and run:

```sh
python -m pip install Pillow
python tools/generate_peraviz_icons.py
```

For the exact externally supplied artwork, use `--brand-art PATH_TO_PNG`. The supplied PNG and repository PNG have different Git blob hashes, so pixel equivalence is not yet confirmed. The script preserves the artwork and applies only an antialiased exterior corner mask. It produces ICO, ICNS, PNG masters, and hicolor PNG files for both identities. The original project PNG and ICO files are copied byte-for-byte.

The new app binary assets from the supplied artwork still need to be added to this branch. Existing runtime settings are deliberately unchanged until the new app binaries are present.

## Follow-up integration

- Godot: application icon and Windows native icon must reference the new app assets.
- Windows: update both export icons and installer setup icon. Install the separate project ICO and register .pvz with it after verifying command-line file opening.
- macOS: app ICNS for the bundle, project ICNS for the document type and UTI.
- Linux: hicolor apps/mimetypes with matching desktop and shared-mime-info metadata.
- Keep brand art, splash, MVR/GDTF and native PVZ format unchanged.
