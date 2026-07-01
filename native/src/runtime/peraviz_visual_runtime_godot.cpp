#include "runtime/peraviz_visual_runtime_godot.h"

namespace godot {

// Registers the visual runtime methods for GDScript callers.
void PeravizVisualRuntime::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &PeravizVisualRuntime::clear);
    ClassDB::bind_method(D_METHOD("set_fixture_bindings", "bindings"), &PeravizVisualRuntime::set_fixture_bindings);
    ClassDB::bind_method(D_METHOD("set_fixture_render_params", "fixture_id", "render_params"), &PeravizVisualRuntime::set_fixture_render_params);
    ClassDB::bind_method(D_METHOD("submit_universe_frame", "universe_id", "data"), &PeravizVisualRuntime::submit_universe_frame);
    ClassDB::bind_method(D_METHOD("consume_latest_visual_frame"), &PeravizVisualRuntime::consume_latest_visual_frame);
    ClassDB::bind_method(D_METHOD("get_stats"), &PeravizVisualRuntime::get_stats);
}

// Clears all native fixture bindings, render parameters, pending frames, and stats.
void PeravizVisualRuntime::clear() {
    core_.clear();
}

// Replaces the flat fixture binding table used by the native visual cooker.
void PeravizVisualRuntime::set_fixture_bindings(const Array &bindings) {
    std::vector<peraviz::runtime::FixtureChannelBinding> parsed_bindings;
    parsed_bindings.reserve(static_cast<size_t>(bindings.size()));
    for (int64_t index = 0; index < bindings.size(); ++index) {
        const Variant item = bindings[index];
        if (item.get_type() != Variant::DICTIONARY) {
            continue;
        }
        parsed_bindings.push_back(parse_binding(static_cast<Dictionary>(item)));
    }
    core_.set_fixture_bindings(parsed_bindings);
}

// Stores static render parameters for one fixture.
void PeravizVisualRuntime::set_fixture_render_params(int fixture_id, const Dictionary &render_params) {
    core_.set_fixture_render_params(fixture_id, parse_render_params(render_params));
}

// Submits the latest snapshot for a DMX universe.
void PeravizVisualRuntime::submit_universe_frame(int universe_id, const PackedByteArray &data) {
    core_.submit_universe_frame(universe_id, data.ptr(), data.size());
}

// Consumes the latest cooked dirty-fixture visual frame as a fixed-stride float buffer.
PackedFloat32Array PeravizVisualRuntime::consume_latest_visual_frame() {
    const peraviz::runtime::VisualFrame frame = core_.consume_latest_visual_frame();
    PackedFloat32Array out;
    out.resize(static_cast<int64_t>(frame.values.size()));
    for (int64_t index = 0; index < out.size(); ++index) {
        out.set(index, frame.values[static_cast<size_t>(index)]);
    }
    return out;
}

// Returns cumulative native runtime counters for diagnostics.
Dictionary PeravizVisualRuntime::get_stats() const {
    return stats_to_dictionary(core_.stats());
}

// Converts a Godot dictionary into a native fixture binding.
peraviz::runtime::FixtureChannelBinding PeravizVisualRuntime::parse_binding(const Dictionary &binding) {
    peraviz::runtime::FixtureChannelBinding out;
    out.fixture_id = static_cast<int>(static_cast<int64_t>(binding.get("fixture_id", 0)));
    out.universe_id = static_cast<int>(static_cast<int64_t>(binding.get("universe_id", binding.get("artnet_universe_id", 0))));
    out.channel_type = static_cast<int>(static_cast<int64_t>(binding.get("channel_type", binding.get("type", 0))));
    out.start_address = static_cast<int>(static_cast<int64_t>(binding.get("start_address", 0)));
    out.fine_address = static_cast<int>(static_cast<int64_t>(binding.get("fine_address", -1)));
    out.ultra_fine_address = static_cast<int>(static_cast<int64_t>(binding.get("ultra_fine_address", -1)));
    out.bit_depth = static_cast<int>(static_cast<int64_t>(binding.get("bit_depth", 8)));
    out.scale_min = static_cast<double>(binding.get("scale_min", 0.0));
    out.scale_max = static_cast<double>(binding.get("scale_max", 1.0));
    return out;
}

// Converts a Godot dictionary into native render parameters.
peraviz::runtime::FixtureRenderParams PeravizVisualRuntime::parse_render_params(const Dictionary &render_params) {
    peraviz::runtime::FixtureRenderParams params;
    params.luminous_flux = static_cast<double>(render_params.get("luminous_flux", params.luminous_flux));
    params.beam_angle_default = static_cast<double>(render_params.get("beam_angle_default", params.beam_angle_default));
    params.zoom_min_deg = static_cast<double>(render_params.get("zoom_min_deg", params.zoom_min_deg));
    params.zoom_max_deg = static_cast<double>(render_params.get("zoom_max_deg", params.zoom_max_deg));
    params.color_temp_k = static_cast<double>(render_params.get("color_temp_k", params.color_temp_k));
    params.spot_multiplier = static_cast<double>(render_params.get("spot_multiplier", params.spot_multiplier));
    params.beam_multiplier = static_cast<double>(render_params.get("beam_multiplier", params.beam_multiplier));
    params.has_zoom = static_cast<bool>(render_params.get("has_zoom", params.has_zoom));
    params.has_color_temperature = static_cast<bool>(render_params.get("has_color_temperature", params.has_color_temperature));
    return params;
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
