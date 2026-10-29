// Included by scene_asset_lifetime_test.cpp; only public synthetic ZIP/XML data.

// Creates an archive through the same production MVR loader and native compiler.
peraviz::SceneModel compatibility_scene(const std::filesystem::path &root, const std::string &addresses,
                                       const std::string &channel_break = "", const std::string &extra_geometry = "") {
    const auto gdtf = root / "compatibility.gdtf";
    std::string xml = "<GDTF DataVersion=\"1.2\"><FixtureType Name=\"Compatibility\"><Geometries>"
        "<Geometry Name=\"Root\"><Beam Name=\"Beam\" BeamAngle=\"20\" LuminousFlux=\"1000\"/>" + extra_geometry +
        "</Geometry></Geometries><DMXModes><DMXMode Name=\"Mode\" Geometry=\"Root\"><DMXChannels>"
        "<DMXChannel " + channel_break + " Offset=\"1\" Geometry=\"Root\"><LogicalChannel Attribute=\"Dimmer\">"
        "<ChannelFunction Attribute=\"Dimmer\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/></LogicalChannel>"
        "</DMXChannel></DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>";
    { peraviz::archive::ZipArchive archive; archive.open_create_or_modify(gdtf); archive.write_file("description.xml",xml); archive.close(); }
    const auto mvr = root / "compatibility.mvr";
    const std::string source = "<GeneralSceneDescription verMajor=\"1\" verMinor=\"6\"><Scene><Layers><Layer uuid=\"layer\"><ChildList>"
        "<Fixture uuid=\"10000000-0000-0000-0000-000000000001\"><GDTFSpec>compatibility.gdtf</GDTFSpec><GDTFMode>Mode</GDTFMode>" +
        addresses + "</Fixture></ChildList></Layer></Layers></Scene></GeneralSceneDescription>";
    { peraviz::archive::ZipArchive archive; archive.open_create_or_modify(mvr); archive.write_file("GeneralSceneDescription.xml",source); archive.write_file("compatibility.gdtf",read_binary(gdtf)); archive.close(); }
    return peraviz::load_mvr(mvr.u8string(),false,false);
}

// Verifies standard absolute/string addressing and explicit refusal of unsupported patching.
int test_import_compatibility(const std::filesystem::path &root) {
    using namespace peraviz;
    for (const auto &address : {"1025", "3.1"}) for (int offset : {-1,0}) {
        auto model = compatibility_scene(root,"<Addresses><Address break=\"0\">" + std::string(address) + "</Address></Addresses>");
        auto compiled = gdtf_runtime::compile_runtime_scene(model,offset);
        if (model.fixture_patches.size()!=1 || model.fixture_patches[0].mvr_universe!=3 || model.fixture_patches[0].mvr_address!=1 ||
            compiled.fixtures.size()!=1 || compiled.source_programs.empty() || compiled.source_programs[0].sources[0].universe_id!=3+offset || compiled.source_programs[0].sources[0].address!=0)
            return fail("Standard MVR absolute/string address did not map to the exact native universe/slot");
    }
    for (const auto &addresses : {
        "<Addresses><Address break=\"0\">3.1</Address><Address break=\"1\">5.20</Address></Addresses>",
        "<Addresses><Address break=\"0\">1</Address><Address break=\"0\">20</Address></Addresses>",
        "<Addresses><Address break=\"7\">1025</Address></Addresses>"}) {
        auto model = compatibility_scene(root,addresses);
        auto compiled = gdtf_runtime::compile_runtime_scene(model,-1);
        bool diagnostic = false;
        for (const auto &entry : compiled.diagnostics) if (entry.code=="PVZ-MVR-DMX-PATCH-UNSUPPORTED") diagnostic = true;
        if (!compiled.fixtures.empty() || !compiled.source_programs.empty() || !diagnostic)
            return fail("MVR distinct/duplicate/non-primary breaks were silently collapsed into one native patch");
        if (model.nodes.empty() || model.fixture_patches.size()!=1) return fail("Unsupported DMX removed source geometry/fixture identity");
    }
    for (const auto &declaration : {"DMXBreak=\"2\"", "DMXBreak=\"Overwrite\""}) {
        auto model = compatibility_scene(root,"<Addresses><Address>3.1</Address></Addresses>",declaration);
        auto compiled = gdtf_runtime::compile_runtime_scene(model,-1);
        bool diagnostic = false;
        for (const auto &entry : compiled.diagnostics) if (entry.code=="PVZ-GDTF-DMX-PATCH-UNSUPPORTED") diagnostic = true;
        if (!compiled.source_programs.empty() || !diagnostic) return fail("Unsupported GDTF break was silently compiled as break 1");
    }
    return 0;
}
