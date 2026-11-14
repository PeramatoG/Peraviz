// Verifies exact hierarchy, resource identity and mapped transforms at 10k objects.
int test_large_mvr_hierarchy(const std::filesystem::path &root) {
    const auto source = root / "large-hierarchy.mvr";
    std::string objects;
    for (int group = 0; group < 100; ++group) {
        objects += "<GroupObject uuid=\"group-" + std::to_string(group) +
            "\"><Matrix>{0,0.001,0}{-0.002,0,0}{0,0,-0.003}{1000," + std::to_string(group*1000) +
            ",3000}</Matrix><ChildList>";
        for (int child = 0; child < 100; ++child) {
            const auto id = std::to_string(group*100+child);
            objects += "<SceneObject uuid=\"object-" + id + "\"><Matrix>{1,0,0}{0,1,0}{0,0,1}{" +
                std::to_string(child*1000) + ",0,0}</Matrix><Geometries>" +
                (child % 2 == 0 ? "<Symbol symdef=\"shared\"/>" : "<Geometry3D fileName=\"stage.3ds\"/>") +
                "</Geometries></SceneObject>";
        }
        objects += "</ChildList></GroupObject>";
    }
    const auto xml = "<GeneralSceneDescription><AUXData><Symdef uuid=\"shared\"><ChildList>"
        "<Geometry3D fileName=\"stage.3ds\"/></ChildList></Symdef></AUXData><Scene><Layers><Layer><Matrix>{1,0,0}{0,1,0}{0,0,1}{0,0,2000}</Matrix><ChildList>" +
        objects + "</ChildList></Layer></Layers></Scene></GeneralSceneDescription>";
    {
        peraviz::archive::ZipArchive archive;
        if (!archive.open_create_or_modify(source) || !archive.write_file("GeneralSceneDescription.xml",xml) ||
            !archive.write_file("stage.3ds","geometry") || !archive.close()) return fail("Cannot write large hierarchy MVR");
    }
    const auto scene = peraviz::load_mvr(source.u8string(),false,false);
    if (scene.nodes.size() != 20100 || scene.object_count != 10000 || !scene.fixture_patches.empty())
        return fail("Large hierarchy lost or invented nodes/patches");
    std::unordered_map<std::string, const peraviz::SceneNode *> index;
    std::string shared_path;
    int models = 0;
    for (const auto &node : scene.nodes) {
        if (!index.emplace(node.node_id,&node).second) return fail("Large hierarchy duplicated node identity");
        if (!node.asset_path.empty()) {
            if (shared_path.empty()) shared_path=node.asset_path;
            if (node.asset_path != shared_path || node.local_transform.scale.x != 1.0F ||
                node.local_transform.position.x != 0.0F || node.local_transform.position.y != 0.0F ||
                node.local_transform.position.z != 0.0F) return fail("Symdef/direct geometry identity or local transform changed");
            ++models;
        }
    }
    if (models != 10000 || scene.asset_metrics.extraction_count != 1) return fail("Repeated geometry did not share extraction");
    for (int group = 0; group < 100; ++group) {
        const auto &parent = *index.at("group-"+std::to_string(group));
        const auto &p = parent.local_transform;
        if (!parent.parent_id.empty() || p.position.x != 1 || p.position.y != 5 || p.position.z != -group ||
            p.basis_x.z != -0.001F || p.basis_y.y != -0.003F || p.basis_z.x != 0.002F)
            return fail("Small/reflected/rotated parent basis or mm conversion changed");
        for (int child=0; child<100; ++child) {
            const auto &node = *index.at("object-"+std::to_string(group*100+child));
            const auto &t=node.local_transform;
            const float world_z = p.position.z + p.basis_x.z*t.position.x;
            if (node.parent_id != parent.node_id || t.position.x != child || t.position.y != 0 || t.position.z != 0 ||
                std::abs(world_z - (-float(group)-0.001F*float(child))) > 0.00001F)
                return fail("Nested world translation/hierarchy changed or mm conversion applied twice");
        }
    }
    return 0;
}
