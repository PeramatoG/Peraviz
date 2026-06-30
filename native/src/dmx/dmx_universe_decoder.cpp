#include "dmx_universe_decoder.h"

#include <algorithm>
#include <cmath>

namespace godot {

// Registers the universe decoder methods for GDScript callers.
void PeravizDmxUniverseDecoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_fixture_bindings", "universe_id", "bindings"), &PeravizDmxUniverseDecoder::set_fixture_bindings);
    ClassDB::bind_method(D_METHOD("decode_universe", "universe_id", "current_frame"), &PeravizDmxUniverseDecoder::decode_universe);
    ClassDB::bind_method(D_METHOD("decode_universe_compact", "universe_id", "current_frame"), &PeravizDmxUniverseDecoder::decode_universe_compact);
    ClassDB::bind_method(D_METHOD("set_fixture_render_params", "fixture_id", "render_params"), &PeravizDmxUniverseDecoder::set_fixture_render_params);
    ClassDB::bind_method(D_METHOD("decode_universe_render_ready", "universe_id", "current_frame"), &PeravizDmxUniverseDecoder::decode_universe_render_ready);
    ClassDB::bind_method(D_METHOD("decode_universe_visual_batch", "universe_id", "current_frame"), &PeravizDmxUniverseDecoder::decode_universe_visual_batch);
    ClassDB::bind_method(D_METHOD("clear"), &PeravizDmxUniverseDecoder::clear);
}

// Replaces the flat channel binding table for one universe.
void PeravizDmxUniverseDecoder::set_fixture_bindings(int universe_id, const Array &bindings) {
    std::vector<FixtureChannelBinding> parsed_bindings;
    parsed_bindings.reserve(static_cast<size_t>(bindings.size()));
    for (int64_t i = 0; i < bindings.size(); ++i) {
        const Variant item = bindings[i];
        if (item.get_type() != Variant::DICTIONARY) {
            continue;
        }
        parsed_bindings.push_back(parse_binding(static_cast<Dictionary>(item)));
    }
    bindings_by_universe_[universe_id] = std::move(parsed_bindings);
    previous_frames_by_universe_.erase(universe_id);
}

// Decodes only changed channels from the current universe frame.
Array PeravizDmxUniverseDecoder::decode_universe(int universe_id, const PackedByteArray &current_frame) {
    Array updates;
    const auto bindings_it = bindings_by_universe_.find(universe_id);
    if (bindings_it == bindings_by_universe_.end() || current_frame.is_empty()) {
        previous_frames_by_universe_[universe_id] = current_frame;
        return updates;
    }

    PackedByteArray &previous_frame = previous_frames_by_universe_[universe_id];
    for (const FixtureChannelBinding &binding : bindings_it->second) {
        const int byte_count = bytes_for_bit_depth(binding.bit_depth);
        bool changed = previous_frame.size() != current_frame.size();
        for (int offset = 0; !changed && offset < byte_count; ++offset) {
            const int address = address_for_byte_index(binding, offset);
            const uint8_t current_value = address >= 0 && address < current_frame.size() ? current_frame[address] : 0;
            const uint8_t previous_value = address >= 0 && address < previous_frame.size() ? previous_frame[address] : 0;
            changed = current_value != previous_value;
        }
        if (!changed) {
            continue;
        }

        Dictionary update;
        update["fixture_id"] = binding.fixture_id;
        update["channel_type"] = binding.channel_type;
        const Dictionary channel_value = read_channel_value(current_frame, binding);
        update["normalized_value"] = channel_value.get("normalized_value", 0.0);
        update["raw_value"] = channel_value.get("raw_value", 0);
        update["resolution_bits"] = channel_value.get("resolution_bits", 8);
        update["bytes"] = channel_value.get("bytes", PackedInt32Array());
        updates.append(update);
    }

    previous_frame = current_frame;
    return updates;
}


