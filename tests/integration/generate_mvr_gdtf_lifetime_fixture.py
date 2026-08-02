#!/usr/bin/env python3
"""Generate a redistributable MVR/GDTF lifetime smoke fixture."""
from __future__ import annotations
import argparse, json, struct, zipfile
from pathlib import Path

PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415408d763f8cfc0f01f00050001ff89993d1d0000000049454e44ae426082")

def glb() -> bytes:
    payload = json.dumps({"asset": {"version": "2.0"}, "scene": 0, "scenes": [{}]}, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    return struct.pack("<III", 0x46546C67, 2, 20 + len(payload)) + struct.pack("<II", len(payload), 0x4E4F534A) + payload

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    spec = "Fixture @ smoke ü.gdtf"
    gdtf = args.output.parent / spec
    description = '''<GDTF><FixtureType Name="Lifetime Smoke"><Models><Model Name="Base" File="base"/><Model Name="Yoke" File="yoke"/></Models><Geometries><Geometry Name="Root" Model="Base"><Axis Name="Yoke" Model="Yoke"><Beam Name="Beam" LuminousFlux="1000" BeamAngle="20"/></Axis></Geometry></Geometries><Wheels><Wheel Name="Gobo Wheel"><Slot Name="Open"/><Slot Name="Star" MediaFileName="star"/></Wheel></Wheels><DMXModes><DMXMode Name="Mode @ Main" Geometry="Root"><DMXChannels><DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Dimmer"><ChannelFunction Attribute="Dimmer" DMXFrom="0" DMXTo="255" PhysicalFrom="0" PhysicalTo="1"/></LogicalChannel></DMXChannel><DMXChannel Offset="2" Geometry="Beam"><LogicalChannel Attribute="Gobo1"><ChannelFunction Attribute="Gobo1" Wheel="Gobo Wheel"><ChannelSet DMXFrom="0" WheelSlotIndex="1"/><ChannelSet DMXFrom="128" WheelSlotIndex="2"/></ChannelFunction></LogicalChannel></DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'''
    with zipfile.ZipFile(gdtf, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("description.xml", description)
        archive.writestr("models/gltf/base.glb", glb())
        archive.writestr("models/gltf/yoke.glb", glb())
        archive.writestr("wheels/star.png", PNG)
    mvr_xml = f'''<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList><Fixture uuid="fixture-one" name="One" Universe="1" Address="1"><GDTFSpec>{spec}</GDTFSpec><GDTFMode>Mode @ Main</GDTFMode></Fixture><Fixture uuid="fixture-two" name="Two" Universe="1" Address="20"><GDTFSpec>{spec}</GDTFSpec><GDTFMode>Mode @ Main</GDTFMode></Fixture></ChildList></Layer></Layers></Scene></GeneralSceneDescription>'''
    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("GeneralSceneDescription.xml", mvr_xml)
        archive.write(gdtf, spec)
    gdtf.unlink()

if __name__ == "__main__":
    main()
