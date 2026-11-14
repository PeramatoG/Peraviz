#!/usr/bin/env python3
"""Public, deterministic scenery stress asset; no proprietary show data required."""
import argparse
from pathlib import Path
import zipfile

from generate_gdtf_geometry_fixture import box_3ds, transformed_glb, gdtf


def generate(output: Path, objects: int = 10000, entries: int = 4500) -> None:
    """Mix shared models, Symdefs, nested transforms, fixtures, and unused assets."""
    groups = []
    for group in range((objects + 99) // 100):
        children = []
        for index in range(group * 100, min(objects, (group + 1) * 100)):
            # Basis is dimensionless; translations are MVR millimetres. A 1000x
            # local translation below a .001 parent becomes one source mm.
            geometry = '<Symbol symdef="shared"/>' if index % 3 == 0 else '<Geometry3D fileName="stage.3ds"/>' if index % 3 == 1 else '<Geometry3D fileName="stage.glb"/>'
            children.append(f'<SceneObject uuid="object-{index}" name="Object{index}"><Matrix>{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{(index % 100)*1000},0,0}}</Matrix><Geometries>{geometry}</Geometries></SceneObject>')
        groups.append(f'<GroupObject uuid="group-{group}" name="Group{group}"><Matrix>{{0,0.001,0}}{{-0.002,0,0}}{{0,0,-0.003}}{{1000,{group},3000}}</Matrix><ChildList>{"".join(children)}</ChildList></GroupObject>')
    fixtures = ''.join(f'<Fixture uuid="fixture-{i}" name="Fixture{i}"><GDTFSpec>{spec}</GDTFSpec><GDTFMode>Selected</GDTFMode><Addresses><Address break="0">{1+i*10}</Address></Addresses></Fixture>' for i, spec in enumerate(['Complete.gdtf','Complete.gdtf','Primitive.gdtf']))
    xml = '<GeneralSceneDescription><AUXData><Symdef uuid="shared" name="Shared"><ChildList><Geometry3D fileName="stage.3ds"/></ChildList></Symdef></AUXData><Scene><Layers><Layer uuid="layer"><ChildList>' + ''.join(groups) + fixtures + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml', xml)
        archive.writestr('stage.3ds', box_3ds())
        archive.writestr('stage.glb', transformed_glb())
        archive.writestr('Complete.gdtf', gdtf())
        archive.writestr('Primitive.gdtf', gdtf(primitive=True))
        for index in range(entries):
            archive.writestr(f'unused/{index}/texture.png', b'unreferenced')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--objects', type=int, default=10000)
    parser.add_argument('--entries', type=int, default=4500)
    args = parser.parse_args()
    generate(args.output, args.objects, args.entries)
