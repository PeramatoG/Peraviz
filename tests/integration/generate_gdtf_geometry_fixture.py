#!/usr/bin/env python3
"""Generate public synthetic fixture geometry with independently known bounds/transforms."""
from __future__ import annotations
import argparse
import io
import json
from pathlib import Path
import struct
import zipfile


def chunk(kind: int, payload: bytes) -> bytes:
    return struct.pack("<HI", kind, len(payload) + 6) + payload


def box_vertices(low: tuple, high: tuple) -> list[tuple]:
    return [(x, y, z) for x in (low[0], high[0]) for y in (low[1], high[1]) for z in (low[2], high[2])]


INDICES = [0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5, 0, 4, 5, 0, 5, 1,
           2, 3, 7, 2, 7, 6, 0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3]


def box_3ds() -> bytes:
    vertices = box_vertices((-100, -200, -300), (100, 200, 300))
    points = chunk(0x4110, struct.pack("<H", len(vertices)) + b"".join(struct.pack("<3f", *v) for v in vertices))
    faces = chunk(0x4120, struct.pack("<H", len(INDICES) // 3) + b"".join(struct.pack("<4H", *INDICES[i:i+3], 0) for i in range(0, len(INDICES), 3)))
    return chunk(0x4D4D, chunk(0x3D3D, chunk(0x4000, b"box\0" + chunk(0x4100, points + faces))))


def transformed_glb() -> bytes:
    vertices = box_vertices((0, 0, 0), (1000, 2000, 3000))
    binary = b"".join(struct.pack("<3f", *v) for v in vertices) + struct.pack("<36H", *INDICES)
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"name": "EmbeddedRoot", "translation": [1, 2, 3], "scale": [0.001]*3, "children": [1]},
                     {"name": "EmbeddedRotation", "rotation": [0, 2**-0.5, 0, 2**-0.5], "children": [2]},
                     {"name": "EmbeddedMirror", "translation": [500, 0, 0], "scale": [-2, 1, 1], "mesh": 0}],
           "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
           "buffers": [{"byteLength": len(binary)}],
           "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 96}, {"buffer": 0, "byteOffset": 96, "byteLength": 72}],
           "accessors": [{"bufferView": 0, "componentType": 5126, "count": 8, "type": "VEC3", "min": [0, 0, 0], "max": [1000, 2000, 3000]},
                         {"bufferView": 1, "componentType": 5123, "count": 36, "type": "SCALAR"}]}
    payload = json.dumps(doc, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    return struct.pack("<III", 0x46546C67, 2, 28 + len(payload) + len(binary)) + struct.pack("<II", len(payload), 0x4E4F534A) + payload + struct.pack("<II", len(binary), 0x004E4942) + binary


def gdtf(partial: bool = False, primitive: bool = False) -> bytes:
    model_file = "genuinely_missing.1" if partial else "base_1.1"
    if primitive:
        models = '<Model Name="Body" PrimitiveType="Cube" Length="0.1" Width="0.2" Height="0.3"/>'
        geometries = '<Beam Name="Base" Model="Body" LuminousFlux="1000" BeamAngle="20"/>'
        target = 'Base'
    else:
        models = f'''<Model Name="Body" File="{model_file}" PrimitiveType="Undefined" Length="0.4" Width="0.3" Height="0.2"/>
<Model Name="YokeModel" File="head.v2.模型" Length="0.2" Width="0.4" Height="0.6"/>
<Model Name="HeadModel" File="base_1.1" Length="0.1" Width="0.2" Height="0.3"/>
<Model Name="ReferenceModel" PrimitiveType="Sphere" Length="0.1" Width="0.2" Height="0.3"/>'''
        geometries = '''<Geometry Name="Unused"/><Geometry Name="Base" Model="Body" Position="{1,0,0}{0,1,0}{0,0,1}{0.1,0.2,0.3}">
<Axis Name="Yoke" Model="YokeModel" Position="{1,0,0}{0,1,0}{0,0,1}{0,0,0.3}">
<Beam Name="Head" Model="HeadModel" LuminousFlux="1000" BeamAngle="20" Position="{1,0,0}{0,1,0}{0,0,1}{0,0.2,0}"/>
</Axis><GeometryReference Name="Copy" Geometry="Module" Position="{1,0,0}{0,1,0}{0,0,1}{0.5,0,0}"/>
</Geometry><Geometry Name="Module" Model="ReferenceModel" Position="{1,0,0}{0,1,0}{0,0,1}{0,0,0.1}"/>'''
        target = 'Head'
    xml = f'''<GDTF DataVersion="1.2"><FixtureType Name="Synthetic Geometry"><Models>{models}</Models><Geometries>{geometries}</Geometries>
<DMXModes><DMXMode Name="Selected" Geometry="Base"><DMXChannels><DMXChannel Offset="1" Geometry="{target}">
<LogicalChannel Attribute="Dimmer"><ChannelFunction Attribute="Dimmer" DMXFrom="0" PhysicalFrom="0" PhysicalTo="1"/>
</LogicalChannel></DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'''
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('description.xml', xml)
        if not primitive:
            archive.writestr('models/3ds/base_1.1.3ds', box_3ds())
            archive.writestr('models/gltf/head.v2.模型.glb', transformed_glb())
    return data.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fixtures = []
    for index, (uuid, spec) in enumerate([('complete-one', 'Geometryñ.gdtf'), ('complete-two', 'Geometryñ.gdtf'), ('partial-one', 'Partial.gdtf'), ('partial-two', 'Partial.gdtf'), ('primitive', 'Primitive.gdtf')]):
        fixtures.append(f'''<Fixture uuid="{uuid}" name="{uuid}" Universe="1" Address="{index + 1}"><Matrix>{{1,0,0}}{{0,1,0}}{{0,0,1}}{{1000,2000,3000}}</Matrix><GDTFSpec>{spec}</GDTFSpec><GDTFMode>Selected</GDTFMode></Fixture>''')
    objects = '<SceneObject uuid="stage"><Geometries><Geometry3D fileName="stage.3ds"/></Geometries></SceneObject><Truss uuid="truss"><Geometries><Geometry3D fileName="stage.3ds"/></Geometries></Truss>'
    objects += '<SceneObject uuid="stage-glb"><Geometries><Geometry3D fileName="stage.glb"/></Geometries></SceneObject><Truss uuid="truss-glb"><Geometries><Geometry3D fileName="stage.glb"/></Geometries></Truss>'
    xml = '<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList>' + ''.join(fixtures) + objects + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml', xml)
        archive.writestr('Geometryñ.gdtf', gdtf())
        archive.writestr('Partial.gdtf', gdtf(partial=True))
        archive.writestr('Primitive.gdtf', gdtf(primitive=True))
        archive.writestr('stage.3ds', box_3ds())
        archive.writestr('stage.glb', transformed_glb())


if __name__ == '__main__':
    main()
