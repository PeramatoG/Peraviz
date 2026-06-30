#pragma once

#include <array>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace peraviz::runtime {

constexpr int kVisualChannelCount = 13;
constexpr int kVisualFrameStride = 24;

enum class VisualChannel : int {
    Dimmer = 0,
    Pan = 1,
    Tilt = 2,
    Zoom = 3,
    Cyan = 4,
    Magenta = 5,
    Yellow = 6,
    Gobo = 7,
    GoboIndex = 8,
    GoboRotation = 9,
    Prism = 10,
    PrismRotation = 11,
    Strobe = 12,
};

struct FixtureChannelBinding {
    int fixture_id = 0;
    int universe_id = 0;
    int channel_type = 0;
    int start_address = 0;
    int fine_address = -1;
    int ultra_fine_address = -1;
    int bit_depth = 8;
    double scale_min = 0.0;
    double scale_max = 1.0;
};

struct FixtureRenderParams {
    double luminous_flux = 10000.0;
    double beam_angle_default = 25.0;
    double zoom_min_deg = -1.0;
    double zoom_max_deg = -1.0;
    double color_temp_k = 5600.0;
    double spot_multiplier = 1.0;
    double beam_multiplier = 20.0;
    bool has_zoom = false;
    bool has_color_temperature = false;
};

struct VisualFrameStats {
    uint64_t packets_submitted = 0;
    uint64_t packets_coalesced = 0;
    uint64_t universes_ignored = 0;
    uint64_t universes_considered = 0;
    uint64_t fixtures_dirty = 0;
    uint64_t fixtures_skipped = 0;
};

struct VisualFrame {
    std::vector<float> values;
    VisualFrameStats stats;
};

} // namespace peraviz::runtime