// Decodes changed fixture channels into a compact fixed-stride float array.
PackedFloat32Array PeravizDmxUniverseDecoder::decode_universe_compact(int universe_id, const PackedByteArray &current_frame) {
    PackedFloat32Array compact_updates;
    const auto bindings_it = bindings_by_universe_.find(universe_id);
    if (bindings_it == bindings_by_universe_.end() || current_frame.is_empty()) {
        previous_frames_by_universe_[universe_id] = current_frame;
        return compact_updates;
    }

    constexpr int channel_count = 13;
    constexpr int stride = 2 + channel_count;
    std::unordered_map<int, int> fixture_offsets;
    PackedByteArray &previous_frame = previous_frames_by_universe_[universe_id];
    compact_updates.append(0.0f);

    for (const FixtureChannelBinding &binding : bindings_it->second) {
        const int compact_index = compact_index_for_channel_type(binding.channel_type);
        if (compact_index < 0) {
            continue;
        }

        const int byte_count = bytes_for_bit_depth(binding.bit_depth);
        bool changed = previous_frame.size() != current_frame.size();
        for (int offset = 0; !changed && offset < byte_count; ++offset) {
            const int address = address_for_byte_index(binding, offset);
            const uint8_t current_value = address >= 0 && address < current_frame.size() ? current_frame[address] : 0;
            const uint8_t previous_value = address >= 0 && address < previous_frame.size() ? previous_frame[address] : 0;
            changed = current_value != previous_value;
        }
        if (!changed) {
            continue;
        }

        int base = 0;
        const auto fixture_it = fixture_offsets.find(binding.fixture_id);
        if (fixture_it == fixture_offsets.end()) {
            base = compact_updates.size();
            fixture_offsets[binding.fixture_id] = base;
            compact_updates.resize(compact_updates.size() + stride);
            compact_updates.set(base, static_cast<float>(binding.fixture_id));
            compact_updates.set(base + 1, 0.0f);
            for (int i = 0; i < channel_count; ++i) {
                compact_updates.set(base + 2 + i, 0.0f);
            }
        } else {
            base = fixture_it->second;
        }

        const int mask = static_cast<int>(compact_updates[base + 1]) | (1 << compact_index);
        compact_updates.set(base + 1, static_cast<float>(mask));
        compact_updates.set(base + 2 + compact_index, static_cast<float>(read_normalized_value(current_frame, binding)));
    }

    if (fixture_offsets.empty()) {
        compact_updates.clear();
    }

    for (const FixtureChannelBinding &binding : bindings_it->second) {
        const int compact_index = compact_index_for_channel_type(binding.channel_type);
        const auto fixture_it = fixture_offsets.find(binding.fixture_id);
        if (compact_index < 0 || fixture_it == fixture_offsets.end()) {
            continue;
        }
        compact_updates.set(fixture_it->second + 2 + compact_index, static_cast<float>(read_normalized_value(current_frame, binding)));
    }

    previous_frame = current_frame;
    if (!compact_updates.is_empty()) {
        compact_updates.set(0, static_cast<float>(fixture_offsets.size()));
    }
    return compact_updates;
}

// Stores static render parameters for a fixture for future render-ready decoding.
void PeravizDmxUniverseDecoder::set_fixture_render_params(int fixture_id, const Dictionary &render_params) {
    FixtureRenderParams params;
    params.luminous_flux = static_cast<double>(render_params.get("luminous_flux", params.luminous_flux));
    params.beam_angle_default = static_cast<double>(render_params.get("beam_angle_default", params.beam_angle_default));
    params.zoom_min_deg = static_cast<double>(render_params.get("zoom_min_deg", params.zoom_min_deg));
    params.zoom_max_deg = static_cast<double>(render_params.get("zoom_max_deg", params.zoom_max_deg));
    params.has_zoom = static_cast<bool>(render_params.get("has_zoom", params.has_zoom));
    params.has_color_temperature = static_cast<bool>(render_params.get("has_color_temperature", params.has_color_temperature));
    params.color_temp_k = static_cast<double>(render_params.get("color_temp_k", params.color_temp_k));
    params.spot_multiplier = static_cast<double>(render_params.get("spot_multiplier", params.spot_multiplier));
    params.beam_multiplier = static_cast<double>(render_params.get("beam_multiplier", params.beam_multiplier));
    render_params_by_fixture_[fixture_id] = params;
}

// Decodes changed fixtures with render-ready light parameters.
PackedFloat32Array PeravizDmxUniverseDecoder::decode_universe_render_ready(int universe_id, const PackedByteArray &current_frame) {
    const PackedFloat32Array compact = decode_universe_compact(universe_id, current_frame);
    if (compact.is_empty()) {
        return compact;
    }

    constexpr int compact_stride = 15;
    constexpr int render_ready_stride = 24;
    PackedFloat32Array out;
    const int fixture_count = static_cast<int>(compact[0]);
    out.resize(1 + (fixture_count * render_ready_stride));
    out.set(0, static_cast<float>(fixture_count));
    int compact_base = 1;
    int out_base = 1;
    for (int i = 0; i < fixture_count; ++i) {
        for (int j = 0; j < compact_stride; ++j) {
            out.set(out_base + j, compact[compact_base + j]);
        }
        const int fixture_id = static_cast<int>(compact[compact_base]);
        const auto params_it = render_params_by_fixture_.find(fixture_id);
        const FixtureRenderParams params = params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams();
        append_render_ready_values(out, compact, compact_base, params);
        compact_base += compact_stride;
        out_base += render_ready_stride;
    }
    return out;
}


