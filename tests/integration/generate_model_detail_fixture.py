#!/usr/bin/env python3
"""Public synthetic authored quality resources; no vendor files or fixed binary artifacts."""
import argparse
import io
import math
from pathlib import Path
import struct
import zipfile
from generate_gdtf_geometry_fixture import chunk, transformed_glb


def housing_3ds(segments: int, rings: int) -> bytes:
    vertices = []
    uvs = []
    for ring in range(rings + 1):
        theta = math.pi * ring / rings
        for segment in range(segments + 1):
            phi = 2 * math.pi * segment / segments
            vertices.append((450 * math.sin(theta) * math.cos(phi), 450 * math.sin(theta) * math.sin(phi), 450 * math.cos(theta)))
            uvs.append((segment / segments, ring / rings))
    faces = []
    for ring in range(rings):
        for segment in range(segments):
            a = ring * (segments + 1) + segment
            b = a + segments + 1
            if ring: faces.append((a, b, a + 1))
            if ring != rings - 1: faces.append((a + 1, b, b + 1))
    points = chunk(0x4110, struct.pack('<H', len(vertices)) + b''.join(struct.pack('<3f', *v) for v in vertices))
    indices = chunk(0x4120, struct.pack('<H', len(faces)) + b''.join(struct.pack('<4H', *f, 0) for f in faces))
    texcoords = chunk(0x4140, struct.pack('<H', len(uvs)) + b''.join(struct.pack('<2f', *uv) for uv in uvs))
    return chunk(0x4D4D, chunk(0x3D3D, chunk(0x4000, b'authored-housing\0' + chunk(0x4100, points + indices + texcoords))))


def generate(path: Path, tiers: list[str], formats: list[str], mixed: bool = False, dense: bool = False, special: bool = False) -> None:
    lens_file = 'housing' if mixed else 'lens'
    xml = f'''<GDTF DataVersion="1.2"><FixtureType Name="Public Model Detail Fixture"><Models>
<Model Name="Case" File="housing" Length="0.9" Width="0.9" Height="0.9"/>
<Model Name="Lens" File="{lens_file}" Length="0.05" Width="0.05" Height="0.01"/>
</Models><Geometries><Geometry Name="Base"><Axis Name="Pan"><Axis Name="Tilt">
<Geometry Name="Housing" Model="Case"/><Beam Name="Optic" Model="Lens" BeamType="Spot" BeamRadius="0.02" BeamAngle="20" LuminousFlux="1000"/>
</Axis></Axis></Geometry></Geometries><DMXModes><DMXMode Name="Mode" Geometry="Base"><DMXChannels>
<DMXChannel Offset="1" Geometry="Optic"><LogicalChannel Attribute="Dimmer"><ChannelFunction Attribute="Dimmer" DMXFrom="0" PhysicalFrom="0" PhysicalTo="1"/></LogicalChannel></DMXChannel>
</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'''
    if special: xml = xml.replace('<Geometry Name="Housing"', '<FilterGobo Name="Housing"')
    packed = io.BytesIO()
    with zipfile.ZipFile(packed, 'w', zipfile.ZIP_DEFLATED) as gdtf:
        gdtf.writestr('description.xml', xml)
        for tier in tiers:
            suffix = '' if tier == 'default' else '_' + tier
            segments, rings = {'low': (16, 8), 'default': (32, 16), 'high': (64, 32)}[tier]
            if dense: segments, rings = 128, 64
            if '3ds' in formats: gdtf.writestr(f'models/3ds{suffix}/housing.3ds', housing_3ds(segments, rings))
            if 'glb' in formats: gdtf.writestr(f'models/gltf{suffix}/housing.glb', transformed_glb())
        gdtf.writestr('models/3ds/lens.3ds', housing_3ds(8, 4))
    fixtures = ''.join(f'''<Fixture uuid="detail-{index}" name="Detail {index}" Universe="1" Address="{1 + index * 16}"><Matrix>{{-1,0,0}}{{0,1,0}}{{0,0,1}}{{{index * 1500},0,0}}</Matrix><GDTFSpec>Detail.gdtf</GDTFSpec><GDTFMode>Mode</GDTFMode><Addresses><Address break="0">{1 + index * 16}</Address></Addresses></Fixture>''' for index in range(3))
    mvr = '<GeneralSceneDescription verMajor="1" verMinor="6"><Scene><Layers><Layer name="Detail" uuid="layer"><ChildList>' + fixtures + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml', mvr)
        archive.writestr('Detail.gdtf', packed.getvalue())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('path', type=Path)
    parser.add_argument('--tiers', default='default,low,high')
    parser.add_argument('--formats', default='3ds,glb')
    parser.add_argument('--mixed', action='store_true')
    parser.add_argument('--dense', action='store_true')
    parser.add_argument('--special', action='store_true')
    args = parser.parse_args()
    generate(args.path, args.tiers.split(','), args.formats.split(','), args.mixed, args.dense, args.special)
