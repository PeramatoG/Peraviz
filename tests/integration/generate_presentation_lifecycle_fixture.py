#!/usr/bin/env python3
"""Generate a small fixture for the real application lighting lifecycle test."""
from __future__ import annotations

import argparse
import json
import math
import struct
import zipfile
import zlib
from pathlib import Path


def gobo_png() -> bytes:
    """Return a deterministic, nontrivial opaque gobo without external image tools."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + b''.join(bytes([255 if 3 <= x <= 12 and 3 <= y <= 12 else 0] * 3 + [255]) for x in range(16)) for y in range(16))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


def lens_glb(simple_opaque: bool = False) -> bytes:
    """Return one named lens triangle with an actual material and picking geometry."""
    binary = struct.pack('<9f', -0.05,0,-0.05, 0.05,0,-0.05, 0,0,0.05)
    gltf = {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],
            "nodes":[{"name":"Lens","mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}],
            "materials":[{"doubleSided":True}],"buffers":[{"byteLength":len(binary)}],
            "bufferViews":[{"buffer":0,"byteLength":len(binary),"target":34962}],
            "accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[-0.05,0,-0.05],"max":[0.05,0,0.05]}]}
    if simple_opaque:
        # A nondegenerate thin aperture fits the declared 10:1 dimensions uniformly.
        # MultiMesh's nonuniform per-instance normal transform is deliberately outside admission.
        vertices = [(-.05,.005,-.05),(.05,.005,-.05),(0,.005,.05),
                    (-.05,-.005,-.05),(.05,-.005,-.05),(0,-.005,.05)]
        faces = [(0,2,1),(3,4,5),(0,1,4),(0,4,3),(1,2,5),(1,5,4),(2,0,3),(2,3,5)]
        positions, normals = [], []
        for face in faces:
            a,b,c = [vertices[i] for i in face]
            u,v = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
            normal = (u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
            length = math.sqrt(sum(value*value for value in normal))
            for vertex in (a,b,c):
                positions.extend(vertex)
                normals.extend(value/length for value in normal)
        binary = struct.pack('<%df' % (len(positions)+len(normals)), *(positions+normals))
        gltf["materials"][0]["pbrMetallicRoughness"] = {"metallicFactor": 0.0}
        gltf["meshes"][0]["primitives"][0]["attributes"]["NORMAL"] = 1
        gltf["buffers"][0]["byteLength"] = len(binary)
        gltf["bufferViews"] = [{"buffer":0,"byteOffset":0,"byteLength":len(positions)*4},
                               {"buffer":0,"byteOffset":len(positions)*4,"byteLength":len(normals)*4}]
        gltf["accessors"] = [{"bufferView":0,"componentType":5126,"count":24,"type":"VEC3","min":[-.05,-.005,-.05],"max":[.05,.005,.05]},
                             {"bufferView":1,"componentType":5126,"count":24,"type":"VEC3"}]
    data = json.dumps(gltf,separators=(',',':')).encode()
    data += b' ' * (-len(data)%4)
    return struct.pack('<III',0x46546c67,2,28+len(data)+len(binary)) + struct.pack('<II',len(data),0x4e4f534a) + data + struct.pack('<II',len(binary),0x004e4942) + binary


def generate(output: Path) -> None:
    """Build two independent projected emitters with dimmer, RGB, motion, zoom and gobo."""
    import io
    channels = []
    for offset, attribute, geometry, low, high, wheel in [
        (1, 'Dimmer', 'Beam', 0, 1, ''), (2, 'ColorAdd_R', 'Beam', 0, 1, ''),
        (3, 'ColorAdd_G', 'Beam', 0, 1, ''), (4, 'ColorAdd_B', 'Beam', 0, 1, ''),
        (5, 'Pan', 'Pan', -180, 180, ''), (6, 'Tilt', 'Tilt', -90, 90, ''),
        (7, 'Zoom', 'Beam', 10, 40, ''), (8, 'Gobo1', 'Beam', 0, 1, ' Wheel="Gobo Wheel"'),
    ]:
        sets = '<ChannelSet DMXFrom="0" WheelSlotIndex="1"/><ChannelSet DMXFrom="128" WheelSlotIndex="2"/>' if wheel else ''
        channels.append(f'<DMXChannel Offset="{offset}" Geometry="{geometry}"><LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}" DMXFrom="0" DMXTo="255" PhysicalFrom="{low}" PhysicalTo="{high}"{wheel}>{sets}</ChannelFunction></LogicalChannel></DMXChannel>')
    description = '<GDTF><FixtureType Name="Presentation Lifecycle"><Models><Model Name="Lens" File="lens" Length="0.1" Width="0.1" Height="0.01"/></Models><Geometries><Geometry Name="Root"><Axis Name="Pan"><Axis Name="Tilt"><Beam Name="Beam" Model="Lens" LuminousFlux="1000" BeamAngle="20" BeamRadius="0.05" BeamType="Wash"/></Axis></Axis></Geometry></Geometries><Wheels><Wheel Name="Gobo Wheel"><Slot Name="Open"/><Slot Name="Square" MediaFileName="square"/></Wheel></Wheels><DMXModes><DMXMode Name="Main" Geometry="Root"><DMXChannels>' + ''.join(channels) + '</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as gdtf:
        gdtf.writestr('description.xml', description)
        gdtf.writestr('wheels/square.png', gobo_png())
        gdtf.writestr('models/gltf/lens.glb', lens_glb())
    fixtures = ''.join(f'<Fixture uuid="fixture-{i}" name="Fixture {i}" Universe="1" Address="{1+i*16}"><GDTFSpec>lifecycle.gdtf</GDTFSpec><GDTFMode>Main</GDTFMode></Fixture>' for i in range(2))
    scene = '<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList>' + fixtures + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as mvr:
        mvr.writestr('GeneralSceneDescription.xml', scene)
        mvr.writestr('lifecycle.gdtf', data.getvalue())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    generate(parser.parse_args().output)
