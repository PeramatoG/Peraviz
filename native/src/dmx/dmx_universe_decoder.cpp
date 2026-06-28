#include "dmx_universe_decoder.h"

#include <algorithm>
#include <cmath>

namespace godot {

// Registers the universe decoder methods for GDScript callers.
void PeravizDmxUniverseDecoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_fixture_bindings", "universe_id", "bindings"), &PeravizDmxUniverseDecoder::set_fixture_bindings);
    ClassDB::bind_method(D_METHOD("decode_universe", "universe_id", "current_frame"), &PeravizDmxUniverseDecoder::decode_universe);
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
            const int address = binding.start_address + offset;
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
        update["normalized_value"] = read_normalized_value(current_frame, binding);
        updates.append(update);
    }

    previous_frame = current_frame;
    return updates;
}

// Clears all registered bindings and frame history.
void PeravizDmxUniverseDecoder::clear() {
    bindings_by_universe_.clear();
    previous_frames_by_universe_.clear();
}

// Converts a Godot dictionary into a native channel binding.
PeravizDmxUniverseDecoder::FixtureChannelBinding PeravizDmxUniverseDecoder::parse_binding(const Dictionary &binding) {
    FixtureChannelBinding out;
    out.fixture_id = static_cast<int>(static_cast<int64_t>(binding.get("fixture_id", 0)));
    out.start_address = static_cast<int>(static_cast<int64_t>(binding.get("start_address", 0)));
    out.channel_type = static_cast<int>(static_cast<int64_t>(binding.get("channel_type", binding.get("type", 0))));
    out.bit_depth = static_cast<int>(static_cast<int64_t>(binding.get("bit_depth", 8)));
    out.scale_min = static_cast<double>(binding.get("scale_min", 0.0));
    out.scale_max = static_cast<double>(binding.get("scale_max", 1.0));
    return out;
}

// Reads a DMX value and scales it to a normalized zero-to-one value.
double PeravizDmxUniverseDecoder::read_normalized_value(const PackedByteArray &frame, const FixtureChannelBinding &binding) {
    const int byte_count = bytes_for_bit_depth(binding.bit_depth);
    uint32_t raw_value = 0;
    uint32_t max_value = 0;
    for (int i = 0; i < byte_count; ++i) {
        const int address = binding.start_address + i;
        const uint8_t byte_value = address >= 0 && address < frame.size() ? frame[address] : 0;
        raw_value = (raw_value << 8U) | byte_value;
        max_value = (max_value << 8U) | 0xffU;
    }
    const double normalized = max_value > 0 ? static_cast<double>(raw_value) / static_cast<double>(max_value) : 0.0;
    const double scaled = binding.scale_min + ((binding.scale_max - binding.scale_min) * normalized);
    return std::clamp(scaled, 0.0, 1.0);
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

} // namespace godot
