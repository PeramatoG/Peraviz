#!/usr/bin/env python3
"""Small public import baseline. Fixed ZIP metadata; no vendor or user assets."""
import argparse
import io
from pathlib import Path
import zipfile
from generate_presentation_lifecycle_fixture import lens_glb, gobo_png

UUIDS = [f'10000000-0000-0000-0000-{i:012d}' for i in range(1, 4)]


def entry(archive, name, data):
    info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    info.external_attr = 0o644 << 16
    archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)


def channel(offset, attribute, geometry, high=1, width=1, extra=''):
    offsets = ','.join(str(offset+i) for i in range(width))
    return f'<DMXChannel Offset="{offsets}" Geometry="{geometry}" {extra}><LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}" DMXFrom="0/{width}" PhysicalFrom="0" PhysicalTo="{high}"/></LogicalChannel></DMXChannel>'


def mode(name, root, channels):
    return f'<DMXMode Name="{name}" Geometry="{root}"><DMXChannels>{channels}</DMXChannels></DMXMode>'


def generate(path: Path, case='supported'):
    direct = channel(1, 'Pan', 'Pan', 180, 2) + channel(3, 'Tilt', 'Tilt', 90)
    for start, geometry in [(4, 'Left'), (8, 'Right')]:
        direct += ''.join(channel(start+i, attribute, geometry) for i, attribute in enumerate(['Dimmer', 'ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    gobo = '<DMXChannel Offset="12" Geometry="Base"><LogicalChannel Attribute="Gobo1"><ChannelFunction Attribute="Gobo1" Wheel="Pattern" DMXFrom="0/1" PhysicalFrom="0" PhysicalTo="1"><ChannelSet DMXFrom="0/1" WheelSlotIndex="1"/><ChannelSet DMXFrom="128/1" WheelSlotIndex="2"/></ChannelFunction></LogicalChannel></DMXChannel>'
    direct += gobo
    repeated = ''.join(channel(4+i, attribute, 'Panel') for i, attribute in enumerate(['Dimmer', 'ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    references = '<GeometryReference Name="CellA" Geometry="Cell" Position="{1,0,0}{0,1,0}{0,0,1}{-0.2,0,0}"/><GeometryReference Name="CellB" Geometry="Cell" Position="{1,0,0}{0,1,0}{0,0,1}{0.2,0,0}"/>'
    models = '<Models><Model Name="Lens" File="lens" Length="0.02" Width="0.02" Height="0.002"/></Models>'
    beam = lambda name, position: f'<Beam Name="{name}" Model="Lens" Position="{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{position}}}" LuminousFlux="1000" BeamType="Wash" BeamRadius="0.01" BeamAngle="25"/>'
    geometries = '<Geometries><Geometry Name="Base" Position="{1,0,0}{0,1,0}{0,0,1}{0.1,0.2,0.3}"><Axis Name="Pan" Position="{1,0,0}{0,1,0}{0,0,1}{0,0,0.5}"><Axis Name="Tilt">'+beam('Left','-0.2,0,0.1')+beam('Right','0.2,0,0.1')+'</Axis></Axis></Geometry><Geometry Name="Panel">'+references+'</Geometry><Geometry Name="Cell" Position="{1,0,0}{0,1,0}{0,0,1}{0,0.1,0}">'+beam('Pixel','0,0,0.1')+'</Geometry></Geometries>'
    modes = mode('Direct','Base',direct) + mode('References','Panel',repeated)
    modes += mode('BreakTwo','Base',direct.replace('Offset="4"','DMXBreak="2" Offset="4"'))
    modes += mode('Overwrite','Panel',channel(1,'Dimmer','Pixel',extra='DMXBreak="Overwrite"'))
    modes += mode('AmbiguousReference','Panel',channel(1,'Dimmer','Pixel'))
    # Referenced source geometry remains unchanged; this variant demonstrates remapping deferral.
    if case == 'reference_offset': geometries = geometries.replace('{-0.2,0,0}"/>','{-0.2,0,0}"><Break DMXBreak="1" DMXOffset="9"/></GeometryReference>')
    wheels = '<Wheels><Wheel Name="Pattern"><Slot Name="Open"/><Slot Name="Mask" MediaFileName="pattern"/></Wheel></Wheels>'
    xml = '<GDTF DataVersion="1.2"><FixtureType Name="Public Compatibility Fixture" ShortName="Compatibility" Manufacturer="Peraviz Tests" FixtureTypeID="20000000-0000-0000-0000-000000000001">'+wheels+models+geometries+'<DMXModes>'+modes+'</DMXModes></FixtureType></GDTF>'
    packed = io.BytesIO()
    with zipfile.ZipFile(packed,'w') as archive:
        entry(archive,'description.xml',xml)
        entry(archive,'models/gltf/lens.glb',lens_glb(simple_opaque=True))
        entry(archive,'wheels/pattern.png',gobo_png())
        entry(archive,'public-extension.bin',b'unknown source bytes\0\xff')
    addresses = ['<Address break="0">3.11</Address>','<Address break="0">1067</Address>','<Address break="0">4.1</Address>']
    selected = ['Direct','Direct','References']
    if case == 'multiple_breaks': addresses[1] += '<Address break="1">5.101</Address>'
    if case == 'duplicate_break': addresses[1] += '<Address break="0">5.101</Address>'
    if case == 'nonprimary_break': addresses[1] = '<Address break="7">1067</Address>'
    if case == 'gdtf_break': selected[1] = 'BreakTwo'
    if case == 'overwrite': selected[2] = 'Overwrite'
    if case == 'ambiguous_reference': selected[2] = 'AmbiguousReference'
    if case == 'copatched': addresses[1] = addresses[0]
    fixtures = ''
    for index, uuid in enumerate(UUIDS):
        basis = '-1,0,0' if index == 1 else '1,0,0'
        fixtures += f'<Fixture uuid="{uuid}" name="Public Fixture {index+1}"><Matrix>{{{basis}}}{{0,1,0}}{{0,0,1}}{{{1000+index*3000},2000,3000}}</Matrix><GDTFSpec>public.gdtf</GDTFSpec><GDTFMode>{selected[index]}</GDTFMode><Addresses>{addresses[index]}</Addresses><FixtureID>{index+1}</FixtureID><UnitNumber>{index+1}</UnitNumber></Fixture>'
    source = '<GeneralSceneDescription verMajor="1" verMinor="6" provider="Peraviz Tests" providerVersion="1"><UserData><Data provider="Peraviz Tests" ver="1"><PublicExtension opaque="retained"/></Data></UserData><Scene><Layers><Layer uuid="30000000-0000-0000-0000-000000000001" name="Public Layer"><ChildList>'+fixtures+'</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    path.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(path,'w') as archive:
        entry(archive,'GeneralSceneDescription.xml',source)
        entry(archive,'public.gdtf',packed.getvalue())
        entry(archive,'public-unknown.txt',b'preserve the original archive')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--case',default='supported',choices=['supported','multiple_breaks','duplicate_break','nonprimary_break','gdtf_break','overwrite','ambiguous_reference','reference_offset','copatched'])
    args = parser.parse_args()
    generate(args.path,args.case)