// Decodes a universe into a render-ready fixture batch with persistent visual changed masks.
Dictionary PeravizDmxUniverseDecoder::decode_universe_visual_batch(int universe_id, const PackedByteArray &current_frame) {
    constexpr int render_ready_stride = 24;
    constexpr int visual_value_count = 22;
    constexpr float default_epsilon = 0.0001f;
    constexpr float angle_epsilon = 0.01f;

    Dictionary batch;
    PackedInt32Array ids_masks;
    PackedFloat32Array states;

    const PackedFloat32Array compact = decode_universe_render_ready(universe_id, current_frame);
    if (compact.is_empty()) {
        batch["ids_masks"] = ids_masks;
        batch["states"] = states;
        batch["count"] = 0;
        return batch;
    }

    const int fixture_count = static_cast<int>(compact[0]);
    ids_masks.resize(fixture_count * 2);
    states.resize(fixture_count * visual_value_count);

    int output_count = 0;
    int base = 1;
    for (int i = 0; i < fixture_count; ++i) {
        if (base + render_ready_stride > compact.size()) {
            break;
        }
        const int fixture_id = static_cast<int>(compact[base]);
        const float values[visual_value_count] = {
            compact[base + 2],
            compact[base + 3],
            compact[base + 4],
            compact[base + 5],
            compact[base + 6],
            compact[base + 7],
            compact[base + 8],
            compact[base + 9],
            compact[base + 10],
            compact[base + 11],
            compact[base + 12],
            compact[base + 13],
            compact[base + 14],
            compact[base + 15],
            compact[base + 16],
            compact[base + 17],
            compact[base + 18],
            compact[base + 19],
            compact[base + 20],
            compact[base + 21],
            compact[base + 22],
            compact[base + 23],
        };

        FixtureVisualState &previous_state = visual_state_by_fixture_[fixture_id];
        int visual_mask = 0;
        for (int value_index = 0; value_index < visual_value_count; ++value_index) {
            const float epsilon = value_index == 16 || value_index == 15 ? angle_epsilon : default_epsilon;
            if (!previous_state.initialized || visual_value_changed(previous_state.values[value_index], values[value_index], epsilon)) {
                visual_mask |= visual_mask_for_changed_value(value_index);
            }
            previous_state.values[value_index] = values[value_index];
            states.set((output_count * visual_value_count) + value_index, values[value_index]);
        }
        previous_state.initialized = true;

        if (visual_mask != 0) {
            ids_masks.set(output_count * 2, fixture_id);
            ids_masks.set((output_count * 2) + 1, visual_mask);
            ++output_count;
        }
        base += render_ready_stride;
    }

    ids_masks.resize(output_count * 2);
    states.resize(output_count * visual_value_count);
    batch["ids_masks"] = ids_masks;
    batch["states"] = states;
    batch["compact"] = compact;
    batch["count"] = output_count;
    return batch;
}

// Clears all registered bindings and frame history.
void PeravizDmxUniverseDecoder::clear() {
    bindings_by_universe_.clear();
    previous_frames_by_universe_.clear();
    render_params_by_fixture_.clear();
    visual_state_by_fixture_.clear();
}

// Converts a Godot dictionary into a native channel binding.
PeravizDmxUniverseDecoder::FixtureChannelBinding PeravizDmxUniverseDecoder::parse_binding(const Dictionary &binding) {
    FixtureChannelBinding out;
    out.fixture_id = static_cast<int>(static_cast<int64_t>(binding.get("fixture_id", 0)));
    out.start_address = static_cast<int>(static_cast<int64_t>(binding.get("start_address", 0)));
    out.fine_address = static_cast<int>(static_cast<int64_t>(binding.get("fine_address", -1)));
    out.ultra_fine_address = static_cast<int>(static_cast<int64_t>(binding.get("ultra_fine_address", -1)));
    out.channel_type = static_cast<int>(static_cast<int64_t>(binding.get("channel_type", binding.get("type", 0))));
    out.bit_depth = static_cast<int>(static_cast<int64_t>(binding.get("bit_depth", 8)));
    out.scale_min = static_cast<double>(binding.get("scale_min", 0.0));
    out.scale_max = static_cast<double>(binding.get("scale_max", 1.0));
    return out;
}

