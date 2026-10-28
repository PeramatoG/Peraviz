#!/usr/bin/env python3
"""Public synthetic authored quality resources; no vendor files or fixed binary artifacts."""
import argparse
import io
import math
import json
import base64
import zlib
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


def housing_glb(segments: int, rings: int, transparent: bool = False, animated: bool = False) -> bytes:
    positions, normals, uvs, indices = [], [], [], []
    for ring in range(rings + 1):
        theta = math.pi * ring / rings
        for segment in range(segments + 1):
            phi = 2 * math.pi * segment / segments
            normal = (math.sin(theta)*math.cos(phi), math.cos(theta), math.sin(theta)*math.sin(phi))
            positions.extend(v * .45 for v in normal)
            normals.extend(normal)
            uvs.extend((segment/segments,ring/rings))
    for ring in range(rings):
        for segment in range(segments):
            a = ring*(segments+1)+segment
            b = a+segments+1
            if ring: indices.extend((a,a+1,b))
            if ring != rings-1: indices.extend((a+1,b+1,b))
    binary = bytearray()
    views, accessors = [], []
    def accessor(values, code, component, kind, width, **extra):
        offset = len(binary)
        binary.extend(struct.pack('<'+code*len(values),*values))
        views.append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset})
        binary.extend(b'\0'*(-len(binary)%4))
        accessors.append({'bufferView':len(views)-1,'componentType':component,'count':len(values)//width,'type':kind,**extra})
        return len(accessors)-1
    position = accessor(positions,'f',5126,'VEC3',3,min=[-.45]*3,max=[.45]*3)
    normal = accessor(normals,'f',5126,'VEC3',3)
    uv = accessor(uvs,'f',5126,'VEC2',2)
    mid = (len(indices)//6)*3
    first = accessor(indices[:mid],'H',5123,'SCALAR',1)
    second = accessor(indices[mid:],'H',5123,'SCALAR',1)
    # Public generated checker texture; exercises actual GLB material/UV ownership.
    def png_chunk(tag, payload):
        return struct.pack('>I',len(payload))+tag+payload+struct.pack('>I',zlib.crc32(tag+payload))
    image = b'\x89PNG\r\n\x1a\n'+png_chunk(b'IHDR',struct.pack('>2I5B',2,2,8,2,0,0,0))+png_chunk(b'IDAT',zlib.compress(b'\0'+bytes([80,120,160,180,180,180])+b'\0'+bytes([180,180,180,80,120,160])))+png_chunk(b'IEND',b'')
    material = {'pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0.0},'doubleSided':False}
    if transparent: material['alphaMode'] = 'BLEND'
    doc = {'asset':{'version':'2.0'},'scene':0,'scenes':[{'nodes':[0]}],
        'nodes':[{'name':'EmbeddedRoot','translation':[.1,.2,.3],'children':[1]}, {'name':'EmbeddedMirror','scale':[-1,1,1],'mesh':0}],
        'meshes':[{'primitives':[{'attributes':{'POSITION':position,'NORMAL':normal,'TEXCOORD_0':uv},'indices':first,'material':0},{'attributes':{'POSITION':position,'NORMAL':normal,'TEXCOORD_0':uv},'indices':second,'material':1}]}],
        'materials':[material,{'pbrMetallicRoughness':{'baseColorFactor':[.3,.3,.3,1]},'doubleSided':True}],
        'textures':[{'source':0}], 'images':[{'uri':'data:image/png;base64,'+base64.b64encode(image).decode()}]}
    if animated:
        times = accessor([0.,1.],'f',5126,'SCALAR',1,min=[0.],max=[1.])
        values = accessor([.1,.2,.3,.2,.2,.3],'f',5126,'VEC3',3)
        doc['animations'] = [{'name':'MovingHousing','samplers':[{'input':times,'output':values}],'channels':[{'sampler':0,'target':{'node':0,'path':'translation'}}]}]
    doc.update(buffers=[{'byteLength':len(binary)}],bufferViews=views,accessors=accessors)
    payload = json.dumps(doc,separators=(',',':')).encode()
    payload += b' '*(-len(payload)%4)
    return struct.pack('<III',0x46546c67,2,28+len(payload)+len(binary))+struct.pack('<II',len(payload),0x4e4f534a)+payload+struct.pack('<II',len(binary),0x004e4942)+binary


def generate(path: Path, tiers: list[str], formats: list[str], mixed: bool = False, dense: bool = False, special: bool = False, oversized: bool = False, lod_glb: bool = False, transparent: bool = False, animated: bool = False, scenery: bool = False) -> None:
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
            if oversized: segments, rings = 192, 128
            if '3ds' in formats: gdtf.writestr(f'models/3ds{suffix}/housing.3ds', housing_3ds(segments, rings))
            if 'glb' in formats: gdtf.writestr(f'models/gltf{suffix}/housing.glb', housing_glb(segments,rings,transparent,animated) if lod_glb else transformed_glb())
        gdtf.writestr('models/3ds/lens.3ds', housing_3ds(8, 4))
    fixtures = ''.join(f'''<Fixture uuid="detail-{index}" name="Detail {index}" Universe="1" Address="{1 + index * 16}"><Matrix>{{-1,0,0}}{{0,1,0}}{{0,0,1}}{{{index * 1500},0,0}}</Matrix><GDTFSpec>Detail.gdtf</GDTFSpec><GDTFMode>Mode</GDTFMode><Addresses><Address break="0">{1 + index * 16}</Address></Addresses></Fixture>''' for index in range(3))
    if scenery: fixtures += '<SceneObject uuid="scenery"><Geometries><Geometry3D fileName="stage.3ds"/></Geometries></SceneObject>'
    mvr = '<GeneralSceneDescription verMajor="1" verMinor="6"><Scene><Layers><Layer name="Detail" uuid="layer"><ChildList>' + fixtures + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('GeneralSceneDescription.xml', mvr)
        archive.writestr('Detail.gdtf', packed.getvalue())
        if scenery: archive.writestr('stage.3ds',housing_3ds(64,32))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('path', type=Path)
    parser.add_argument('--tiers', default='default,low,high')
    parser.add_argument('--formats', default='3ds,glb')
    parser.add_argument('--mixed', action='store_true')
    parser.add_argument('--dense', action='store_true')
    parser.add_argument('--special', action='store_true')
    for option in ['oversized','lod-glb','transparent','animated','scenery']: parser.add_argument('--'+option,action='store_true')
    args = parser.parse_args()
    generate(args.path, args.tiers.split(','), args.formats.split(','), args.mixed, args.dense, args.special, args.oversized, args.lod_glb, args.transparent, args.animated, args.scenery)
