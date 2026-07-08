#include "runtime/peraviz_visual_runtime_godot.h"

namespace godot {

// Registers the visual runtime methods for GDScript callers.
void PeravizVisualRuntime::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &PeravizVisualRuntime::clear);
    ClassDB::bind_method(D_METHOD("install_compiled_scene", "integers", "floats"), &PeravizVisualRuntime::install_compiled_scene);
    ClassDB::bind_method(D_METHOD("submit_universe_frame", "universe_id", "data"), &PeravizVisualRuntime::submit_universe_frame);
    ClassDB::bind_method(D_METHOD("consume_latest_visual_frame"), &PeravizVisualRuntime::consume_latest_visual_frame);
    ClassDB::bind_method(D_METHOD("get_visual_frame_schema"), &PeravizVisualRuntime::get_visual_frame_schema);
    ClassDB::bind_method(D_METHOD("get_stats"), &PeravizVisualRuntime::get_stats);
}

// Clears all native fixture bindings, render parameters, pending frames, and stats.
void PeravizVisualRuntime::clear() {
    core_.clear();
}

// Installs a compact compiled Dimmer/Pan/Tilt scene without Godot-built semantic dictionaries.
void PeravizVisualRuntime::install_compiled_scene(const PackedInt32Array &integers, const PackedFloat32Array &floats) {
    peraviz::runtime::CompiledRuntimeScene scene;
    if (integers.size() >= 10) {
        peraviz::runtime::CompiledFixtureInstance fixture;
        fixture.fixture_id = integers[0];
        fixture.universe_id = integers[1];
        fixture.start_address = integers[2];
        fixture.luminous_flux = floats.size() > 0 ? floats[0] : fixture.luminous_flux;
        fixture.beam_angle_default = floats.size() > 1 ? floats[1] : fixture.beam_angle_default;
        scene.fixtures.push_back(fixture);
        const int dimmer = integers[3];
        const int pan_coarse = integers[4];
        const int pan_fine = integers[5];
        const int tilt_coarse = integers[6];
        const int tilt_fine = integers[7];
        const int component_id = integers[8];
        const int render_target_id = integers[9];
        scene.source_programs.push_back({1, peraviz::runtime::CompiledSemantic::Dimmer, {{fixture.universe_id, dimmer, 0}}, 0, 255, 0.0, 1.0, "Dimmer", "Dimmer"});
        scene.source_programs.push_back({2, peraviz::runtime::CompiledSemantic::Pan, {{fixture.universe_id, pan_coarse, 0}, {fixture.universe_id, pan_fine, 1}}, 0, 65535, 0.0, 1.0, "Pan", "Pan"});
        scene.source_programs.push_back({3, peraviz::runtime::CompiledSemantic::Tilt, {{fixture.universe_id, tilt_coarse, 0}, {fixture.universe_id, tilt_fine, 1}}, 0, 65535, 0.0, 1.0, "Tilt", "Tilt"});
        scene.properties.push_back({fixture.fixture_id, component_id, render_target_id, peraviz::runtime::CompiledSemantic::Dimmer, {{1, 1.0}}});
        scene.properties.push_back({fixture.fixture_id, component_id, render_target_id, peraviz::runtime::CompiledSemantic::Pan, {{2, 1.0}}});
        scene.properties.push_back({fixture.fixture_id, component_id, render_target_id, peraviz::runtime::CompiledSemantic::Tilt, {{3, 1.0}}});
    }
    core_.install_compiled_scene(scene);
}

// Submits the latest snapshot for a DMX universe.
void PeravizVisualRuntime::submit_universe_frame(int universe_id, const PackedByteArray &data) {
    core_.submit_universe_frame(universe_id, data.ptr(), data.size());
}

// Consumes the latest cooked dirty visual frame as one coherent typed snapshot.
Dictionary PeravizVisualRuntime::consume_latest_visual_frame() {
    const peraviz::runtime::SectionedVisualFrame frame = core_.consume_latest_visual_frame();
    PackedInt32Array descriptors;
    descriptors.resize(static_cast<int64_t>(frame.descriptors.size()));
    for (int64_t index = 0; index < descriptors.size(); ++index) {
        descriptors.set(index, frame.descriptors[static_cast<size_t>(index)]);
    }
    PackedInt32Array integers;
    integers.resize(static_cast<int64_t>(frame.integers.size()));
    for (int64_t index = 0; index < integers.size(); ++index) {
        integers.set(index, frame.integers[static_cast<size_t>(index)]);
    }
    PackedFloat32Array floats;
    floats.resize(static_cast<int64_t>(frame.floats.size()));
    for (int64_t index = 0; index < floats.size(); ++index) {
        floats.set(index, frame.floats[static_cast<size_t>(index)]);
    }
    Dictionary out;
    out["protocol_major"] = frame.protocol_major;
    out["protocol_minor"] = frame.protocol_minor;
    out["schema_generation"] = frame.schema_generation;
    out["descriptors"] = descriptors;
    out["integers"] = integers;
    out["floats"] = floats;
    return out;
}

// Returns the installed section schema for structural registration and validation in Godot.
Dictionary PeravizVisualRuntime::get_visual_frame_schema() const {
    const peraviz::runtime::VisualFrameSchema &schema = core_.schema();
    Array sections;
    for (const peraviz::runtime::VisualSectionSchema &section : schema.sections) {
        Dictionary row;
        row["section_type"] = section.section_type;
        row["row_stride_ints"] = section.row_stride_ints;
        row["row_stride_floats"] = section.row_stride_floats;
        row["flags"] = section.flags;
        sections.push_back(row);
    }
    Dictionary out;
    out["protocol_major"] = schema.protocol_major;
    out["protocol_minor"] = schema.protocol_minor;
    out["schema_generation"] = schema.schema_generation;
    out["sections"] = sections;
    return out;
}

// Returns cumulative native runtime counters for diagnostics.
Dictionary PeravizVisualRuntime::get_stats() const {
    return stats_to_dictionary(core_.stats());
}

// Converts native visual frame stats into a Godot dictionary.
Dictionary PeravizVisualRuntime::stats_to_dictionary(const peraviz::runtime::VisualFrameStats &stats) {
    Dictionary out;
    out["packets_submitted"] = static_cast<int64_t>(stats.packets_submitted);
    out["packets_coalesced"] = static_cast<int64_t>(stats.packets_coalesced);
    out["universes_ignored"] = static_cast<int64_t>(stats.universes_ignored);
    out["universes_considered"] = static_cast<int64_t>(stats.universes_considered);
    out["fixtures_dirty"] = static_cast<int64_t>(stats.fixtures_dirty);
    out["fixtures_skipped"] = static_cast<int64_t>(stats.fixtures_skipped);
    out["changed_transform"] = static_cast<int64_t>(stats.changed_transform);
    out["changed_dimmer"] = static_cast<int64_t>(stats.changed_dimmer);
    out["changed_color"] = static_cast<int64_t>(stats.changed_color);
    out["changed_zoom"] = static_cast<int64_t>(stats.changed_zoom);
    out["changed_gobo"] = static_cast<int64_t>(stats.changed_gobo);
    out["changed_gobo_rotation"] = static_cast<int64_t>(stats.changed_gobo_rotation);
    out["gobo_topology_updates"] = static_cast<int64_t>(stats.gobo_topology_updates);
    out["gobo_parametric_updates"] = static_cast<int64_t>(stats.gobo_parametric_updates);
    return out;
}

} // namespace godot