// Reads a DMX channel and returns normalized, raw, resolution, and byte values.
Dictionary PeravizDmxUniverseDecoder::read_channel_value(const PackedByteArray &frame, const FixtureChannelBinding &binding) {
    const int byte_count = bytes_for_bit_depth(binding.bit_depth);
    uint32_t raw_value = 0;
    uint32_t max_value = 0;
    for (int i = 0; i < byte_count; ++i) {
        const int address = address_for_byte_index(binding, i);
        const uint8_t byte_value = address >= 0 && address < frame.size() ? frame[address] : 0;
        raw_value = (raw_value << 8U) | byte_value;
        max_value = (max_value << 8U) | 0xffU;
    }
    const double normalized = max_value > 0 ? static_cast<double>(raw_value) / static_cast<double>(max_value) : 0.0;
    const double scaled = binding.scale_min + ((binding.scale_max - binding.scale_min) * normalized);

    Dictionary out;
    out["normalized_value"] = std::clamp(scaled, 0.0, 1.0);
    out["raw_value"] = static_cast<int64_t>(raw_value);
    out["resolution_bits"] = byte_count * 8;
    out["bytes"] = read_channel_bytes(frame, binding);
    return out;
}

// Reads a DMX value and scales it to a normalized zero-to-one value.
double PeravizDmxUniverseDecoder::read_normalized_value(const PackedByteArray &frame, const FixtureChannelBinding &binding) {
    const int byte_count = bytes_for_bit_depth(binding.bit_depth);
    uint32_t raw_value = 0;
    uint32_t max_value = 0;
    for (int i = 0; i < byte_count; ++i) {
        const int address = address_for_byte_index(binding, i);
        const uint8_t byte_value = address >= 0 && address < frame.size() ? frame[address] : 0;
        raw_value = (raw_value << 8U) | byte_value;
        max_value = (max_value << 8U) | 0xffU;
    }
    const double normalized = max_value > 0 ? static_cast<double>(raw_value) / static_cast<double>(max_value) : 0.0;
    const double scaled = binding.scale_min + ((binding.scale_max - binding.scale_min) * normalized);
    return std::clamp(scaled, 0.0, 1.0);
}

// Returns the DMX bytes used to compose a native channel value.
PackedInt32Array PeravizDmxUniverseDecoder::read_channel_bytes(const PackedByteArray &frame, const FixtureChannelBinding &binding) {
    PackedInt32Array bytes;
    const int byte_count = bytes_for_bit_depth(binding.bit_depth);
    for (int i = 0; i < byte_count; ++i) {
        const int address = address_for_byte_index(binding, i);
        bytes.append(address >= 0 && address < frame.size() ? frame[address] : 0);
    }
    return bytes;
}

