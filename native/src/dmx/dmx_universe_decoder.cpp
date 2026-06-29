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

    previous_frame = current_frame;
    if (fixture_offsets.empty()) {
        compact_updates.clear();
        return compact_updates;
    }
    compact_updates.set(0, static_cast<float>(fixture_offsets.size()));
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
    params.color_temp_k = static_cast<double>(render_params.get("color_temp_k", params.color_temp_k));
    params.spot_multiplier = static_cast<double>(render_params.get("spot_multiplier", params.spot_multiplier));
    params.beam_multiplier = static_cast<double>(render_params.get("beam_multiplier", params.beam_multiplier));
    render_params_by_fixture_[fixture_id] = params;
}

// Reserves an API entry point for future render-ready fixture decoding.
PackedFloat32Array PeravizDmxUniverseDecoder::decode_universe_render_ready(int universe_id, const PackedByteArray &current_frame) {
    // TODO: Return light energy, spot angle, and color values directly from native decoding.
    return decode_universe_compact(universe_id, current_frame);
}

// Clears all registered bindings and frame history.
void PeravizDmxUniverseDecoder::clear() {
    bindings_by_universe_.clear();
    previous_frames_by_universe_.clear();
    render_params_by_fixture_.clear();
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

} // namespace godot
