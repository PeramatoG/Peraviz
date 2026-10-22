#!/usr/bin/env python3
"""Generate a redistributable MVR/GDTF lifetime smoke fixture."""
from __future__ import annotations
import argparse, json, struct, zipfile, zlib
from pathlib import Path

def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

PNG = (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
       + png_chunk(b"IDAT", zlib.compress(b"\0\xff\xff\xff\xff")) + png_chunk(b"IEND", b""))


def glb() -> bytes:
    binary = struct.pack("<9f3H", 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 2) + b"\0\0"
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"mesh": 0}], "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
           "buffers": [{"byteLength": len(binary)}],
           "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
           "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
                         {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}]}
    payload = json.dumps(doc, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    return (struct.pack("<III", 0x46546C67, 2, 28 + len(payload) + len(binary))
            + struct.pack("<II", len(payload), 0x4E4F534A) + payload
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def chunk(kind: int, payload: bytes) -> bytes:
    return struct.pack("<HI", kind, len(payload) + 6) + payload


def model_3ds() -> bytes:
    material = chunk(0xAFFF, chunk(0xA000, b"surface\0") + chunk(0xA020, chunk(0x0011, bytes([100, 150, 200])))
                     + chunk(0xA200, chunk(0xA300, "texturañ.png".encode() + b"\0")))
    second_material = chunk(0xAFFF, chunk(0xA000, b"second\0") + chunk(0xA020, chunk(0x0010, struct.pack("<3f", 1, 0, 0))))
    objects = material + second_material
    for name, x in [(b"first", 0), (b"second", 2000)]:
        vertices = chunk(0x4110, struct.pack("<H9f", 3, x, 0, 0, x + 1000, 0, 0, x, 1000, 0))
        faces = chunk(0x4120, struct.pack("<H4H", 1, 0, 1, 2, 0) + chunk(0x4130, b"surface\0" + struct.pack("<HH", 1, 0)))
        uv = chunk(0x4140, struct.pack("<H6f", 3, 0, 0, 1, 0, 0, 1))
        objects += chunk(0x4000, name + b"\0" + chunk(0x4100, vertices + faces + uv))
    return chunk(0x4D4D, chunk(0x3D3D, objects))

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    spec = "Fixture @ smoke ü.gdtf"
    gdtf = args.output.parent / spec
    description = '''<GDTF><FixtureType Name="Lifetime Smoke"><Models><Model Name="Base" File="baseñ模型"/><Model Name="Yoke" File="yoke"/></Models><Geometries><Geometry Name="Root" Model="Base"><Axis Name="Yoke" Model="Yoke"><Beam Name="Beam" LuminousFlux="1000" BeamAngle="20"/></Axis></Geometry></Geometries><Wheels><Wheel Name="Gobo Wheel"><Slot Name="Open"/><Slot Name="Star" MediaFileName="star"/></Wheel></Wheels><DMXModes><DMXMode Name="Mode @ Main" Geometry="Root"><DMXChannels><DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Dimmer"><ChannelFunction Attribute="Dimmer" DMXFrom="0" DMXTo="255" PhysicalFrom="0" PhysicalTo="1"/></LogicalChannel></DMXChannel><DMXChannel Offset="2" Geometry="Beam"><LogicalChannel Attribute="Gobo1"><ChannelFunction Attribute="Gobo1" Wheel="Gobo Wheel"><ChannelSet DMXFrom="0" WheelSlotIndex="1"/><ChannelSet DMXFrom="128" WheelSlotIndex="2"/></ChannelFunction></LogicalChannel></DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>'''
    with zipfile.ZipFile(gdtf, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("description.xml", description)
        archive.writestr("models/3ds/baseñ模型.3ds", model_3ds())
        archive.writestr("models/3ds/texturañ.png", PNG)
        archive.writestr("models/gltf/yoke.glb", glb())
        archive.writestr("wheels/star.png", PNG)
    mvr_xml = f'''<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList><Fixture uuid="fixture-one" name="One" Universe="1" Address="1"><GDTFSpec>{spec}</GDTFSpec><GDTFMode>Mode @ Main</GDTFMode></Fixture><Fixture uuid="fixture-two" name="Two" Universe="1" Address="20"><GDTFSpec>{spec}</GDTFSpec><GDTFMode>Mode @ Main</GDTFMode></Fixture><SceneObject uuid="object" name="Escena ñ 模型"><Geometries><Geometry3D fileName="nested/escenañ模型.3ds"/></Geometries></SceneObject></ChildList></Layer></Layers></Scene></GeneralSceneDescription>'''
    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("GeneralSceneDescription.xml", mvr_xml)
        archive.write(gdtf, spec)
        archive.writestr("nested/escenañ模型.3ds", model_3ds())
        archive.writestr("nested/texturañ.png", PNG)
    gdtf.unlink()
    (args.output.parent / "direct.3ds").write_bytes(model_3ds())
    (args.output.parent / "directñ模型.3ds").write_bytes(model_3ds())
    (args.output.parent / "texturañ.png").write_bytes(PNG)
    (args.output.parent / "corrupt.3ds").write_bytes(b"invalid")
    (args.output.parent / "truncated.3ds").write_bytes(model_3ds()[:-1])
    (args.output.parent / "short_chunk.3ds").write_bytes(chunk(0x4D4D, struct.pack("<HI", 0x3D3D, 0)))
    (args.output.parent / "empty.3ds").write_bytes(chunk(0x4D4D, chunk(0x3D3D, b"")))

if __name__ == "__main__":
    main()
