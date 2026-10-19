#!/usr/bin/env python3
"""Generate a small fixture for the real application lighting lifecycle test."""
from __future__ import annotations

import argparse
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
    description = '<GDTF><FixtureType Name="Presentation Lifecycle"><Geometries><Geometry Name="Root"><Axis Name="Pan"><Axis Name="Tilt"><Beam Name="Beam" LuminousFlux="1000" BeamAngle="20" BeamRadius="0.05" BeamType="Wash"/></Axis></Axis></Geometry></Geometries><Wheels><Wheel Name="Gobo Wheel"><Slot Name="Open"/><Slot Name="Square" MediaFileName="square"/></Wheel></Wheels><DMXModes><DMXMode Name="Main" Geometry="Root"><DMXChannels>' + ''.join(channels) + '</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as gdtf:
        gdtf.writestr('description.xml', description)
        gdtf.writestr('wheels/square.png', gobo_png())
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
