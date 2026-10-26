#!/usr/bin/env python3
"""Generate a compact canonical source with global and independent-pixel selected modes."""
import io
import math
import sys
import zipfile
from generate_presentation_lifecycle_fixture import lens_glb, gobo_png
from pathlib import Path


def channel(offset: int, attribute: str, geometry: str, high: float = 1) -> str:
    """Author a standard selected-mode scalar ChannelFunction."""
    return f'<DMXChannel Offset="{offset}" Geometry="{geometry}"><LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}" DMXFrom="0" PhysicalFrom="0" PhysicalTo="{high}"/></LogicalChannel></DMXChannel>'


def generate(output: Path, pixels: bool = False, sources: int = 1, emission: bool = True, wheel: str = "", selected_mode: str = "", transforms: bool = False, independent: bool = False, apertures: bool = False) -> None:
    """Retain fifty physical lenses, one emission-only output and a genuine mechanical chain."""
    geometries = []
    spacing = 0.5 if independent else 0.018
    for i in range(50):
        position = f'{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{(i % 10)*spacing},{(i // 10)*spacing},0}}'
        geometries.append(f'<Beam Name="Emitter{i}" Model="Lens" Position="{position}" LuminousFlux="320" BeamRadius="0.01" BeamAngle="25" FieldAngle="25" BeamType="Wash"/>')
    if wheel == 'basic':
        geometries = []
        emitter = 0
        for ring, (count, radius) in enumerate([(14,0.045),(16,0.084),(20,0.124)]):
            members = []
            for index in range(count):
                angle = 2*math.pi*index/count
                position = f'{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{radius*math.cos(angle)},{radius*math.sin(angle)},0}}'
                members.append(f'<Beam Name="Emitter{emitter}" Model="Lens" Position="{position}" LuminousFlux="320" BeamRadius="0.018" BeamAngle="28" FieldAngle="43.75" BeamType="Wash"/>')
                emitter += 1
            geometries.append(f'<Geometry Name="Ring{ring}">' + ''.join(members) + '</Geometry>')
    if emission:
        geometries.append('<Beam Name="Emission" Model="Lens" LuminousFlux="900" BeamRadius="0.03" BeamType="None"/>')
    common = channel(1, 'Dimmer', 'Root') + channel(2, 'Pan', 'Pan', 180) + channel(3, 'Tilt', 'Tilt', 90) + channel(4, 'Zoom', 'Root', 40)
    global_color = ''.join(channel(5+i, a, 'Root') for i, a in enumerate(['ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    pixel_color = ''.join(channel(5+i*3+c, a, f'Emitter{i}') for i in range(50) for c, a in enumerate(['ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    if independent:
        common = channel(2, 'Pan', 'Pan', 180) + channel(3, 'Tilt', 'Tilt', 90) + channel(4, 'Zoom', 'Root', 40)
        pixel_color = ''.join(channel(5+i*4+c, a, f'Emitter{i}') for i in range(50) for c, a in enumerate(['Dimmer', 'ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    wheel_xml = ''
    if wheel:
        effect = '<PrismFacet/>' if wheel == 'facet' else ''
        media = ' MediaFileName="pattern"' if wheel == 'media' else ' VendorOpticalEffect="Unproven"' if wheel == 'unknown_slot' else ''
        wheel_xml = '<Wheels><Wheel Name="Chromatic"><Slot Name="Open"/><Slot Name="Red" Color="0.64,0.33,0.5"' + media + '>' + effect + '</Slot><Slot Name="Blue" Color="0.15,0.06,0.25"/><Slot Name="Closed" Color="0.3127,0.329,0"/></Wheel></Wheels>'
        attribute = {'index':'Color1WheelIndex','spin':'Color1WheelSpin','random':'Color1WheelRandom','audio':'Color1WheelAudio','gobo':'Gobo1','gobo_motion':'Gobo1Pos','unknown':'ColorNovelEffect','fx':'ColorEffects1'}.get(wheel,'Color1')
        sets = ''.join(f'<ChannelSet DMXFrom="{i*64}" WheelSlotIndex="{i+1}"/>' for i in range(4))
        wheel_channel = lambda offset: f'<DMXChannel Offset="{offset}" Geometry="Root"><LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}" Wheel="Chromatic" DMXFrom="0" PhysicalFrom="0" PhysicalTo="360">{sets}</ChannelFunction></LogicalChannel></DMXChannel>'
        global_color += wheel_channel(8)
        pixel_color += wheel_channel(155)
    modes = ''.join(f'<DMXMode Name="{name}" Geometry="Root"><DMXChannels>{common}{color}</DMXChannels></DMXMode>' for name, color in [('Global', global_color), ('Pixels', pixel_color)])
    if wheel == 'basic':
        # A generic selected-mode counterexample: supported seated selection plus potentially active unsupported modes.
        slots = '<Slot Name="Open"/><Slot Name="Red" Color="0.64,0.33,0.5"/><Slot Name="Blue" Color="0.15,0.06,0.25"/><Slot Name="Closed" Color="0.3127,0.329,0"/>' + ''.join(f'<Slot Name="Tint{i}" Color="0.3127,0.329,0.8"/>' for i in range(33))
        wheel_xml = '<Wheels><Wheel Name="Chromatic">' + slots + '</Wheel></Wheels>'
        def wheel_functions(offset: int, full: bool) -> str:
            sets = ''.join(f'<ChannelSet DMXFrom="{i*(128 if full else 256)//37}" WheelSlotIndex="{i+1}"/>' for i in range(37))
            selection = '<ChannelFunction Attribute="Color1" Wheel="Chromatic" DMXFrom="0" PhysicalFrom="0" PhysicalTo="1">' + sets + '</ChannelFunction>'
            extra = '<ChannelFunction Attribute="Color1WheelSpin" Wheel="Chromatic" DMXFrom="128" PhysicalFrom="-30" PhysicalTo="30"/><ChannelFunction Attribute="ColorEffects1" Wheel="Chromatic" DMXFrom="192"/><ChannelFunction Attribute="NoFeature" DMXFrom="224"/>' if full else ''
            return f'<DMXChannel Offset="{offset}" Geometry="Head"><LogicalChannel Attribute="Color1">{selection}{extra}</LogicalChannel></DMXChannel>'
        head_common = channel(1,'Dimmer','Head') + channel(2,'Pan','Pan',180) + channel(3,'Tilt','Head',90) + channel(4,'Zoom','Head',40)
        rgb = ''.join(channel(5+i,a,'Head') for i,a in enumerate(['ColorAdd_R','ColorAdd_G','ColorAdd_B']))
        ring_rgb = ''.join(channel(5+ring*3+i,a,f'Ring{ring}') for ring in range(3) for i,a in enumerate(['ColorAdd_R','ColorAdd_G','ColorAdd_B']))
        ctc = channel(9,'CTC','Head',6500)
        base_controls = '<DMXChannel Offset="10" Geometry="Root"><LogicalChannel Attribute="Control"><ChannelFunction Attribute="ColorMixReset" DMXFrom="0"/><ChannelFunction Attribute="ColorCalibrationMode" DMXFrom="128"/></LogicalChannel></DMXChannel>'
        basic_controls = head_common+rgb+wheel_functions(8,True).replace('Attribute="ColorEffects1" Wheel="Chromatic"','Attribute="ColorEffects1"')+ctc+base_controls
        variants = [('BrokenControls',basic_controls.replace('Wheel="Chromatic"','Wheel="Absent"')),('BasicControls',basic_controls),('Seated',head_common+rgb+wheel_functions(8,False)+ctc),('Basic',head_common+rgb+wheel_functions(8,True)+ctc),('Extended',head_common+ring_rgb+wheel_functions(14,True)),('ExtendedSeated',head_common+ring_rgb+wheel_functions(14,False))]
        modes = ''.join(f'<DMXMode Name="{name}" Geometry="Root"><DMXChannels>{channels}</DMXChannels></DMXMode>' for name,channels in variants)
    xml = '<GDTF><FixtureType Name="Synthetic Source"><Models><Model Name="Lens" File="lens" PrimitiveType="Cylinder" Length="0.02" Width="0.02" Height="0.002"/></Models><Geometries><Geometry Name="Root"><Axis Name="Pan"><Axis Name="Tilt">' + ''.join(geometries) + '</Axis></Axis></Geometry></Geometries><DMXModes>' + modes + '</DMXModes>' + wheel_xml + '</FixtureType></GDTF>'
    if wheel == 'fx':
        xml = xml.replace(' Wheel="Chromatic"','')
    if wheel == 'missing':
        xml = xml.replace('Wheel="Chromatic"','Wheel="Absent"')
    if wheel == 'basic':
        xml = xml.replace('<Axis Name="Tilt">','<Axis Name="Head">')
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as gdtf:
        if not wheel and not apertures:
            xml = xml.replace(' File="lens"','')
        gdtf.writestr('description.xml', xml)
        if wheel or apertures:
            gdtf.writestr('models/gltf/lens.glb', lens_glb(simple_opaque=apertures))
            if wheel == 'media':
                gdtf.writestr('wheels/pattern.png', gobo_png())
    mode = selected_mode or ('Basic' if wheel == 'basic' else 'Pixels' if pixels else 'Global')
    stride = 256 if independent else 192 if pixels else 16
    fixtures = ''.join(f'<Fixture uuid="source-{i+1}" name="Source" Universe="{1+(stride*i)//512}" Address="{1+(stride*i)%512}">' +
                       (f'<Matrix>{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{i*1000},{i*100},0}}</Matrix>' if transforms else '') +
                       f'<GDTFSpec>source.gdtf</GDTFSpec><GDTFMode>{mode}</GDTFMode></Fixture>' for i in range(sources))
    scene = '<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList>' + fixtures + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as mvr:
        mvr.writestr('GeneralSceneDescription.xml', scene)
        mvr.writestr('source.gdtf', buffer.getvalue())


if __name__ == '__main__':
    generate(Path(sys.argv[1]), '--pixels' in sys.argv, next((int(a.split('=',1)[1]) for a in sys.argv if a.startswith('--instances=')), 20 if '--load' in sys.argv else 1), '--load' not in sys.argv, next((a.split('=',1)[1] for a in sys.argv if a.startswith('--wheel=')), ''), next((a.split('=',1)[1] for a in sys.argv if a.startswith('--mode=')), ''), '--transforms' in sys.argv, '--independent' in sys.argv, '--apertures' in sys.argv)
