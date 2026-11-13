#!/usr/bin/env python3
"""Generate two public RGB Glow fixtures whose inferred continuation deliberately overlaps."""
import sys
import zipfile
from pathlib import Path
from generate_rgb_strip_fixture import generate


def generate_policy_fixture(output: Path) -> None:
    generate(output)
    with zipfile.ZipFile(output) as archive:
        gdtf = archive.read('strip.gdtf')
    scene = '<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList>'
    for identity, patch in [('strip', '1.511'), ('other', '2.9')]:
        scene += (f'<Fixture uuid="{identity}" name="{identity}"><GDTFSpec>strip.gdtf</GDTFSpec>'
                  f'<GDTFMode>RGB_180ch</GDTFMode><Addresses><Address>{patch}</Address></Addresses></Fixture>')
    scene += '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml', scene)
        archive.writestr('strip.gdtf', gdtf)


if __name__ == '__main__':
    generate_policy_fixture(Path(sys.argv[1]))
