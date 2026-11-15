#!/usr/bin/env python3
"""Public canonical MVR fixture and independent ZIP/XML preservation checks."""
import hashlib
import re
import sys
import uuid
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
from generate_selection_preview import generate as preview


def fixture_uuid(index: int) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"peraviz-editing-{index}"))


def generate(path: Path, multibreak: bool = False) -> None:
    preview(path)
    with zipfile.ZipFile(path) as archive:
        resources = {name: archive.read(name) for name in archive.namelist()}
    xml = resources.pop("GeneralSceneDescription.xml").decode()
    xml = xml.replace("<GeneralSceneDescription>", '<?xml version="1.0" encoding="UTF-8"?><GeneralSceneDescription verMajor="1" verMinor="6" provider="Synthetic" providerVersion="1" xmlns:x="urn:preserved"><UserData><Data provider="Other"><x:Unrecognized flag="a &amp; b"><![CDATA[<keep>]]></x:Unrecognized></Data></UserData>')
    for legacy in ["preview-layer", "preview-rig", "preview-truss"]:
        xml = xml.replace(f'uuid="{legacy}"', f'uuid="{uuid.uuid5(uuid.NAMESPACE_DNS, legacy)}"')
    for index in range(4):
        xml = xml.replace(f'uuid="preview-{index}"', f'uuid="{fixture_uuid(index)}" x:owner="préservé"')
        xml = xml.replace(f'Universe="1" Address="{1+index*3}"', "")
        xml = xml.replace(f"<FixtureID>{101+index}</FixtureID>", f'<FixtureID>{101+index}</FixtureID><FixtureIDNumeric>{101+index}</FixtureIDNumeric><UnitNumber>{index+1}</UnitNumber><Addresses><Address break="0">{1 if index < 2 else 1+index*3}</Address></Addresses>')
    xml = xml.replace("preview.gdtf", "projecteur-é.gdtf")
    xml = xml.replace("</Fixture>", "<!--unrelated child boundary--></Fixture>")
    for name in list(resources):
        if name.endswith(".gdtf"):
            xml = xml.replace(name, "projecteur-é.gdtf")
            resources["projecteur-é.gdtf"] = resources.pop(name)
    if multibreak:
        xml = re.sub(r"<Addresses>.*?</Addresses>", '<Addresses><Address break="2">1025</Address><Address break="0">1</Address><Address break="1">513</Address></Addresses>', xml)
        import io
        payload = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(resources["projecteur-é.gdtf"])) as old, zipfile.ZipFile(payload, "w", zipfile.ZIP_DEFLATED) as new:
            for name in old.namelist():
                data = old.read(name)
                if name == "description.xml":
                    data = data.replace(b'Offset="2" Geometry="Pan"', b'DMXBreak="2" Offset="1,3" Geometry="Pan"').replace(b'Offset="3" Geometry="Tilt"', b'DMXBreak="3" Offset="2" Geometry="Tilt"')
                new.writestr(name, data)
        resources["projecteur-é.gdtf"] = payload.getvalue()
    resources["vendor/repeated-é.bin"] = bytes(range(256)) * 8192
    resources["vendor/repeated-copy.bin"] = resources["vendor/repeated-é.bin"]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("GeneralSceneDescription.xml", xml)
        for name, data in resources.items():
            archive.writestr(name, data)


def verify(original: Path, exported: Path) -> None:
    with zipfile.ZipFile(original) as before, zipfile.ZipFile(exported) as after:
        assert after.testzip() is None
        assert before.namelist() == after.namelist(), "Archive entry identity/order changed"
        for name in before.namelist():
            if name != "GeneralSceneDescription.xml":
                assert hashlib.sha256(before.read(name)).digest() == hashlib.sha256(after.read(name)).digest(), name
        old = before.read("GeneralSceneDescription.xml")
        new = after.read("GeneralSceneDescription.xml")
        for data in [old, new]:
            root = ET.fromstring(data)
            ids = [node.attrib["uuid"] for node in root.iter() if "uuid" in node.attrib]
            assert len(ids) == len(set(ids))
        strip_flags = lambda data: re.sub(rb"<DMXInvert(?:Pan|Tilt)>[^<]*</DMXInvert(?:Pan|Tilt)>", b"", data)
        assert strip_flags(old) == strip_flags(new), "Unrelated XML bytes changed"
    print("Independent ZIP, resource hashes and XML preservation checks passed")


if __name__ == "__main__":
    if sys.argv[1] == "--verify":
        verify(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        generate(Path(sys.argv[1]), "--multibreak" in sys.argv)
        print(" ".join(fixture_uuid(i) for i in range(4)))
