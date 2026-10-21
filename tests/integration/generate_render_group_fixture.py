#!/usr/bin/env python3
"""Generate a compact canonical source with global and independent-pixel selected modes."""
import io
import sys
import zipfile
from pathlib import Path


def channel(offset: int, attribute: str, geometry: str, high: float = 1) -> str:
    """Author a standard selected-mode scalar ChannelFunction."""
    return f'<DMXChannel Offset="{offset}" Geometry="{geometry}"><LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}" DMXFrom="0" PhysicalFrom="0" PhysicalTo="{high}"/></LogicalChannel></DMXChannel>'


def generate(output: Path, pixels: bool = False, sources: int = 1, emission: bool = True) -> None:
    """Retain fifty physical lenses, one emission-only output and a genuine mechanical chain."""
    geometries = []
    for i in range(50):
        position = f'{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{(i % 10)*0.018},{(i // 10)*0.018},0}}'
        geometries.append(f'<Beam Name="Emitter{i}" Model="Lens" Position="{position}" LuminousFlux="320" BeamRadius="0.01" BeamAngle="25" FieldAngle="25" BeamType="Wash"/>')
    if emission:
        geometries.append('<Beam Name="Emission" Model="Lens" LuminousFlux="900" BeamRadius="0.03" BeamType="None"/>')
    common = channel(1, 'Dimmer', 'Root') + channel(2, 'Pan', 'Pan', 180) + channel(3, 'Tilt', 'Tilt', 90) + channel(4, 'Zoom', 'Root', 40)
    global_color = ''.join(channel(5+i, a, 'Root') for i, a in enumerate(['ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    pixel_color = ''.join(channel(5+i*3+c, a, f'Emitter{i}') for i in range(50) for c, a in enumerate(['ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    modes = ''.join(f'<DMXMode Name="{name}" Geometry="Root"><DMXChannels>{common}{color}</DMXChannels></DMXMode>' for name, color in [('Global', global_color), ('Pixels', pixel_color)])
    xml = '<GDTF><FixtureType Name="Synthetic Source"><Models><Model Name="Lens" PrimitiveType="Cylinder" Length="0.02" Width="0.02" Height="0.002"/></Models><Geometries><Geometry Name="Root"><Axis Name="Pan"><Axis Name="Tilt">' + ''.join(geometries) + '</Axis></Axis></Geometry></Geometries><DMXModes>' + modes + '</DMXModes></FixtureType></GDTF>'
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as gdtf:
        gdtf.writestr('description.xml', xml)
    mode = 'Pixels' if pixels else 'Global'
    fixtures = ''.join(f'<Fixture uuid="source-{i+1}" name="Source" Universe="1" Address="{1+16*i}"><GDTFSpec>source.gdtf</GDTFSpec><GDTFMode>{mode}</GDTFMode></Fixture>' for i in range(sources))
    scene = '<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList>' + fixtures + '</ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as mvr:
        mvr.writestr('GeneralSceneDescription.xml', scene)
        mvr.writestr('source.gdtf', buffer.getvalue())


if __name__ == '__main__':
    generate(Path(sys.argv[1]), '--pixels' in sys.argv, 20 if '--load' in sys.argv else 1, '--load' not in sys.argv)
