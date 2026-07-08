#include "runtime/peraviz_visual_runtime.h"

#include <algorithm>
#include <cmath>

namespace peraviz::runtime {
namespace {

constexpr float kDefaultEpsilon = 0.0001f;
constexpr float kAngleEpsilon = 0.01f;

struct LegacySemanticBinding {
    int channel_type;
    SemanticParameter parameter;
};

constexpr LegacySemanticBinding kLegacySemanticBindings[] = {
    {1, SemanticParameter::Pan}, {2, SemanticParameter::Tilt}, {3, SemanticParameter::Dimmer}, {4, SemanticParameter::Zoom},
    {5, SemanticParameter::Cyan}, {6, SemanticParameter::Magenta}, {7, SemanticParameter::Yellow}, {8, SemanticParameter::GoboSelect},
    {9, SemanticParameter::GoboIndex}, {10, SemanticParameter::GoboRotation}, {11, SemanticParameter::PrismSelect},
    {12, SemanticParameter::PrismRotation}, {13, SemanticParameter::Strobe},
};

// Adds one typed section descriptor to the frame descriptor table.
void append_descriptor(SectionedVisualFrame &frame, VisualSectionType type, int32_t row_count, int32_t int_offset, int32_t float_offset) {
    frame.descriptors.push_back(static_cast<int32_t>(type));
    frame.descriptors.push_back(row_count);
    frame.descriptors.push_back(int_offset);
    frame.descriptors.push_back(float_offset);
    frame.descriptors.push_back(0);
}

} // namespace

// Clears bindings, cached frames, fixture state, and runtime counters.
void PeravizVisualRuntimeCore::clear() {
    universes_.clear();
    render_params_by_fixture_.clear();
    component_state_by_fixture_.clear();
    stats_ = VisualFrameStats();
    schema_ = make_visual_frame_schema(++next_schema_generation_, VisualFrameSchemaCapabilities());
}

// Replaces fixture bindings and compiles them into semantic channel programs.
void PeravizVisualRuntimeCore::set_fixture_bindings(const std::vector<FixtureChannelBinding> &bindings) {
    universes_.clear();
    component_state_by_fixture_.clear();
    VisualFrameSchemaCapabilities capabilities;
    for (const FixtureChannelBinding &binding : bindings) {
        const SemanticParameter parameter = semantic_parameter_for_legacy_channel_type(binding.channel_type);
        if (binding.fixture_id <= 0 || binding.universe_id < 0 || parameter == SemanticParameter::Unknown) {
            continue;
        }
        capabilities.has_transform = capabilities.has_transform || parameter == SemanticParameter::Pan || parameter == SemanticParameter::Tilt;
        capabilities.has_intensity = capabilities.has_intensity || parameter == SemanticParameter::Dimmer;
        capabilities.has_color = capabilities.has_color || parameter == SemanticParameter::Cyan || parameter == SemanticParameter::Magenta || parameter == SemanticParameter::Yellow;
        capabilities.has_optics = capabilities.has_optics || parameter == SemanticParameter::Zoom;
        capabilities.has_wheel_selection = capabilities.has_wheel_selection || parameter == SemanticParameter::GoboSelect || parameter == SemanticParameter::PrismSelect;
        capabilities.has_wheel_motion = capabilities.has_wheel_motion || parameter == SemanticParameter::GoboIndex || parameter == SemanticParameter::GoboRotation || parameter == SemanticParameter::PrismRotation;
        capabilities.has_temporal = capabilities.has_temporal || parameter == SemanticParameter::Strobe;

        UniverseState &universe = universes_[binding.universe_id];
        const int32_t component_id = binding.fixture_id * 100 + static_cast<int32_t>(parameter);
        const int32_t target_id = binding.fixture_id * 1000 + static_cast<int32_t>(parameter);
        const int32_t wheel_id = parameter == SemanticParameter::GoboSelect || parameter == SemanticParameter::GoboIndex || parameter == SemanticParameter::GoboRotation ? 10 : 20;
        universe.programs.push_back({binding, parameter, component_id, target_id, wheel_id});
        const int byte_count = bytes_for_bit_depth(binding.bit_depth);
        for (int byte_index = 0; byte_index < byte_count; ++byte_index) {
            const int address = address_for_byte_index(binding, byte_index);
            if (address >= 0) {
                universe.interest_offsets.push_back(address);
            }
        }
    }
    for (auto &[_, universe] : universes_) {
        std::sort(universe.interest_offsets.begin(), universe.interest_offsets.end());
        universe.interest_offsets.erase(std::unique(universe.interest_offsets.begin(), universe.interest_offsets.end()), universe.interest_offsets.end());
    }
    schema_ = make_visual_frame_schema(++next_schema_generation_, capabilities);
}

// Stores static render parameters used when cooking component render values.
void PeravizVisualRuntimeCore::set_fixture_render_params(int fixture_id, const FixtureRenderParams &params) {
    if (fixture_id > 0) {
        render_params_by_fixture_[fixture_id] = params;
    }
}

// Submits a universe snapshot using latest-wins coalescing.
void PeravizVisualRuntimeCore::submit_universe_frame(int universe_id, const uint8_t *data, int length) {
    ++stats_.packets_submitted;
    auto universe_it = universes_.find(universe_id);
    if (universe_it == universes_.end() || data == nullptr || length <= 0) {
        ++stats_.universes_ignored;
        return;
    }
    UniverseState &universe = universe_it->second;
    if (universe.has_pending_frame) {
        ++stats_.packets_coalesced;
    }
    const int clamped_length = std::clamp(length, 0, 512);
    universe.latest_frame.assign(data, data + clamped_length);
    universe.has_pending_frame = true;
}

// Consumes newest dirty universes and returns one typed sectioned visual frame.
SectionedVisualFrame PeravizVisualRuntimeCore::consume_latest_visual_frame() {
    SectionedVisualFrame frame;
    frame.schema_generation = schema_.schema_generation;
    struct PendingRow {
        int fixture_id = 0;
        uint32_t changed_visual_mask = 0;
        ComponentState state;
    };
    std::vector<PendingRow> rows;

    for (auto &[_, universe] : universes_) {
        if (!universe.has_pending_frame) {
            continue;
        }
        universe.has_pending_frame = false;
        ++stats_.universes_considered;
        const uint64_t interest_hash = compute_interest_hash(universe.latest_frame, universe.interest_offsets);
        if (universe.has_hash && universe.interest_hash == interest_hash) {
            continue;
        }
        universe.has_hash = true;
        universe.interest_hash = interest_hash;

        std::unordered_map<int, ComponentState> pending_by_fixture;
        for (const CompiledChannelProgram &program : universe.programs) {
            ComponentState &state = pending_by_fixture[program.binding.fixture_id];
            auto existing = component_state_by_fixture_.find(program.binding.fixture_id);
            if (!state.initialized && existing != component_state_by_fixture_.end()) {
                state = existing->second;
            }
            apply_semantic_value(state, program.parameter, read_normalized_value(universe.latest_frame, program.binding));
        }

        for (auto &[fixture_id, next_state] : pending_by_fixture) {
            const auto params_it = render_params_by_fixture_.find(fixture_id);
            cook_render_state(next_state, params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams());
            const FixtureChangeResult change = merge_component_state(fixture_id, next_state);
            if (!change.changed) {
                ++stats_.fixtures_skipped;
                continue;
            }
            add_visual_mask_stats(change.changed_visual_mask);
            ++stats_.fixtures_dirty;
            rows.push_back({fixture_id, change.changed_visual_mask, next_state});
        }
    }

    auto section_count_for = [&rows](uint32_t mask) {
        return static_cast<int32_t>(std::count_if(rows.begin(), rows.end(), [mask](const PendingRow &row) { return (row.changed_visual_mask & mask) != 0U; }));
    };

    const int32_t transform_count = section_count_for(VisualChangeTransform);
    if (transform_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeTransform) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id * 100 + 1, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.pan, row.state.tilt});
        }
        append_descriptor(frame, VisualSectionType::GeometryTransform, transform_count, int_offset, float_offset);
    }

    const int32_t intensity_count = section_count_for(VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology);
    if (intensity_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id * 1000 + 3, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.dimmer, row.state.beam_energy, row.state.spot_energy, row.state.beam_intensity, row.state.material_energy});
        }
        append_descriptor(frame, VisualSectionType::EmitterIntensity, intensity_count, int_offset, float_offset);
    }

    const int32_t color_count = section_count_for(VisualChangeColor | VisualChangeMaterial);
    if (color_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeColor | VisualChangeMaterial)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id * 1000 + 5, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.red, row.state.green, row.state.blue});
        }
        append_descriptor(frame, VisualSectionType::EmitterColor, color_count, int_offset, float_offset);
    }

    const int32_t optics_count = section_count_for(VisualChangeZoom | VisualChangeBeamTopology);
    if (optics_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeZoom | VisualChangeBeamTopology)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id * 1000 + 4, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.beam_half_angle, row.state.beam_angle, row.state.zoom});
        }
        append_descriptor(frame, VisualSectionType::BeamOptics, optics_count, int_offset, float_offset);
    }

    const int32_t wheel_selection_count = section_count_for(VisualChangeGobo | VisualChangePrism);
    if (wheel_selection_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeGobo | VisualChangePrism)) == 0U) continue;
            const int32_t wheel_id = (row.changed_visual_mask & VisualChangeGobo) != 0U ? 10 : 20;
            const int32_t resolved_slot = static_cast<int32_t>(std::round(std::clamp(row.state.gobo_select, 0.0f, 1.0f) * 6.0f));
            frame.integers.insert(frame.integers.end(), {row.fixture_id, wheel_id, row.fixture_id * 1000 + wheel_id, resolved_slot, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.push_back(row.state.gobo_select);
        }
        append_descriptor(frame, VisualSectionType::WheelSelection, wheel_selection_count, int_offset, float_offset);
    }

    const int32_t wheel_motion_count = section_count_for(VisualChangeGoboRotation | VisualChangePrism);
    if (wheel_motion_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeGoboRotation | VisualChangePrism)) == 0U) continue;
            const int32_t wheel_id = (row.changed_visual_mask & VisualChangeGoboRotation) != 0U ? 10 : 20;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, wheel_id, static_cast<int32_t>(row.changed_visual_mask), 0});
            frame.floats.insert(frame.floats.end(), {row.state.gobo_index, row.state.gobo_rotation, 0.0f});
        }
        append_descriptor(frame, VisualSectionType::WheelMotion, wheel_motion_count, int_offset, float_offset);
    }

    const int32_t temporal_count = section_count_for(VisualChangeStrobe);
    if (temporal_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeStrobe) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id * 1000 + 13, 0, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.strobe, row.state.dimmer});
        }
        append_descriptor(frame, VisualSectionType::TemporalOutput, temporal_count, int_offset, float_offset);
    }

    frame.stats = stats_;
    return frame;
}

