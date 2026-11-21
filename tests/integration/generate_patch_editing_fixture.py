#!/usr/bin/env python3
"""Canonical patch fixtures plus independent field-local archive preservation verification."""
import re
import sys
import zipfile
import hashlib
import uuid
from pathlib import Path
from xml.etree import ElementTree as ET
from generate_mvr_editing_fixture import generate as foundation


def generate(path, multibreak=False, count=4):
    foundation(path, multibreak)
    with zipfile.ZipFile(path) as archive:
        entries = [(i, archive.read(i.filename)) for i in archive.infolist()]
    index = 0
    def fixture(match):
        nonlocal index
        body = match.group()
        body = body.replace('<Addresses>', '<Addresses vendor="keep"><Network geometry="NetworkInOut_1" x:tag="keep">192.0.2.1</Network>')
        if not multibreak:
            body = body.replace('<Address break="0">1</Address>', '<Address x:origin="keep"> \n1\t </Address>', 1)
            if index == 2:
                body = re.sub(r'<Address(?:\s[^>]*)?>.*?</Address>', '<Address break="0">2.1</Address>', body, count=1, flags=re.S)
        index += 1
        return body
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for info, data in entries:
            if info.filename == 'GeneralSceneDescription.xml':
                data = re.sub(r'<Fixture\s[^>]*>.*?</Fixture>', fixture, data.decode(), flags=re.S).encode()
                if count > 4:
                    text = data.decode()
                    matches = list(re.finditer(r'<Fixture\s[^>]*>.*?</Fixture>', text, flags=re.S))
                    template = matches[-1].group()
                    old_id = re.search(r'uuid="([^"]+)"', template).group(1)
                    added = []
                    for number in range(4, count):
                        body = template.replace(old_id, str(uuid.uuid5(uuid.NAMESPACE_DNS, f'peraviz-patch-moderate-{number}')))
                        body = body.replace('Spot 104', f'Spot {101+number}').replace('<FixtureID>104</FixtureID>', f'<FixtureID>{101+number}</FixtureID>')
                        added.append(body)
                    text = text[:matches[-1].end()] + ''.join(added) + text[matches[-1].end():]
                    data = text.encode()
                ET.fromstring(data)
            archive.writestr(info, data)


def verify(before, after):
    with zipfile.ZipFile(before) as a, zipfile.ZipFile(after) as b:
        assert b.testzip() is None
        assert a.namelist() == b.namelist()
        for name in a.namelist():
            if name != 'GeneralSceneDescription.xml':
                assert hashlib.sha256(a.read(name)).digest() == hashlib.sha256(b.read(name)).digest(), name
        x, y = [z.read('GeneralSceneDescription.xml') for z in [a, b]]
        # Only standard Address element values/additions/removals and inversion fields may differ.
        strip = lambda raw: re.sub(rb'<DMXInvert(?:Pan|Tilt)>[^<]*</DMXInvert(?:Pan|Tilt)>|<Address(?:\s[^>]*)?>[^<]*</Address>', b'', raw)
        assert strip(x) == strip(y), 'Unrelated XML, Network, hierarchy or attributes changed'
        for raw in [x, y]:
            ids = [e.attrib['uuid'] for e in ET.fromstring(raw).iter() if 'uuid' in e.attrib]
            assert len(ids) == len(set(ids))
    print('Independent canonical patch XML/resource verification passed')


if __name__ == '__main__':
    if sys.argv[1] == '--verify':
        verify(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        generate(Path(sys.argv[1]), '--multibreak' in sys.argv, int(sys.argv[sys.argv.index('--count')+1]) if '--count' in sys.argv else 4)
