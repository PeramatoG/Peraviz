// Included by scene_asset_lifetime_test.cpp; only public synthetic ZIP/XML data.

// Creates an archive through the same production MVR loader and native compiler.
peraviz::SceneModel compatibility_scene(const std::filesystem::path &root, const std::string &addresses,
                                       const std::string &channel_break = "", const std::string &extra_geometry = "",
                                       const std::string &custom_channels = "", const std::string &source_geometry = "") {
    const auto gdtf = root / "compatibility.gdtf";
    std::string xml = "<GDTF DataVersion=\"1.2\"><FixtureType Name=\"Compatibility\"><Geometries>"
        "<Geometry Name=\"Root\"><Beam Name=\"Beam\" BeamAngle=\"20\" LuminousFlux=\"1000\"/>" + extra_geometry +
        "</Geometry>" + source_geometry + "</Geometries><DMXModes><DMXMode Name=\"Mode\" Geometry=\"Root\"><DMXChannels>" +
        (custom_channels.empty() ? "<DMXChannel " + channel_break + " Offset=\"1\" Geometry=\"Root\"><LogicalChannel Attribute=\"Dimmer\">"
        "<ChannelFunction Attribute=\"Dimmer\" PhysicalFrom=\"0\" PhysicalTo=\"1\"/></LogicalChannel>"
        "</DMXChannel>" : custom_channels) + "</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>";
    { peraviz::archive::ZipArchive archive; archive.open_create_or_modify(gdtf); archive.write_file("description.xml",xml); archive.close(); }
    const auto mvr = root / "compatibility.mvr";
    const std::string source = "<GeneralSceneDescription verMajor=\"1\" verMinor=\"6\"><Scene><Layers><Layer uuid=\"layer\"><ChildList>"
        "<Fixture uuid=\"10000000-0000-0000-0000-000000000001\"><GDTFSpec>compatibility.gdtf</GDTFSpec><GDTFMode>Mode</GDTFMode>" +
        addresses + "</Fixture></ChildList></Layer></Layers></Scene></GeneralSceneDescription>";
    { peraviz::archive::ZipArchive archive; archive.open_create_or_modify(mvr); archive.write_file("GeneralSceneDescription.xml",source); archive.write_file("compatibility.gdtf",read_binary(gdtf)); archive.close(); }
    return peraviz::load_mvr(mvr.u8string(),false,false);
}