// Returns the immutable schema currently used by emitted sectioned frames.
const VisualFrameSchema &PeravizVisualRuntimeCore::schema() const { return schema_; }

// Returns cumulative runtime counters for debug UI and benchmarks.
const VisualFrameStats &PeravizVisualRuntimeCore::stats() const { return stats_; }

// Maps legacy numeric bindings into compiled semantic parameters until parser-backed programs replace setup input.
SemanticParameter PeravizVisualRuntimeCore::semantic_parameter_for_legacy_channel_type(int channel_type) {
    for (const LegacySemanticBinding &binding : kLegacySemanticBindings) {
        if (binding.channel_type == channel_type) {
            return binding.parameter;
        }
    }
    return SemanticParameter::Unknown;
}

// Returns the byte count required for a channel bit depth.
int PeravizVisualRuntimeCore::bytes_for_bit_depth(int bit_depth) {
    if (bit_depth <= 8) return 1;
    if (bit_depth <= 16) return 2;
    return 3;
}

// Resolves the source byte address for coarse, fine, and ultra-fine channels.
int PeravizVisualRuntimeCore::address_for_byte_index(const FixtureChannelBinding &binding, int byte_index) {
    if (byte_index == 0) return binding.start_address;
    if (byte_index == 1 && binding.fine_address >= 0) return binding.fine_address;
    if (byte_index == 2 && binding.ultra_fine_address >= 0) return binding.ultra_fine_address;
    return binding.start_address + byte_index;
}

