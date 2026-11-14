#!/usr/bin/env python3
"""Generate distinct model references for cold resource preparation profiling."""
import argparse
from pathlib import Path
import struct
import zipfile

from generate_gdtf_geometry_fixture import chunk
from generate_model_detail_fixture import housing_3ds, housing_glb
from generate_presentation_lifecycle_fixture import gobo_png


def textured_3ds() -> bytes:
    """Use a real UV model and one shared external image, retaining 3DS units."""
    data = housing_3ds(32, 16)
    material = chunk(0xAFFF, chunk(0xA000, b'checker\0') + chunk(0xA200, chunk(0xA300, b'shared.png\0')))
    editor = material + data[12:]
    return chunk(0x4D4D, chunk(0x3D3D, editor))


def generate(output: Path, count: int = 1000, kind: str = '3ds', mirrored: bool = True, repeated: bool = False, animated: bool = False) -> None:
    """Different paths deliberately remain different authored model identities."""
    children = []
    for index in range(count):
        resource = 0 if repeated else index
        children.append(f'<SceneObject uuid="object-{index}"><Matrix>{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{index*1000},0,0}}</Matrix><Geometries><Geometry3D fileName="models/model-{resource}.{kind}"/></Geometries></SceneObject>')
    scale = -1 if mirrored else 1
    xml = '<GeneralSceneDescription><Scene><Layers><Layer><ChildList><GroupObject uuid="parent"><Matrix>{' + str(scale) + ',0,0}{0,1,0}{0,0,1}{1000,2000,3000}</Matrix><ChildList>' + ''.join(children) + '</ChildList></GroupObject></ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    model = textured_3ds() if kind == '3ds' else housing_glb(8,4,animated=animated)
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml',xml)
        archive.writestr('models/shared.png',gobo_png())
        for index in range(1 if repeated else count):
            archive.writestr(f'models/model-{index}.{kind}',model)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    parser.add_argument('--count',type=int,default=1000)
    parser.add_argument('--kind',choices=['3ds','glb'],default='3ds')
    parser.add_argument('--animated',action='store_true')
    parser.add_argument('--positive',action='store_true')
    parser.add_argument('--repeated',action='store_true')
    args = parser.parse_args()
    generate(args.output,args.count,args.kind,not args.positive,args.repeated,args.animated)
