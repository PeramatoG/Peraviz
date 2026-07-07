#pragma once

#include "runtime/visual_frame_schema.h"

#include <array>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace peraviz::runtime {

class PeravizVisualRuntimeCore {
public:
    void clear();
    void set_fixture_bindings(const std::vector<FixtureChannelBinding> &bindings);
    void set_fixture_render_params(int fixture_id, const FixtureRenderParams &params);
    void submit_universe_frame(int universe_id, const uint8_t *data, int length);
    SectionedVisualFrame consume_latest_visual_frame();
    const VisualFrameSchema &schema() const;
    const VisualFrameStats &stats() const;

private:
    static constexpr size_t kRuntimeControlCount = 13;
    enum RuntimeControl : size_t { Dimmer = 0, Pan = 1, Tilt = 2, Zoom = 3, Cyan = 4, Magenta = 5, Yellow = 6, Gobo = 7, GoboIndex = 8, GoboRotation = 9, Prism = 10, PrismRotation = 11, Strobe = 12 };
    struct UniverseState {
        std::vector<FixtureChannelBinding> bindings;
        std::vector<int> interest_offsets;
        std::vector<uint8_t> latest_frame;
        uint64_t interest_hash = 0;
        bool has_pending_frame = false;
        bool has_hash = false;
    };

    struct FixtureState {
        std::array<float, kRuntimeControlCount> channels {};
        std::array<float, 9> render_values {};
        bool initialized = false;
    };

    struct FixtureChangeResult {
        bool changed = false;
        uint32_t changed_channel_mask = 0;
        uint32_t changed_visual_mask = 0;
    };

    static int control_index_for_channel_type(int channel_type);
    static int bytes_for_bit_depth(int bit_depth);
    static int address_for_byte_index(const FixtureChannelBinding &binding, int byte_index);
    static float read_normalized_value(const std::vector<uint8_t> &frame, const FixtureChannelBinding &binding);
    static uint64_t compute_interest_hash(const std::vector<uint8_t> &frame, const std::vector<int> &offsets);
    static void append_render_values(std::vector<float> &out, const std::array<float, kRuntimeControlCount> &channels, const FixtureRenderParams &params);
    static uint32_t visual_mask_for_channel_index(size_t channel_index);
    static uint32_t visual_mask_for_render_index(size_t render_index);
    void add_visual_mask_stats(uint32_t visual_mask);
    FixtureChangeResult fixture_changed(int fixture_id, const std::array<float, kRuntimeControlCount> &channels, const std::array<float, 9> &render_values);

    std::unordered_map<int, UniverseState> universes_;
    std::unordered_map<int, FixtureRenderParams> render_params_by_fixture_;
    std::unordered_map<int, FixtureState> fixture_state_by_id_;
    VisualFrameSchema schema_ = make_visual_frame_schema(1, VisualFrameSchemaCapabilities());
    int32_t next_schema_generation_ = 1;
    VisualFrameStats stats_;
};

} // namespace peraviz::runtime