// Reads one DMX channel as a scaled normalized value.
float PeravizVisualRuntimeCore::read_normalized_value(const std::vector<uint8_t> &frame, const FixtureChannelBinding &binding) {
    uint32_t raw_value = 0;
    uint32_t max_value = 0;
    const int byte_count = bytes_for_bit_depth(binding.bit_depth);
    for (int byte_index = 0; byte_index < byte_count; ++byte_index) {
        const int address = address_for_byte_index(binding, byte_index);
        const uint8_t value = address >= 0 && address < static_cast<int>(frame.size()) ? frame[static_cast<size_t>(address)] : 0;
        raw_value = (raw_value << 8U) | value;
        max_value = (max_value << 8U) | 0xffU;
    }
    const double normalized = max_value > 0 ? static_cast<double>(raw_value) / static_cast<double>(max_value) : 0.0;
    const double scaled = binding.scale_min + ((binding.scale_max - binding.scale_min) * normalized);
    return static_cast<float>(std::clamp(scaled, 0.0, 1.0));
}

// Computes a native hash over only patched DMX offsets for a universe.
uint64_t PeravizVisualRuntimeCore::compute_interest_hash(const std::vector<uint8_t> &frame, const std::vector<int> &offsets) {
    uint64_t hash = 1469598103934665603ULL;
    for (int offset : offsets) {
        const uint8_t value = offset >= 0 && offset < static_cast<int>(frame.size()) ? frame[static_cast<size_t>(offset)] : 0;
        hash ^= static_cast<uint64_t>(offset & 0xffff);
        hash *= 1099511628211ULL;
        hash ^= static_cast<uint64_t>(value);
        hash *= 1099511628211ULL;
    }
    return hash;
}