// Resolves the frame address for a coarse, fine, or ultra-fine byte.
int PeravizDmxUniverseDecoder::address_for_byte_index(const FixtureChannelBinding &binding, int byte_index) {
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

// Returns how many DMX bytes are required for the requested channel bit depth.
int PeravizDmxUniverseDecoder::bytes_for_bit_depth(int bit_depth) {
    if (bit_depth <= 8) {
        return 1;
    }
    if (bit_depth <= 16) {
        return 2;
    }
    return 3;
}

// Maps native channel types to compact payload indexes.
int PeravizDmxUniverseDecoder::compact_index_for_channel_type(int channel_type) {
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

// Reads a compact normalized value from a fixture payload.
double PeravizDmxUniverseDecoder::compact_value_at(const PackedFloat32Array &compact, int base, int compact_index) {
    return static_cast<double>(compact[base + 2 + compact_index]);
}


// Checks whether a visual float value changed beyond its render epsilon.
bool PeravizDmxUniverseDecoder::visual_value_changed(float previous_value, float current_value, float epsilon) {
    return std::fabs(previous_value - current_value) > epsilon;
}

// Maps visual batch value indexes to high-level apply changed masks.
int PeravizDmxUniverseDecoder::visual_mask_for_changed_value(int value_index) {
    switch (value_index) {
        case 0: return 1 << 0;
        case 1: return 1 << 1;
        case 2: return 1 << 1;
        case 3: return 1 << 3;
        case 4: return 1 << 2;
        case 5: return 1 << 2;
        case 6: return 1 << 2;
        case 7: return 1 << 4;
        case 8: return 1 << 4;
        case 9: return 1 << 4;
        case 10: return 1 << 5;
        case 11: return 1 << 5;
        case 12: return 1 << 7;
        case 13: return 1 << 0;
        case 14: return 1 << 0;
        case 15: return 1 << 3;
        case 16: return 1 << 3;
        case 17: return 1 << 2;
        case 18: return 1 << 2;
        case 19: return 1 << 2;
        case 20: return 1 << 0;
        case 21: return 1 << 0;
        default: return 0;
    }
}

// Appends render-ready light parameters derived from compact DMX values.
void PeravizDmxUniverseDecoder::append_render_ready_values(PackedFloat32Array &out, const PackedFloat32Array &compact, int base, const FixtureRenderParams &params) {
    constexpr double energy_scale = 0.02;
    constexpr double default_zoom_min = 4.0;
    constexpr double max_beam_angle = 90.0;
    constexpr double beam_intensity_max = 50.0;
    constexpr double cmy_epsilon = 0.0001;

    const int out_base = 1 + ((base - 1) / 15 * 24);
    const double dimmer = std::clamp(compact_value_at(compact, base, 0), 0.0, 1.0);
    const double zoom = std::clamp(compact_value_at(compact, base, 3), 0.0, 1.0);
    const double cyan = std::clamp(compact_value_at(compact, base, 4), 0.0, 1.0);
    const double magenta = std::clamp(compact_value_at(compact, base, 5), 0.0, 1.0);
    const double yellow = std::clamp(compact_value_at(compact, base, 6), 0.0, 1.0);

    double beam_angle = std::clamp(params.beam_angle_default, 0.1, max_beam_angle);
    if (params.has_zoom) {
        double zoom_min = params.zoom_min_deg >= 0.0 ? params.zoom_min_deg : default_zoom_min;
        double zoom_max = params.zoom_max_deg >= 0.0 ? params.zoom_max_deg : max_beam_angle;
        if (zoom_max < zoom_min) {
            std::swap(zoom_min, zoom_max);
        }
        zoom_min = std::clamp(zoom_min, 0.1, max_beam_angle);
        zoom_max = std::clamp(zoom_max, zoom_min, max_beam_angle);
        beam_angle = zoom_min + ((zoom_max - zoom_min) * zoom);
    }

    double red = 1.0;
    double green = 1.0;
    double blue = 1.0;
    const bool has_cmy = cyan > cmy_epsilon || magenta > cmy_epsilon || yellow > cmy_epsilon;
    if (has_cmy) {
        red = 1.0 - cyan;
        green = 1.0 - magenta;
        blue = 1.0 - yellow;
    } else if (params.has_color_temperature) {
        const double clamped_temperature = std::clamp(params.color_temp_k, 1000.0, 12000.0);
        const double warm_factor = std::clamp((3200.0 - clamped_temperature) / (3200.0 - 2000.0), 0.0, 1.0);
        const double cool_factor = std::clamp((clamped_temperature - 8500.0) / (11000.0 - 8500.0), 0.0, 1.0);
        const double tint_mix = std::clamp(std::max(warm_factor, cool_factor) * 0.04, 0.0, 1.0);
        const double t = clamped_temperature / 100.0;
        double kelvin_red = 255.0;
        double kelvin_green = 255.0;
        double kelvin_blue = 255.0;
        if (t <= 66.0) {
            kelvin_green = 99.4708025861 * std::log(t) - 161.1195681661;
            kelvin_blue = t <= 19.0 ? 0.0 : 138.5177312231 * std::log(t - 10.0) - 305.0447927307;
        } else {
            kelvin_red = 329.698727446 * std::pow(t - 60.0, -0.1332047592);
            kelvin_green = 288.1221695283 * std::pow(t - 60.0, -0.0755148492);
        }
        red = 1.0 + ((std::clamp(kelvin_red / 255.0, 0.0, 1.0) - 1.0) * tint_mix);
        green = 1.0 + ((std::clamp(kelvin_green / 255.0, 0.0, 1.0) - 1.0) * tint_mix);
        blue = 1.0 + ((std::clamp(kelvin_blue / 255.0, 0.0, 1.0) - 1.0) * tint_mix);
    }

    const double base_energy = std::max(params.luminous_flux, 0.0) * dimmer * energy_scale;
    out.set(out_base + 15, static_cast<float>(base_energy));
    out.set(out_base + 16, static_cast<float>(base_energy * params.spot_multiplier));
    out.set(out_base + 17, static_cast<float>(beam_angle * 0.5));
    out.set(out_base + 18, static_cast<float>(beam_angle));
    out.set(out_base + 19, static_cast<float>(red));
    out.set(out_base + 20, static_cast<float>(green));
    out.set(out_base + 21, static_cast<float>(blue));
    out.set(out_base + 22, static_cast<float>(std::clamp(dimmer * params.beam_multiplier, 0.0, beam_intensity_max)));
    out.set(out_base + 23, static_cast<float>(dimmer * 4.0));
}

} // namespace godot
