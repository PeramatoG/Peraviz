#!/usr/bin/env python3
"""Package a deterministic fixture for live mode and serialization regressions."""
from io import BytesIO
from pathlib import Path
import sys
from zipfile import ZipFile, ZIP_DEFLATED
from generate_mvr_editing_fixture import fixture_uuid, generate
from generate_patch_editing_fixture import generate as generate_patch_scene


def channel(offset, attribute, geometry, low=0, high=1, number=1):
    return (
        f'<DMXChannel DMXBreak="{number}" Offset="{offset}" Geometry="{geometry}">'
        f'<LogicalChannel Attribute="{attribute}"><ChannelFunction Attribute="{attribute}"'
        f' PhysicalFrom="{low}" PhysicalTo="{high}"/></LogicalChannel></DMXChannel>'
    )


def mode(name, geometry, *channels):
    return f'<DMXMode Name="{name}" Geometry="{geometry}"><DMXChannels>{"".join(channels)}</DMXChannels></DMXMode>'


def create(path, count=4):
    if count == 4:
        generate(path)
    else:
        generate_patch_scene(path, count=count)
    with ZipFile(path) as source:
        contents = {name: source.read(name) for name in source.namelist()}
    if count == 4:
        name = "GeneralSceneDescription.xml"
        xml = contents[name].decode()
        start = xml.index(f'<Fixture uuid="{fixture_uuid(3)}"')
        end = xml.index("</Fixture>", start)
        xml = xml[:start] + xml[start:end].replace(
            "<GDTFMode>Preview 3ch</GDTFMode>", "<GDTFMode>Unavailable source mode</GDTFMode>"
        ) + xml[end:]
        contents[name] = xml.encode().replace(
            b"</Addresses>", b'<Address break="9">9.10</Address></Addresses>', 1
        )
    name = "projecteur-é.gdtf"
    payload = BytesIO()
    with ZipFile(BytesIO(contents[name])) as source, ZipFile(payload, "w", ZIP_DEFLATED) as target:
        for entry in source.namelist():
            data = source.read(entry)
            if entry == "description.xml":
                xml = data.decode()
                xml = xml.replace('Offset="1" Geometry="Head"', 'Offset="1" Geometry="Tilt"')
                xml = xml.replace('</Axis></Axis></Geometry></Geometries>',
                    '<Beam Name="Head2" Model="Head" LuminousFlux="5000" BeamAngle="20" BeamRadius="0.1"/>'
                    '</Axis></Axis></Geometry><Geometry Name="Alternate" Model="Base">'
                    '<Beam Name="AltBeam" Model="Head" LuminousFlux="5000" BeamAngle="20" BeamRadius="0.1"/>'
                    '</Geometry></Geometries>')
                modes = mode("Pixels &amp; Pan", "Base", channel("4,6", "Pan", "Pan", -270, 270),
                    channel("1", "Dimmer", "Head"), channel("8", "Dimmer", "Head2"),
                    channel("2", "ColorAdd_R", "Head"), channel("3", "ColorAdd_R", "Head2"))
                modes += mode("Alternative", "Alternate", channel("1", "Dimmer", "AltBeam"))
                modes += mode("Needs break", "Base", channel("1", "Dimmer", "Head"),
                    channel("1,3", "Pan", "Pan", -270, 270, number=2))
                modes += mode("Duplicate", "Base", channel("1", "Dimmer", "Head")) * 2
                data = xml.replace("</DMXModes>", modes + "</DMXModes>").encode()
            target.writestr(entry, data)
    contents[name] = payload.getvalue()
    with ZipFile(path, "w", ZIP_DEFLATED) as target:
        for name, data in contents.items():
            target.writestr(name, data)


def verify(original, edited):
    with ZipFile(original) as before, ZipFile(edited) as after:
        assert before.namelist() == after.namelist()
        for name in before.namelist():
            data = before.read(name)
            if name == "GeneralSceneDescription.xml":
                data = data.replace(b"<GDTFMode>Preview 3ch</GDTFMode>",
                    b"<GDTFMode>Pixels &amp; Pan</GDTFMode>", 1)
            assert data == after.read(name), name


if __name__ == "__main__":
    if sys.argv[1] == "--verify":
        verify(sys.argv[2], sys.argv[3])
    else:
        create(Path(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else 4)
