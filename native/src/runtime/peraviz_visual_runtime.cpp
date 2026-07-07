#include "runtime/peraviz_visual_runtime.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace peraviz::runtime {

// Clears bindings, cached frames, fixture state, and runtime counters.
void PeravizVisualRuntimeCore::clear() {
    universes_.clear();
    render_params_by_fixture_.clear();
    fixture_state_by_id_.clear();
    stats_ = VisualFrameStats();
}

// Replaces fixture bindings and precomputes native universe interest offsets.
void PeravizVisualRuntimeCore::set_fixture_bindings(const std::vector<FixtureChannelBinding> &bindings) {
    universes_.clear();
    fixture_state_by_id_.clear();
    for (const FixtureChannelBinding &binding : bindings) {
        if (binding.fixture_id <= 0 || binding.universe_id < 0 || compact_index_for_channel_type(binding.channel_type) < 0) {
            continue;
        }
        UniverseState &universe = universes_[binding.universe_id];
        universe.bindings.push_back(binding);
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
}

// Stores static render parameters used by the cooked visual resolver.
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
        uint32_t changed_channel_mask = 0;
        uint32_t changed_visual_mask = 0;
        std::array<float, kVisualChannelCount> channels {};
        std::array<float, 9> render_values {};
    };
    std::vector<PendingRow> rows;

    for (auto &[universe_id, universe] : universes_) {
        (void)universe_id;
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

        std::unordered_map<int, std::array<float, kVisualChannelCount>> fixture_channels;
        for (const FixtureChannelBinding &binding : universe.bindings) {
            const int compact_index = compact_index_for_channel_type(binding.channel_type);
            if (compact_index < 0) {
                continue;
            }
            auto insert_result = fixture_channels.emplace(binding.fixture_id, std::array<float, kVisualChannelCount>());
            auto &channels = insert_result.first->second;
            if (insert_result.second) {
                const auto state_it = fixture_state_by_id_.find(binding.fixture_id);
                if (state_it != fixture_state_by_id_.end()) {
                    channels = state_it->second.channels;
                }
            }
            channels[compact_index] = read_normalized_value(universe.latest_frame, binding);
        }

        for (const auto &[fixture_id, channels] : fixture_channels) {
            const auto params_it = render_params_by_fixture_.find(fixture_id);
            const FixtureRenderParams params = params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams();
            std::vector<float> render_buffer;
            append_render_values(render_buffer, channels, params);
            std::array<float, 9> render_values {};
            std::copy(render_buffer.begin(), render_buffer.end(), render_values.begin());
            const FixtureChangeResult change = fixture_changed(fixture_id, channels, render_values);
            if (!change.changed) {
                ++stats_.fixtures_skipped;
                continue;
            }
            add_visual_mask_stats(change.changed_visual_mask);
            ++stats_.fixtures_dirty;
            rows.push_back({fixture_id, change.changed_channel_mask, change.changed_visual_mask, channels, render_values});
        }
    }

    auto append_descriptor = [&frame](VisualSectionType type, int32_t row_count, int32_t int_offset, int32_t float_offset) {
        frame.descriptors.push_back(static_cast<int32_t>(type));
        frame.descriptors.push_back(row_count);
        frame.descriptors.push_back(int_offset);
        frame.descriptors.push_back(float_offset);
        frame.descriptors.push_back(0);
    };

    auto section_count_for = [&rows](uint32_t mask) {
        return static_cast<int32_t>(std::count_if(rows.begin(), rows.end(), [mask](const PendingRow &row) { return (row.changed_visual_mask & mask) != 0U; }));
    };

    const int32_t transform_count = section_count_for(VisualChangeTransform);
    if (transform_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeTransform) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.channels[1], row.channels[2]});
        }
        append_descriptor(VisualSectionType::GeometryTransform, transform_count, int_offset, float_offset);
    }

    const int32_t intensity_count = section_count_for(VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology);
    if (intensity_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.channels[0], row.render_values[0], row.render_values[1], row.render_values[7], row.render_values[8]});
        }
        append_descriptor(VisualSectionType::EmitterIntensity, intensity_count, int_offset, float_offset);
    }

    const int32_t color_count = section_count_for(VisualChangeColor | VisualChangeMaterial);
    if (color_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeColor | VisualChangeMaterial)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.render_values[4], row.render_values[5], row.render_values[6]});
        }
        append_descriptor(VisualSectionType::EmitterColor, color_count, int_offset, float_offset);
    }

    const int32_t optics_count = section_count_for(VisualChangeZoom | VisualChangeBeamTopology);
    if (optics_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeZoom | VisualChangeBeamTopology)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.render_values[2], row.render_values[3], row.channels[3]});
        }
        append_descriptor(VisualSectionType::BeamOptics, optics_count, int_offset, float_offset);
    }

    const int32_t wheel_selection_count = section_count_for(VisualChangeGobo | VisualChangePrism);
    if (wheel_selection_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeGobo | VisualChangePrism)) == 0U) continue;
            const int32_t slot = static_cast<int32_t>(std::floor(std::clamp(row.channels[7], 0.0f, 1.0f) * 255.0f));
            frame.integers.insert(frame.integers.end(), {row.fixture_id, 1, row.fixture_id, slot, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.push_back(row.channels[7]);
        }
        append_descriptor(VisualSectionType::WheelSelection, wheel_selection_count, int_offset, float_offset);
    }

    const int32_t wheel_motion_count = section_count_for(VisualChangeGoboRotation | VisualChangePrism);
    if (wheel_motion_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeGoboRotation | VisualChangePrism)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, 1, static_cast<int32_t>(row.changed_visual_mask), 0});
            frame.floats.insert(frame.floats.end(), {row.channels[8], row.channels[9], 0.0f});
        }
        append_descriptor(VisualSectionType::WheelMotion, wheel_motion_count, int_offset, float_offset);
    }

    const int32_t temporal_count = section_count_for(VisualChangeStrobe);
    if (temporal_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeStrobe) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.fixture_id, 0, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.channels[12], row.channels[0]});
        }
        append_descriptor(VisualSectionType::TemporalOutput, temporal_count, int_offset, float_offset);
    }

    frame.stats = stats_;
    return frame;
}

