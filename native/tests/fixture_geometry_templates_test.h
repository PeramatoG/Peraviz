// Included by the scene asset lifetime suite after its archive/test helpers.

// Compares all imported immutable optical/model fields and instance-local identity/transforms.
bool same_geometry_node(const peraviz::SceneNode &a, const peraviz::SceneNode &b) {
    const auto fields = [](const peraviz::SceneNode &n) {
        return std::tie(n.node_id,n.parent_id,n.name,n.type,n.node_class,n.asset_kind,n.asset_path,
            n.gdtf_source,n.gdtf_fixture_type,n.gdtf_fixture_uuid,n.gdtf_model_name,n.model_dimensions.x,n.model_dimensions.y,n.model_dimensions.z,
            n.primitive_type,n.gdtf_geometry_key,n.gdtf_geometry_path,n.primitive_size_x,n.primitive_size_y,n.primitive_size_z,
            n.is_fixture,n.is_axis,n.is_emitter,n.is_lens,n.is_beam,n.has_luminous_flux,n.luminous_flux,
            n.has_color_temperature,n.color_temperature,n.has_beam_angle,n.beam_angle,n.has_field_angle,n.field_angle,
            n.has_beam_radius,n.beam_radius,n.has_beam_type,n.beam_type,n.has_throw_ratio,n.throw_ratio,
            n.has_rectangle_ratio,n.rectangle_ratio,n.has_dominant_wavelength,n.dominant_wavelength);
    };
    const auto transform = [](const peraviz::SceneTransform &t) {
        return std::tie(t.position.x,t.position.y,t.position.z,t.rotation_degrees.x,t.rotation_degrees.y,t.rotation_degrees.z,
            t.scale.x,t.scale.y,t.scale.z,t.has_basis,t.basis_x.x,t.basis_x.y,t.basis_x.z,
            t.basis_y.x,t.basis_y.y,t.basis_y.z,t.basis_z.x,t.basis_z.y,t.basis_z.z);
    };
    return fields(a)==fields(b) && transform(a.local_transform)==transform(b.local_transform);
}

// Exercises repeated references, overrides, selected roots, setup retirement and file revisions.
int test_fixture_geometry_templates(const std::filesystem::path &root) {
    using namespace peraviz;
    const auto path=root / "generated-template.gdtf";
    const auto write_definition = [&](int revision) {
        std::string references;
        for (int i=0;i<50;++i) references += "<GeometryReference Name=\"Cell"+std::to_string(i)+
            "\" Geometry=\"Module\" Model=\"Override\" Position=\"{1,0,0}{0,1,0}{0,0,1}{"+std::to_string(i*0.001)+",0,0}\"/>";
        const std::string xml="<GDTF><FixtureType><Models><Model Name=\"Override\" PrimitiveType=\"Cylinder\" Length=\"0.02\"/>"
            "</Models><Geometries><Geometry Name=\"Root\"><Axis Name=\"Tilt\">"+references+
            "</Axis></Geometry><Geometry Name=\"Module\" Position=\"{1,0,0}{0,1,0}{0,0,1}{0,0.01,0}\">"
            "<Beam Name=\"Beam\" BeamType=\"Wash\" BeamRadius=\"0.01\" LuminousFlux=\""+std::to_string(revision*320)+
            "\" BeamAngle=\"25\" FieldAngle=\"30\"/></Geometry></Geometries><DMXModes>"
            "<DMXMode Name=\"Full\" Geometry=\"Root\"/><DMXMode Name=\"Module\" Geometry=\"Module\"/>"
            "</DMXModes></FixtureType></GDTF>";
        archive::ZipArchive archive;
        return archive.open_create_or_modify(path) && archive.write_file("description.xml",xml) && archive.close();
    };
    if (!write_definition(1)) return fail("Cannot author geometry template fixture");
    for (int instances : {1,20,100,250}) {
        FixtureGeometryTemplates templates;
        int extracted=0;
        const auto start=std::chrono::steady_clock::now();
        for (int i=0;i<instances;++i) {
            GdtfBuildRequest request{path.u8string(),"Full","uuid-"+std::to_string(i),"Generated"};
            auto actual=templates.instantiate(request,request.fixture_node_id,extracted);
            Matrix parent; parent.o[0]=float(i*1000);
            auto reference=build_fixture_geometry_nodes(request,request.fixture_node_id,parent,extracted);
            if (actual.nodes.size()!=102 || actual.nodes.size()!=reference.nodes.size()) return fail("Repeated references lost physical geometry");
            for (size_t n=0;n<actual.nodes.size();++n)
                if (!same_geometry_node(actual.nodes[n],reference.nodes[n])) return fail("Template changed identity, reference expansion, override, optics or local transform");
        }
        if (templates.definitions()!=1 || templates.hits()!=size_t(instances-1)) return fail("Template setup scaled with instances instead of definitions");
        std::cout << "geometry equivalence instances=" << instances << " definitions=" << templates.definitions()
            << " hits=" << templates.hits() << " comparison_ms=" << std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count() << '\n';
        auto other=templates.instantiate({path.u8string(),"Module","other",""},"other",extracted);
        if (templates.definitions()!=2 || other.nodes.size()!=2) return fail("Selected modes shared an incorrect geometry root");
    }
    int extracted=0;
    FixtureGeometryTemplates first_generation;
    auto first=first_generation.instantiate({path.u8string(),"Module","same",""},"same",extracted);
    if (!write_definition(2)) return fail("Cannot revise geometry archive");
    FixtureGeometryTemplates next_generation;
    auto revised=next_generation.instantiate({path.u8string(),"Module","same",""},"same",extracted);
    if (first.nodes.back().luminous_flux!=320 || revised.nodes.back().luminous_flux!=640 || first.cache_path==revised.cache_path)
        return fail("Scene generation reused stale content after same-filename revision");
    first.nodes.back().luminous_flux=1;
    auto isolated=next_generation.instantiate({path.u8string(),"Module","different",""},"different",extracted);
    if (isolated.nodes.back().luminous_flux!=640 || isolated.nodes.back().node_id==revised.nodes.back().node_id)
        return fail("Mutable fixture-local state leaked into immutable template");
    auto missing_mode = build_fixture_geometry_nodes({path.u8string(),"MissingMode","missing",""},"missing",Matrix{},extracted);
    if (!missing_mode.nodes.empty() || missing_mode.error != "missing_selected_dmx_mode")
        return fail("Unknown selected mode silently chose unrelated root geometry");
    return 0;
}