// Verifies production ZIP import, ordered multi-break sources, validation and independent instances.
int test_import_compatibility(const std::filesystem::path &root) {
    using namespace peraviz;
    for (const auto &address : {"1025", "3.1"}) for (int offset : {-1,0}) {
        auto model = compatibility_scene(root,"<Addresses><Address break=\"0\">" + std::string(address) + "</Address></Addresses>");
        auto compiled = gdtf_runtime::compile_runtime_scene(model,offset);
        if (model.fixture_patches.size()!=1 || model.fixture_patches[0].mvr_universe!=3 || model.fixture_patches[0].mvr_address!=1 ||
            compiled.fixtures.size()!=1 || compiled.source_programs.empty() || compiled.source_programs[0].sources[0].universe_id!=3+offset || compiled.source_programs[0].sources[0].address!=0)
            return fail("Standard MVR absolute/string address did not map to the exact native universe/slot");
    }
    const std::string addresses="<Addresses><Address break=\"1\">7.21</Address><Address>3.11</Address></Addresses>";
    auto numbered=compatibility_scene(root,addresses,"DMXBreak=\"2\"");
    auto compiled=gdtf_runtime::compile_runtime_scene(numbered,-1);
    if (compiled.fixtures.size()!=1 || compiled.source_programs.size()!=1 || compiled.source_programs[0].sources[0].universe_id!=6 || compiled.source_programs[0].sources[0].address!=20)
        return fail("Explicit GDTF break 2 did not select MVR break 1 independently of entry order");
    const auto &entries=numbered.fixture_patches[0].addresses;
    if (entries.size()!=2 || entries[0].order!=0 || !entries[0].explicit_break || entries[1].explicit_break || numbered.fixture_patches[0].mvr_universe!=3)
        return fail("Typed ordered patch entries lost default/explicit identity or primary projection");
    for (const auto &invalid : {
        "<Addresses><Address break=\"0\">1</Address><Address break=\"0\">20</Address></Addresses>",
        "<Addresses><Address break=\"-1\">3.1</Address></Addresses>",
        "<Addresses><Address>3.513</Address></Addresses>",
        "<Addresses><Address>3.1junk</Address></Addresses>",
        "<Addresses><Address>9999999999999999</Address></Addresses>",
        "<Addresses><Address Universe=\"4\">3.1</Address></Addresses>",
        "<Addresses><Address>1</Address></Addresses><Addresses><Address>2</Address></Addresses>"}) {
        auto model=compatibility_scene(root,invalid);
        auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        if (!out.fixtures.empty() || out.diagnostics.empty() || out.diagnostics[0].code!="PVZ-MVR-DMX-PATCH-UNSUPPORTED" || model.nodes.empty())
            return fail("Malformed/duplicate MVR entries bypassed native validation or removed source geometry");
    }
    for (const auto &declaration : {"DMXBreak=\"2\"", "DMXBreak=\"Overwrite\"", "DMXBreak=\"0\"", "DMXBreak=\"2junk\""}) {
        auto model=compatibility_scene(root,"<Addresses><Address>3.1</Address></Addresses>",declaration);
        auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        if (!out.source_programs.empty() || out.diagnostics.empty()) return fail("Invalid/unmapped GDTF break silently became break 1");
    }
    const auto channel=[](const std::string &attribute,const std::string &offset,const std::string &break_id,const std::string &extra="") {
        return "<DMXChannel DMXBreak=\""+break_id+"\" Offset=\""+offset+"\" Geometry=\"Pixel\"><LogicalChannel Attribute=\""+attribute+"\"><ChannelFunction Name=\"Value\" Attribute=\""+attribute+"\" PhysicalFrom=\"0\" PhysicalTo=\"1\" "+extra+"/></LogicalChannel></DMXChannel>";
    };
    for (const auto &break_id : {"Overwrite","2"}) {
        const std::string first=std::string(break_id)=="Overwrite" ? "1" : "2";
        const std::string references="<GeometryReference Name=\"A\" Geometry=\"Cell\"><Break DMXBreak=\""+first+"\" DMXOffset=\"3\"/></GeometryReference>"
            "<GeometryReference Name=\"B\" Geometry=\"Cell\"><Break DMXBreak=\"2\" DMXOffset=\"1.9\"/></GeometryReference>";
        const std::string master=std::string(break_id)=="Overwrite" ? "Pixel_Dimmer" : "Pixel_Dimmer.Dimmer.Value";
        const std::string channels=channel("Dimmer","1",break_id)+channel("ColorAdd_R","2",break_id,"ModeMaster=\""+master+"\" ModeFrom=\"128/1\" ModeTo=\"255/1\"");
        auto model=compatibility_scene(root,addresses,"",references,channels,"<Geometry Name=\"Cell\"><Beam Name=\"Pixel\"/></Geometry>");
        auto parsed=gdtf_runtime::compile_gdtf_fixture_type(model.fixture_patches[0].gdtf_path,"Mode");
        auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        if (!parsed.dmx_patch_supported || parsed.channel_programs.size()!=4 || out.fixtures.size()!=1 || out.source_programs.size()!=4)
            return fail("Referenced channels did not compile as independently identified native programs");
        for (const auto &program : out.source_programs) {
            const bool a=program.geometry_name=="Root/A/Cell/Pixel";
            const bool red=program.attribute_name=="ColorAdd_R";
            const bool overwrite=std::string(break_id)=="Overwrite";
            const int expected_universe=a && overwrite ? 2 : 6;
            const int expected_address=(a ? (overwrite ? 12 : 22) : 28)+(red ? 1 : 0);
            if (program.sources[0].universe_id!=expected_universe || program.sources[0].address!=expected_address)
                return fail("Reference source selected the wrong effective break, offset or instance");
            if (red) {
                const auto master=std::find_if(out.source_programs.begin(),out.source_programs.end(),[&](const auto &p){ return p.program_id==program.activation.master_program_id; });
                if (master==out.source_programs.end() || master->geometry_name!=program.geometry_name || master->attribute_name!="Dimmer")
                    return fail("ModeMaster dependency escaped its reference instance");
            }
        }
    }
    {
        const std::string references="<GeometryReference Name=\"A\" Geometry=\"Cell\"><Break DMXBreak=\"2\" DMXOffset=\"3\"/><Break DMXBreak=\"4\" DMXOffset=\"5\"/><Break DMXBreak=\"3\" DMXOffset=\"7\"/></GeometryReference>";
        const auto model=compatibility_scene(root,"<Addresses><Address break=\"1\">7.21</Address><Address break=\"2\">8.31</Address><Address break=\"3\">9.41</Address></Addresses>","",references,
            channel("Dimmer","1","2")+channel("ColorAdd_R","1","4")+channel("ColorAdd_G","2","Overwrite"),"<Geometry Name=\"Cell\"><Beam Name=\"Pixel\"/></Geometry>");
        const auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        if (out.source_programs.size()!=3) return fail("Mixed numbered and Overwrite reference breaks did not compile");
        for (const auto &program : out.source_programs) {
            const int universe=program.attribute_name=="Dimmer" ? 6 : (program.attribute_name=="ColorAdd_R" ? 8 : 7);
            const int slot=program.attribute_name=="Dimmer" ? 22 : (program.attribute_name=="ColorAdd_R" ? 44 : 37);
            if (program.sources[0].universe_id!=universe || program.sources[0].address!=slot) return fail("Reference children lost ordered numbered/final Overwrite correspondence");
        }
    }
    {
        const std::string reference="<GeometryReference Name=\"A\" Geometry=\"Cell\"/>";
        const std::string sources="<Geometry Name=\"Cell\"><GeometryReference Name=\"Inner\" Geometry=\"Leaf\"/></Geometry><Geometry Name=\"Leaf\"><Beam Name=\"Pixel\"/></Geometry>";
        const std::string wiring="<WiringObject Name=\"Connector\"><PinPatch ToWiringObject=\"Other\" FromPin=\"1\" ToPin=\"1\"/></WiringObject>";
        auto ancestor=compatibility_scene(root,addresses,"",reference+wiring,"",sources);
        if (gdtf_runtime::compile_runtime_scene(ancestor,-1).source_programs.empty()) return fail("Non-addressed nested geometry or wiring metadata rejected a valid ancestor control");
        auto nested=compatibility_scene(root,addresses,"",reference,channel("Dimmer","1","Overwrite"),sources);
        if (!gdtf_runtime::compile_runtime_scene(nested,-1).source_programs.empty()) return fail("Nested reference sources bypassed the explicit addressing guard");
    }
    auto sparse=compatibility_scene(root,"<Addresses><Address break=\"7\">9.20</Address></Addresses>","DMXBreak=\"8\"");
    auto sparse_runtime=gdtf_runtime::compile_runtime_scene(sparse,-1);
    if (sparse_runtime.fixtures.size()!=1 || sparse_runtime.source_programs[0].sources[0].universe_id!=8 || sparse_runtime.source_programs[0].sources[0].address!=19)
        return fail("Sparse MVR break 7 was not resolved as GDTF break 8 without a primary-break fallback");
    for (const auto &invalid_offset : {"0","513","1.bad","2.1"}) {
        const std::string reference="<GeometryReference Name=\"A\" Geometry=\"Cell\"><Break DMXOffset=\""+std::string(invalid_offset)+"\"/></GeometryReference>";
        auto model=compatibility_scene(root,addresses,"",reference,channel("Dimmer","1","Overwrite"),"<Geometry Name=\"Cell\"><Beam Name=\"Pixel\"/></Geometry>");
        auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        if (!out.source_programs.empty() || out.diagnostics.empty()) return fail("Invalid or unsupported reference offset bypassed native validation");
    }
    for (const auto &invalid_offset : {"1,junk","1,1","0,2","1,2,3,4,5"}) {
        auto model=compatibility_scene(root,addresses,"","<Beam Name=\"Pixel\"/>",channel("Dimmer",invalid_offset,"2"));
        auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        if (!out.source_programs.empty() || out.diagnostics.empty()) return fail("Malformed/unsupported ordered byte declaration was partially interpreted");
    }
    auto crossing=compatibility_scene(root,"<Addresses><Address>3.512</Address></Addresses>","","<Beam Name=\"Pixel\"/>",channel("Dimmer","1,2","1"));
    if (!gdtf_runtime::compile_runtime_scene(crossing,-1).source_programs.empty()) return fail("Out-of-range fine byte produced a misleading partial coarse-only program");
    for (const auto &offset : {"4,2,3,1","2,1"}) {
        auto model=compatibility_scene(root,addresses,"","<Beam Name=\"Pixel\"/>",channel("Dimmer",offset,"2"));
        auto out=gdtf_runtime::compile_runtime_scene(model,-1);
        const auto &bytes=out.source_programs[0].sources;
        const std::vector<int> expected=std::string(offset)=="2,1" ? std::vector<int>{21,20} : std::vector<int>{23,21,22,20};
        if (bytes.size()!=expected.size()) return fail("Ordered 16/32-bit source width changed");
        for (size_t i=0;i<bytes.size();++i) if (bytes[i].universe_id!=6 || bytes[i].address!=expected[i] || bytes[i].byte_order!=static_cast<int>(i)) return fail("Ordered source bytes lost their coarse/fine order");
    }
    return 0;
}