// Maps a semantic parameter to the render domains it can dirty.
uint32_t PeravizVisualRuntimeCore::visual_mask_for_parameter(SemanticParameter parameter) {
    switch (parameter) {
        case SemanticParameter::Dimmer: return VisualChangeDimmer | VisualChangeMaterial;
        case SemanticParameter::Pan:
        case SemanticParameter::Tilt: return VisualChangeTransform;
        case SemanticParameter::Zoom: return VisualChangeZoom | VisualChangeBeamTopology;
        case SemanticParameter::Cyan:
        case SemanticParameter::Magenta:
        case SemanticParameter::Yellow: return VisualChangeColor | VisualChangeMaterial;
        case SemanticParameter::GoboSelect:
        case SemanticParameter::GoboIndex: return VisualChangeGobo | VisualChangeBeamTopology;
        case SemanticParameter::GoboRotation: return VisualChangeGoboRotation;
        case SemanticParameter::PrismSelect:
        case SemanticParameter::PrismRotation: return VisualChangePrism;
        case SemanticParameter::Strobe: return VisualChangeStrobe;
        case SemanticParameter::Unknown: return VisualChangeNone;
    }
    return VisualChangeNone;
}


// Writes the incoming semantic value into the component-oriented fixture state.
void PeravizVisualRuntimeCore::apply_semantic_value(ComponentState &state, SemanticParameter parameter, float value) {
    switch (parameter) {
        case SemanticParameter::Pan: state.pan = value; break;
        case SemanticParameter::Tilt: state.tilt = value; break;
        case SemanticParameter::Dimmer: state.dimmer = value; break;
        case SemanticParameter::Zoom: state.zoom = value; break;
        case SemanticParameter::Cyan: state.cyan = value; break;
        case SemanticParameter::Magenta: state.magenta = value; break;
        case SemanticParameter::Yellow: state.yellow = value; break;
        case SemanticParameter::GoboSelect: state.gobo_select = value; break;
        case SemanticParameter::GoboIndex: state.gobo_index = value; break;
        case SemanticParameter::GoboRotation: state.gobo_rotation = value; break;
        case SemanticParameter::PrismSelect: state.prism_select = value; break;
        case SemanticParameter::PrismRotation: state.prism_rotation = value; break;
        case SemanticParameter::Strobe: state.strobe = value; break;
        case SemanticParameter::Unknown: break;
    }
}

// Cooks physical render values from component state without changing semantic ownership.
void PeravizVisualRuntimeCore::cook_render_state(ComponentState &state, const FixtureRenderParams &params) {
    constexpr double energy_scale = 0.02;
    constexpr double default_zoom_min = 4.0;
    constexpr double max_beam_angle = 90.0;
    constexpr double beam_intensity_max = 50.0;
    constexpr double cmy_epsilon = 0.0001;
    double beam_angle = std::clamp(params.beam_angle_default, 0.1, max_beam_angle);
    if (params.has_zoom) {
        double zoom_min = params.zoom_min_deg >= 0.0 ? params.zoom_min_deg : default_zoom_min;
        double zoom_max = params.zoom_max_deg >= 0.0 ? params.zoom_max_deg : max_beam_angle;
        if (zoom_max < zoom_min) std::swap(zoom_min, zoom_max);
        beam_angle = std::clamp(zoom_min + ((zoom_max - zoom_min) * state.zoom), 0.1, max_beam_angle);
    }
    state.red = state.cyan > cmy_epsilon || state.magenta > cmy_epsilon || state.yellow > cmy_epsilon ? 1.0f - state.cyan : 1.0f;
    state.green = state.cyan > cmy_epsilon || state.magenta > cmy_epsilon || state.yellow > cmy_epsilon ? 1.0f - state.magenta : 1.0f;
    state.blue = state.cyan > cmy_epsilon || state.magenta > cmy_epsilon || state.yellow > cmy_epsilon ? 1.0f - state.yellow : 1.0f;
    const double base_energy = std::max(params.luminous_flux, 0.0) * state.dimmer * energy_scale;
    state.beam_energy = static_cast<float>(base_energy);
    state.spot_energy = static_cast<float>(base_energy * params.spot_multiplier);
    state.beam_half_angle = static_cast<float>(beam_angle * 0.5);
    state.beam_angle = static_cast<float>(beam_angle);
    state.beam_intensity = static_cast<float>(std::clamp(state.dimmer * params.beam_multiplier, 0.0, beam_intensity_max));
    state.material_energy = state.dimmer * 4.0f;
}

