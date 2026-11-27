#!/usr/bin/env python3
"""Generate platform icon assets from the existing Peraviz brand artwork and pear."""
from pathlib import Path
import argparse
import shutil
from PIL import Image, ImageDraw, ImageChops

SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)

def app_master(source):
    im = source.convert('RGBA')
    if im.size != (1024, 1024):
        if im.width != im.height:
            raise ValueError('Brand artwork must be square')
        im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    # Only remove the outer black corner pixels; retain the illustrated border.
    mask = Image.new('L', (4096, 4096))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 4095, 4095), radius=320, fill=255)
    mask = mask.resize(im.size, Image.Resampling.LANCZOS)
    im.putalpha(ImageChops.multiply(im.getchannel('A'), mask))
    return im

def export_set(master, target, name, category):
    target.mkdir(parents=True, exist_ok=True)
    images = {s: master.resize((s, s), Image.Resampling.LANCZOS) for s in SIZES}
    for s in (256, 512, 1024):
        images[s].save(target / f'{name}_{s}.png', optimize=True)
    master.save(target / f'{name}.ico', sizes=[(s,s) for s in SIZES if s<=256])
    master.save(target / f'{name}.icns')
    for s in SIZES[:-1]:
        dest = target / 'linux' / 'hicolor' / f'{s}x{s}' / category
        dest.mkdir(parents=True, exist_ok=True)
        images[s].save(dest / f'{name}.png', optimize=True)
    with Image.open(target / f'{name}.ico') as ico:
        assert ico.ico.sizes() == {(s,s) for s in SIZES if s<=256}
    with Image.open(target / f'{name}.icns') as icns:
        assert icns.size == (1024, 1024)
        icns.load()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--brand-art', type=Path, help='Optional exact brand artwork PNG')
    parser.add_argument('--app-only', action='store_true')
    args = parser.parse_args()
    assets = args.root.resolve() / 'assets'
    with Image.open(args.brand_art or assets / 'peraviz_brand_art.png') as source:
        export_set(app_master(source), assets/'icons'/'app', 'peraviz_app', 'apps')
    if not args.app_only:
        project = assets/'icons'/'project'
        with Image.open(assets/'peraviz_icon_1024.png') as source:
            if source.size != (1024,1024):
                raise ValueError('Expected the original 1024px pear icon')
            export_set(source.convert('RGBA'), project, 'peraviz_project', 'mimetypes')
        shutil.copyfile(assets/'peraviz.ico', project/'peraviz_project.ico')
        for s in (256,512,1024):
            shutil.copyfile(assets/f'peraviz_icon_{s}.png', project/f'peraviz_project_{s}.png')

if __name__ == '__main__':
    main()
