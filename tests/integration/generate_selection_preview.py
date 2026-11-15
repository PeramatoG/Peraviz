#!/usr/bin/env python3
"""Build a public synthetic rig for inspecting selection and the navigation cube."""
from __future__ import annotations

import argparse
import io
import math
from pathlib import Path
import struct
import zipfile

from generate_gdtf_geometry_fixture import chunk, INDICES, box_vertices, box_3ds


def cylinder_mesh() -> bytes:
    """Use an authored 3DS head so preview material ownership matches real assets."""
    vertices = [(100*math.cos(i*math.tau/24), 100*math.sin(i*math.tau/24), z)
                for z in [-100,100] for i in range(24)]
    indices = []
    for i in range(24):
        nxt = (i+1)%24
        indices.extend([i,nxt,24+i,nxt,24+nxt,24+i])
    for i in range(1,23):
        indices.extend([0,i+1,i,24,24+i,24+i+1])
    return mesh_3ds(vertices, indices)


def mesh_3ds(vertices: list[tuple], indices: list[int]) -> bytes:
    """Encode a public test mesh without application document mutation."""
    points = chunk(0x4110, struct.pack('<H', len(vertices)) + b''.join(struct.pack('<3f', *v) for v in vertices))
    faces = chunk(0x4120, struct.pack('<H', len(indices)//3) + b''.join(struct.pack('<4H', *indices[i:i+3], 0) for i in range(0,len(indices),3)))
    return chunk(0x4D4D, chunk(0x3D3D, chunk(0x4000, b'PreviewMesh\0' + chunk(0x4100, points + faces))))


def truss_mesh() -> bytes:
    """Create a small truss-like assembly from opaque box members in millimetres."""
    vertices: list[tuple] = []
    indices: list[int] = []
    members = []
    for y in [-120, 120]:
        for z in [1800, 2040]:
            members.append(((-2500, y-18, z-18), (2500, y+18, z+18)))
    for x in range(-2500, 2501, 500):
        members.append(((x-12, -138, 1782), (x+12, 138, 1818)))
        members.append(((x-12, -138, 2022), (x+12, 138, 2058)))
        for y in [-120, 120]:
            members.append(((x-12, y-12, 1800), (x+12, y+12, 2040)))
    for low, high in members:
        offset = len(vertices)
        vertices.extend(box_vertices(low, high))
        indices.extend(index + offset for index in INDICES)
    return mesh_3ds(vertices, indices)


def generate(output: Path) -> None:
    """Package authored moving-head bodies and a rig through the production importer."""
    channels = []
    for offset, attribute, geometry, low, high in [(1, 'Dimmer', 'Head', 0, 1), (2, 'Pan', 'Pan', -270, 270), (3, 'Tilt', 'Tilt', -135, 135)]:
        channels.append(f'<DMXChannel Offset="{offset}" Geometry="{geometry}"><LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}" DMXFrom="0" PhysicalFrom="{low}" PhysicalTo="{high}"/></LogicalChannel></DMXChannel>')
    description = '''<GDTF DataVersion="1.2"><FixtureType Name="Synthetic Preview Spot"><Models>
<Model Name="Base" File="body" PrimitiveType="Undefined" Length="0.42" Width="0.3" Height="0.18"/>
<Model Name="Upright" File="body" PrimitiveType="Undefined" Length="0.08" Width="0.12" Height="0.38"/>
<Model Name="Head" File="head" PrimitiveType="Undefined" Length="0.32" Width="0.32" Height="0.42"/>
</Models><Geometries><Geometry Name="Base" Model="Base"><Axis Name="Pan">
<Geometry Name="LeftYoke" Model="Upright" Position="{1,0,0}{0,1,0}{0,0,1}{-0.22,0,-0.22}"/>
<Geometry Name="RightYoke" Model="Upright" Position="{1,0,0}{0,1,0}{0,0,1}{0.22,0,-0.22}"/>
<Axis Name="Tilt" Position="{1,0,0}{0,1,0}{0,0,1}{0,0,-0.35}">
<Beam Name="Head" Model="Head" LuminousFlux="5000" BeamAngle="20" BeamRadius="0.1"/>
</Axis></Axis></Geometry></Geometries><DMXModes><DMXMode Name="Preview 3ch" Geometry="Base"><DMXChannels>''' + ''.join(channels) + '</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'
    gdtf_data = io.BytesIO()
    with zipfile.ZipFile(gdtf_data, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('description.xml', description)
        archive.writestr('models/3ds/body.3ds', box_3ds())
        archive.writestr('models/3ds/head.3ds', cylinder_mesh())
    fixtures = []
    for index, x in enumerate([-1800, -600, 600, 1800]):
        fixtures.append(f'<Fixture uuid="preview-{index}" name="Spot {101+index}" Universe="1" Address="{1+index*3}"><FixtureID>{101+index}</FixtureID><Matrix>{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{x},0,1700}}</Matrix><GDTFSpec>PreviewSpot.gdtf</GDTFSpec><GDTFMode>Preview 3ch</GDTFMode></Fixture>')
    scene = '<GeneralSceneDescription><Scene><Layers><Layer uuid="preview-layer"><ChildList><GroupObject uuid="preview-rig" name="Lighting rig"><ChildList><Truss uuid="preview-truss" name="Front truss"><Geometries><Geometry3D fileName="truss.3ds"/></Geometries></Truss>' + ''.join(fixtures) + '</ChildList></GroupObject></ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml', scene)
        archive.writestr('PreviewSpot.gdtf', gdtf_data.getvalue())
        archive.writestr('truss.3ds', truss_mesh())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    generate(parser.parse_args().output)