// Compares two component values using section-appropriate tolerances.
bool PeravizVisualRuntimeCore::nearly_equal(float a, float b, float epsilon) { return std::fabs(a - b) <= epsilon; }

// Adds cumulative per-category visual mask counters for diagnostics.
void PeravizVisualRuntimeCore::add_visual_mask_stats(uint32_t visual_mask) {
    if ((visual_mask & VisualChangeTransform) != 0U) ++stats_.changed_transform;
    if ((visual_mask & VisualChangeDimmer) != 0U) ++stats_.changed_dimmer;
    if ((visual_mask & VisualChangeColor) != 0U) ++stats_.changed_color;
    if ((visual_mask & VisualChangeZoom) != 0U) ++stats_.changed_zoom;
    if ((visual_mask & VisualChangeGobo) != 0U) { ++stats_.changed_gobo; ++stats_.gobo_topology_updates; }
    if ((visual_mask & VisualChangeGoboRotation) != 0U) { ++stats_.changed_gobo_rotation; ++stats_.gobo_parametric_updates; }
}

// Updates cached component state and returns the semantic render domains that changed.
PeravizVisualRuntimeCore::FixtureChangeResult PeravizVisualRuntimeCore::merge_component_state(int fixture_id, const ComponentState &next_state) {
    ComponentState &previous = component_state_by_fixture_[fixture_id];
    FixtureChangeResult result;
    result.changed = !previous.initialized;
    if (!previous.initialized) {
        result.changed_visual_mask = VisualChangeTransform | VisualChangeDimmer | VisualChangeMaterial | VisualChangeColor | VisualChangeZoom | VisualChangeBeamTopology | VisualChangeGobo | VisualChangeGoboRotation | VisualChangePrism | VisualChangeStrobe;
    } else {
        if (!nearly_equal(previous.pan, next_state.pan, kDefaultEpsilon) || !nearly_equal(previous.tilt, next_state.tilt, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::Pan);
        if (!nearly_equal(previous.dimmer, next_state.dimmer, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::Dimmer);
        if (!nearly_equal(previous.zoom, next_state.zoom, kDefaultEpsilon) || !nearly_equal(previous.beam_angle, next_state.beam_angle, kAngleEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::Zoom);
        if (!nearly_equal(previous.cyan, next_state.cyan, kDefaultEpsilon) || !nearly_equal(previous.magenta, next_state.magenta, kDefaultEpsilon) || !nearly_equal(previous.yellow, next_state.yellow, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::Cyan);
        if (!nearly_equal(previous.gobo_select, next_state.gobo_select, kDefaultEpsilon) || !nearly_equal(previous.gobo_index, next_state.gobo_index, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::GoboSelect);
        if (!nearly_equal(previous.gobo_rotation, next_state.gobo_rotation, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::GoboRotation);
        if (!nearly_equal(previous.prism_select, next_state.prism_select, kDefaultEpsilon) || !nearly_equal(previous.prism_rotation, next_state.prism_rotation, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::PrismSelect);
        if (!nearly_equal(previous.strobe, next_state.strobe, kDefaultEpsilon)) result.changed_visual_mask |= visual_mask_for_parameter(SemanticParameter::Strobe);
        const bool previous_visible = previous.dimmer > kDefaultEpsilon;
        const bool current_visible = next_state.dimmer > kDefaultEpsilon;
        if (previous_visible != current_visible) result.changed_visual_mask |= VisualChangeBeamTopology;
        result.changed = result.changed_visual_mask != VisualChangeNone;
    }
    previous = next_state;
    previous.initialized = true;
    return result;
}

} // namespace peraviz::runtime
