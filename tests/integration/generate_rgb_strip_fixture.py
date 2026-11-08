#!/usr/bin/env python3
"""Generate a one metre, 60-reference Glow strip with exactly 180 RGB slots."""
import io
import sys
import zipfile
from pathlib import Path
from generate_presentation_lifecycle_fixture import lens_glb
from generate_render_group_fixture import channel


def generate(output: Path) -> None:
    references = ''.join(
        f'<GeometryReference Name="Pixel{i}" Geometry="Pixel" Position="{{1,0,0}}{{0,1,0}}{{0,0,1}}{{{i/60},0,0}}"><Break DMXBreak="1" DMXOffset="{1+3*i}"/></GeometryReference>'
        for i in range(60))
    rgb = ''.join(channel(1+i, attribute, 'Lens').replace('<DMXChannel ', '<DMXChannel DMXBreak="Overwrite" ')
                  for i, attribute in enumerate(['ColorAdd_R', 'ColorAdd_G', 'ColorAdd_B']))
    description = ('<GDTF><FixtureType Name="RGB Strip"><Models><Model Name="LensModel" File="lens" Length="0.012" Width="0.012" Height="0.002"/></Models>'
                   '<Geometries><Geometry Name="Root">' + references + '</Geometry><Geometry Name="Pixel"><Beam Name="Lens" Model="LensModel" BeamType="Glow" LuminousFlux="20" BeamRadius="0.006"/></Geometry></Geometries>'
                   '<DMXModes><DMXMode Name="RGB_180ch" Geometry="Root"><DMXChannels>' + rgb + '</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>')
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as gdtf:
        gdtf.writestr('description.xml', description)
        gdtf.writestr('models/gltf/lens.glb', lens_glb())
    scene = '<GeneralSceneDescription><Scene><Layers><Layer uuid="layer"><ChildList><Fixture uuid="strip" name="Strip" Universe="1" Address="1"><GDTFSpec>strip.gdtf</GDTFSpec><GDTFMode>RGB_180ch</GDTFMode></Fixture></ChildList></Layer></Layers></Scene></GeneralSceneDescription>'
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as mvr:
        mvr.writestr('GeneralSceneDescription.xml', scene)
        mvr.writestr('strip.gdtf', data.getvalue())


if __name__ == '__main__':
    generate(Path(sys.argv[1]))
