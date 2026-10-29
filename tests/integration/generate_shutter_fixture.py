#!/usr/bin/env python3
"""Deterministic public shutter fixtures, reusing the production import baseline ZIP/assets."""
import argparse
import io
import math
from pathlib import Path
import zipfile
from generate_import_compatibility_fixture import entry, channel, mode
from generate_presentation_lifecycle_fixture import lens_glb, gobo_png


def generate(path: Path, outputs=4, shared=False, split=False, gobo=False, absent=False, shutter_index=1, random_modes=False, fidelity=False, channel_master=False, conditional_mode=False):
    xml_attributes = ''
    for name, unit, subs in [
        ('Shutter1', 'None', ''),
        ('Shutter1Strobe', 'Frequency', '<SubPhysicalUnit Type="Duration" PhysicalUnit="Time" PhysicalFrom="0.025" PhysicalTo="0.025"/><SubPhysicalUnit Type="TimeOffset" PhysicalUnit="Percent" PhysicalFrom="100" PhysicalTo="100"/>'),
        ('Shutter1StrobePulse', 'Frequency', ''),
        ('Shutter1StrobePulseOpen', 'Frequency', '<SubPhysicalUnit Type="DutyCycle" PhysicalUnit="Percent" PhysicalFrom="50" PhysicalTo="50"/><SubPhysicalUnit Type="TimeOffset" PhysicalUnit="Percent" PhysicalFrom="75" PhysicalTo="75"/>'),
        ('Shutter1StrobePulseClose', 'Frequency', ''),
        ('StrobeFrequency', 'Frequency', ''), ('StrobeDuration', 'Time', ''),
        ('Gobo1PosRotate', 'AngularSpeed', '')]:
        xml_attributes += f'<Attribute Name="{name}" PhysicalUnit="{unit}">{subs}</Attribute>'
    refs = ''
    columns = math.ceil(math.sqrt(outputs))
    width = 3 if split else 1
    for index in range(outputs):
        bank = index // (500 // width)
        slot = (index % (500 // width)) * width + 1
        # Tight co-directional apertures allow proving shared-strobe aggregate compatibility.
        x, y = (index % columns) * 0.025, (index // columns) * 0.025
        remap = '' if shared or absent else f'<Break DMXBreak="{bank+2}" DMXOffset="{slot}"/>'
        refs += f'<GeometryReference Name="Cell{index}" Geometry="Cell" Position="{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{x},{y},0}}">{remap}</GeometryReference>'
    geometry = '<Geometries><Axis Name="Base">'+refs+'</Axis><Geometry Name="Cell"><Beam Name="Pixel" Model="Lens" BeamType="Wash" BeamRadius="0.02" BeamAngle="25" LuminousFlux="1000"/></Geometry></Geometries>'
    channels = ''.join(channel(1+i, attr, 'Base') for i, attr in enumerate(['Dimmer','ColorAdd_R','ColorAdd_G','ColorAdd_B']))
    target = 'Base' if shared else 'Pixel'
    declaration = 'DMXBreak="1"' if shared else 'DMXBreak="Overwrite"'
    offset = 7 if shared and gobo else 5 if shared else 1
    if not absent:
        if split:
            functions = '<ChannelFunction Name="Closed" Attribute="StrobeModeShutter" DMXFrom="0/1"/><ChannelFunction Name="Open" Attribute="StrobeModeShutter" DMXFrom="10/1"/><ChannelFunction Name="Strobe" Attribute="StrobeModeStrobe" DMXFrom="20/1"/><ChannelFunction Name="Pulse" Attribute="StrobeModePulse" DMXFrom="120/1"/><ChannelFunction Name="PulseOpen" Attribute="StrobeModePulseOpen" DMXFrom="160/1"/><ChannelFunction Name="PulseClose" Attribute="StrobeModePulseClose" DMXFrom="200/1"/>'
            if channel_master:
                functions = functions.replace('<ChannelFunction Name="Pulse"','<ChannelFunction Name="StrobeRepeat" Attribute="StrobeModeStrobe" DMXFrom="60/1"/><ChannelFunction Name="Pulse"')
            if conditional_mode:
                functions = functions.replace('Name="StrobeRepeat"','Name="StrobeRepeat" ModeMaster="Base_Dimmer" ModeFrom="128/1" ModeTo="255/1"')
            channels += f'<DMXChannel Offset="{offset}" Geometry="{target}" {declaration}><LogicalChannel Attribute="StrobeModeShutter">{functions}</LogicalChannel><LogicalChannel Attribute="StrobeMode"><ChannelFunction Name="Mode Selector" Attribute="StrobeModeShutter"/></LogicalChannel></DMXChannel>'
            functions = ''
            for name in ['Strobe','Pulse','PulseOpen','PulseClose']:
                link = f'{target}_StrobeModeShutter.StrobeModeShutter.{name}'
                if shared and name == "Random": continue
                functions += f'<ChannelFunction Name="{name}" Attribute="StrobeFrequency" DMXFrom="0/1" ModeMaster="{link}" ModeFrom="0/1" ModeTo="255/1" PhysicalFrom="2" PhysicalTo="10"/>'
            if channel_master:
                functions = f'<ChannelFunction Name="Frequency" Attribute="StrobeFrequency" ModeMaster="{target}_StrobeModeShutter" ModeFrom="0/1" ModeTo="255/1" PhysicalFrom="2" PhysicalTo="10"/>'
            channels += f'<DMXChannel Offset="{offset+1}" Geometry="{target}" {declaration}><LogicalChannel Attribute="StrobeFrequency">{functions}</LogicalChannel></DMXChannel>'
            channels += channel(offset+2, 'StrobeDuration', target, 0.05, extra=declaration)
        else:
            functions = '<ChannelFunction Name="Gate" Attribute="Shutter1" DMXFrom="0/1" PhysicalFrom="0" PhysicalTo="1"><ChannelSet Name="Closed" DMXFrom="0/1" PhysicalFrom="0" PhysicalTo="0"/><ChannelSet Name="Open" DMXFrom="10/1" PhysicalFrom="1" PhysicalTo="1"/></ChannelFunction>'
            for name, attr, start, low, high in [
                ('Strobe','Shutter1Strobe',20,2,10), ('Pulse','Shutter1StrobePulse',120,2,2),
                ('PulseOpen','Shutter1StrobePulseOpen',160,2,2), ('PulseClose','Shutter1StrobePulseClose',200,2,2),
                ('Random','Shutter1StrobeRandom',240,2,10), ('Unknown','Shutter1',250,0,1)]:
                if shared and name == "Random": continue
                functions += f'<ChannelFunction Name="{name}" Attribute="{attr}" DMXFrom="{start}/1" PhysicalFrom="{low}" PhysicalTo="{high}"/>'
            if fidelity:
                functions = '<ChannelFunction Name="Gate" Attribute="Shutter1"><ChannelSet Name="Closed"/><ChannelSet Name="Open" DMXFrom="10/1"/></ChannelFunction>'
                functions += '<ChannelFunction Name="Default" Attribute="Shutter1Strobe" DMXFrom="20/1"/><ChannelFunction Name="OnlyTo" Attribute="Shutter1Strobe" DMXFrom="40/1" PhysicalTo="12"/>'
                functions += '<ChannelFunction Name="Descending" Attribute="Shutter1Strobe" DMXFrom="60/1" PhysicalFrom="20" PhysicalTo="2"/>'
                functions += '<ChannelFunction Name="Narrow" Attribute="Shutter1Strobe" DMXFrom="80/1" PhysicalFrom="2" PhysicalTo="10"><ChannelSet/><ChannelSet Name="Fixed" DMXFrom="90/1" PhysicalFrom="7" PhysicalTo="7"/><ChannelSet Name="Single" DMXFrom="99/1" PhysicalFrom="12" PhysicalTo="12"/></ChannelFunction>'
                functions += '<ChannelFunction Name="Malformed" Attribute="Shutter1Strobe" DMXFrom="100/1" PhysicalTo="nan"/>'
            channels += f'<DMXChannel Offset="{offset}" Geometry="{target}" {declaration}><LogicalChannel Attribute="Shutter1">{functions}</LogicalChannel></DMXChannel>'
    wheels = ''
    if gobo:
        wheels = '<Wheels><Wheel Name="Pattern"><Slot Name="Mask" MediaFileName="pattern"/></Wheel></Wheels>'
        channels += '<DMXChannel Offset="5" Geometry="Base"><LogicalChannel Attribute="Gobo1"><ChannelFunction Attribute="Gobo1" Wheel="Pattern" DMXFrom="0/1"><ChannelSet DMXFrom="0/1" WheelSlotIndex="1"/></ChannelFunction></LogicalChannel></DMXChannel>'
        channels += '<DMXChannel Offset="6" Geometry="Base"><LogicalChannel Attribute="Gobo1PosRotate"><ChannelFunction Attribute="Gobo1PosRotate" Wheel="Pattern" DMXFrom="0/1" PhysicalFrom="30" PhysicalTo="30"/></LogicalChannel></DMXChannel>'
    xml = '<GDTF DataVersion="1.2"><FixtureType Name="Public Shutter Fixture" Manufacturer="Peraviz Tests" FixtureTypeID="40000000-0000-0000-0000-000000000001"><AttributeDefinitions><Attributes>'+xml_attributes+'</Attributes></AttributeDefinitions>'+wheels+'<Models><Model Name="Lens" File="lens" Length="0.02" Width="0.02" Height="0.002"/></Models>'+geometry+'<DMXModes>'+mode('Mode','Base',channels)+'</DMXModes></FixtureType></GDTF>'
    if random_modes:
        for original, replacement in [('Shutter1StrobePulseClose','Shutter1StrobeRandomPulseClose'),('Shutter1StrobePulseOpen','Shutter1StrobeRandomPulseOpen'),('Shutter1StrobePulse','Shutter1StrobeRandomPulse'),('Shutter1Strobe','Shutter1StrobeRandom')]:
            # Replace complete XML attribute values, avoiding recursively rewriting already-random families.
            xml = xml.replace('"'+original+'"','"'+replacement+'"')
        for original,replacement in [('StrobeModeStrobe','StrobeModeRandom'),('StrobeModePulse','StrobeModeRandomPulse'),('StrobeModePulseOpen','StrobeModeRandomPulseOpen'),('StrobeModePulseClose','StrobeModeRandomPulseClose')]: xml=xml.replace('"'+original+'"','"'+replacement+'"')
    xml = xml.replace("Shutter1", "Shutter%d" % shutter_index)
    packed = io.BytesIO()
    with zipfile.ZipFile(packed, 'w') as archive:
        entry(archive, 'description.xml', xml)
        entry(archive, 'models/gltf/lens.glb', lens_glb(simple_opaque=True))
        if gobo: entry(archive, 'wheels/pattern.png', gobo_png())
    addresses = '<Address>1.1</Address>'
    if not shared and not absent:
        for bank in range((outputs-1)//(500//width)+1): addresses += f'<Address break="{bank+1}">{bank+3}.1</Address>'
    source = '<GeneralSceneDescription verMajor="1" verMinor="6"><Scene><Layers><Layer uuid="layer"><ChildList><Fixture uuid="50000000-0000-0000-0000-000000000001" name="Public Shutter"><Matrix>{1,0,0}{0,1,0}{0,0,1}{0,0,3000}</Matrix><GDTFSpec>public.gdtf</GDTFSpec><GDTFMode>Mode</GDTFMode><Addresses>'+addresses+'</Addresses></Fixture></ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    path.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(path,'w') as archive:
        entry(archive, 'GeneralSceneDescription.xml', source)
        entry(archive, 'public.gdtf', packed.getvalue())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path',type=Path)
    parser.add_argument('--outputs',type=int,default=4)
    parser.add_argument('--shutter-index',type=int,default=1)
    for flag in ['shared','split','gobo','absent','random-modes','fidelity','channel-master','conditional-mode']: parser.add_argument('--'+flag,action='store_true')
    args = parser.parse_args()
    generate(args.path,args.outputs,args.shared,args.split,args.gobo,args.absent,args.shutter_index,args.random_modes,args.fidelity,args.channel_master,args.conditional_mode)