// Returns the immutable schema currently used by emitted sectioned frames.
const VisualFrameSchema &PeravizVisualRuntimeCore::schema() const {
    return schema_;
}

// Returns cumulative runtime counters for debug UI and benchmarks.
const VisualFrameStats &PeravizVisualRuntimeCore::stats() const {
    return stats_;
}

// Maps fixture channel identifiers into fixed visual channel indexes.
int PeravizVisualRuntimeCore::compact_index_for_channel_type(int channel_type) {
    switch (channel_type) {
        case 3: return 0;
        case 1: return 1;
        case 2: return 2;
        case 4: return 3;
        case 5: return 4;
        case 6: return 5;
        case 7: return 6;
        case 8: return 7;
        case 9: return 8;
        case 10: return 9;
        case 11: return 10;
        case 12: return 11;
        case 13: return 12;
        default: return -1;
    }
}

// Returns the byte count required for a channel bit depth.
int PeravizVisualRuntimeCore::bytes_for_bit_depth(int bit_depth) {
    if (bit_depth <= 8) {
        return 1;
    }
    if (bit_depth <= 16) {
        return 2;
    }
    return 3;
}

// Resolves the source byte address for coarse, fine, and ultra-fine channels.
int PeravizVisualRuntimeCore::address_for_byte_index(const FixtureChannelBinding &binding, int byte_index) {
    if (byte_index == 0) {
        return binding.start_address;
    }
    if (byte_index == 1 && binding.fine_address >= 0) {
        return binding.fine_address;
    }
    if (byte_index == 2 && binding.ultra_fine_address >= 0) {
        return binding.ultra_fine_address;
    }
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

// Appends cooked light and material parameters for a fixture channel state.
void PeravizVisualRuntimeCore::append_render_values(std::vector<float> &out, const std::array<float, kVisualChannelCount> &channels, const FixtureRenderParams &params) {
    constexpr double energy_scale = 0.02;
    constexpr double default_zoom_min = 4.0;
    constexpr double max_beam_angle = 90.0;
    constexpr double beam_intensity_max = 50.0;
    constexpr double cmy_epsilon = 0.0001;

    const double dimmer = std::clamp(static_cast<double>(channels[0]), 0.0, 1.0);
    const double zoom = std::clamp(static_cast<double>(channels[3]), 0.0, 1.0);
    const double cyan = std::clamp(static_cast<double>(channels[4]), 0.0, 1.0);
    const double magenta = std::clamp(static_cast<double>(channels[5]), 0.0, 1.0);
    const double yellow = std::clamp(static_cast<double>(channels[6]), 0.0, 1.0);

    double beam_angle = std::clamp(params.beam_angle_default, 0.1, max_beam_angle);
    if (params.has_zoom) {
        double zoom_min = params.zoom_min_deg >= 0.0 ? params.zoom_min_deg : default_zoom_min;
        double zoom_max = params.zoom_max_deg >= 0.0 ? params.zoom_max_deg : max_beam_angle;
        if (zoom_max < zoom_min) {
            std::swap(zoom_min, zoom_max);
        }
        beam_angle = std::clamp(zoom_min + ((zoom_max - zoom_min) * zoom), 0.1, max_beam_angle);
    }

    double red = 1.0;
    double green = 1.0;
    double blue = 1.0;
    if (cyan > cmy_epsilon || magenta > cmy_epsilon || yellow > cmy_epsilon) {
        red = 1.0 - cyan;
        green = 1.0 - magenta;
        blue = 1.0 - yellow;
    }

    const double base_energy = std::max(params.luminous_flux, 0.0) * dimmer * energy_scale;
    out = {static_cast<float>(base_energy),
           static_cast<float>(base_energy * params.spot_multiplier),
           static_cast<float>(beam_angle * 0.5),
           static_cast<float>(beam_angle),
           static_cast<float>(red),
           static_cast<float>(green),
           static_cast<float>(blue),
           static_cast<float>(std::clamp(dimmer * params.beam_multiplier, 0.0, beam_intensity_max)),
           static_cast<float>(dimmer * 4.0)};
}

// Maps a changed channel index to semantic visual apply categories.
uint32_t PeravizVisualRuntimeCore::visual_mask_for_channel_index(size_t channel_index) {
    switch (static_cast<VisualChannel>(channel_index)) {
        case VisualChannel::Dimmer:
            return VisualChangeDimmer | VisualChangeMaterial;
        case VisualChannel::Pan:
        case VisualChannel::Tilt:
            return VisualChangeTransform;
        case VisualChannel::Zoom:
            return VisualChangeZoom | VisualChangeBeamTopology;
        case VisualChannel::Cyan:
        case VisualChannel::Magenta:
        case VisualChannel::Yellow:
            return VisualChangeColor | VisualChangeMaterial;
        case VisualChannel::Gobo:
        case VisualChannel::GoboIndex:
            return VisualChangeGobo | VisualChangeBeamTopology;
        case VisualChannel::GoboRotation:
            return VisualChangeGoboRotation;
        case VisualChannel::Prism:
        case VisualChannel::PrismRotation:
            return VisualChangePrism;
        case VisualChannel::Strobe:
            return VisualChangeStrobe;
        default:
            return VisualChangeNone;
    }
}

// Maps changed cooked render indexes to semantic visual apply categories.
uint32_t PeravizVisualRuntimeCore::visual_mask_for_render_index(size_t render_index) {
    switch (render_index) {
        case 0:
        case 1:
        case 7:
        case 8:
            return VisualChangeDimmer | VisualChangeMaterial;
        case 2:
        case 3:
            return VisualChangeZoom | VisualChangeBeamTopology;
        case 4:
        case 5:
        case 6:
            return VisualChangeColor | VisualChangeMaterial;
        default:
            return VisualChangeNone;
    }
}

// Adds cumulative per-category visual mask counters for diagnostics.
void PeravizVisualRuntimeCore::add_visual_mask_stats(uint32_t visual_mask) {
    if ((visual_mask & VisualChangeTransform) != 0U) {
        ++stats_.changed_transform;
    }
    if ((visual_mask & VisualChangeDimmer) != 0U) {
        ++stats_.changed_dimmer;
    }
    if ((visual_mask & VisualChangeColor) != 0U) {
        ++stats_.changed_color;
    }
    if ((visual_mask & VisualChangeZoom) != 0U) {
        ++stats_.changed_zoom;
    }
    if ((visual_mask & VisualChangeGobo) != 0U) {
        ++stats_.changed_gobo;
        ++stats_.gobo_topology_updates;
    }
    if ((visual_mask & VisualChangeGoboRotation) != 0U) {
        ++stats_.changed_gobo_rotation;
        ++stats_.gobo_parametric_updates;
    }
}

// Updates cached fixture state and returns real changed channel and visual masks.
PeravizVisualRuntimeCore::FixtureChangeResult PeravizVisualRuntimeCore::fixture_changed(int fixture_id, const std::array<float, kVisualChannelCount> &channels, const std::array<float, 9> &render_values) {
    constexpr float default_epsilon = 0.0001f;
    constexpr float angle_epsilon = 0.01f;
    FixtureState &state = fixture_state_by_id_[fixture_id];
    FixtureChangeResult result;
    result.changed = !state.initialized;
    if (!state.initialized) {
        for (size_t index = 0; index < channels.size(); ++index) {
            result.changed_channel_mask |= 1U << index;
            result.changed_visual_mask |= visual_mask_for_channel_index(index);
        }
        for (size_t index = 0; index < render_values.size(); ++index) {
            result.changed_visual_mask |= visual_mask_for_render_index(index);
        }
    } else {
        for (size_t index = 0; index < channels.size(); ++index) {
            if (std::fabs(state.channels[index] - channels[index]) > default_epsilon) {
                result.changed = true;
                result.changed_channel_mask |= 1U << index;
                result.changed_visual_mask |= visual_mask_for_channel_index(index);
            }
        }
        for (size_t index = 0; index < render_values.size(); ++index) {
            const float epsilon = (index == 2 || index == 3) ? angle_epsilon : default_epsilon;
            if (std::fabs(state.render_values[index] - render_values[index]) > epsilon) {
                result.changed = true;
                result.changed_visual_mask |= visual_mask_for_render_index(index);
            }
        }
    }
    const bool previous_visible = state.initialized && state.channels[static_cast<size_t>(VisualChannel::Dimmer)] > default_epsilon;
    const bool current_visible = channels[static_cast<size_t>(VisualChannel::Dimmer)] > default_epsilon;
    if (state.initialized && previous_visible != current_visible) {
        result.changed_visual_mask |= VisualChangeBeamTopology;
    }

    state.channels = channels;
    state.render_values = render_values;
    state.initialized = true;
    return result;
}

} // namespace peraviz::runtime
