#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <unordered_map>
#include <vector>
#include <type_traits>

namespace peraviz::presentation {

// Internal presentation indices never replace canonical GDTF/MVR identities.
struct OutputBinding {
    int32_t canonical_id = 0;
    float projected_scale = 1.0f;
};
struct TargetBinding {
    int32_t section = 0;
    int32_t target_id = 0;
    uint32_t output_index = 0;
};

// All values needed by the existing renderer, already composed and scaled.
enum Value : size_t {
    Dimmer, Red, Green, Blue, BeamEnergy, SpotEnergy, BeamIntensity,
    MaterialEnergy, HalfAngle, FullAngle, ColorGain, Visible, ValueCount
};
using RenderValues = std::array<float, ValueCount>;
struct OutputState {
    float dimmer = 0.0f;
    float beam_energy = 0.0f;
    float spot_energy = 0.0f;
    float beam_intensity = 0.0f;
    float material_energy = 0.0f;
    float red = 1.0f, green = 1.0f, blue = 1.0f, gain = 1.0f;
    float half_angle = 12.5f, full_angle = 25.0f;
    uint32_t mask = 0;
    bool committed = false;
    RenderValues previous{};
};

static_assert(std::is_trivially_copyable<OutputState>::value, "Realtime state must stay POD");

struct PreparedOutput {
    uint32_t index;
    uint32_t mask;
    RenderValues values;
};

class DensePresentationState {
public:
    bool install(const std::vector<OutputBinding> &outputs, const std::vector<TargetBinding> &targets);
    bool install_groups(const std::vector<int32_t> &representatives);
    void clear();
    void invalidate_renderer();
    // Returns the current process-unique scene binding token.
    uint64_t generation() const { return generation_; }
    bool update(uint64_t generation, uint32_t index, int32_t section, uint32_t mask, const float *values);
    bool update_target(uint64_t generation, int32_t section, int32_t target, uint32_t mask, const float *values);
    bool compose_sections(uint64_t generation, const int32_t *descriptors, size_t descriptor_count,
            const int32_t *integers, size_t integer_count, const float *values, size_t value_count);
    // Enables optional snapshot counters without adding clocks to native production updates.
    void set_trace_enabled(bool enabled) { trace_enabled_ = enabled; }
    void prepare_snapshot();
    // Borrows the current contiguous render deltas until snapshot completion.
    const std::vector<PreparedOutput> &prepared() const { return prepared_; }
    const std::vector<PreparedOutput> &prepared_groups() const { return prepared_groups_; }
    size_t dynamic_candidates() const { return dynamic_candidates_; }
    RenderValues render_values(uint32_t index) const;
    // Borrows domain dirtiness for downstream native render projection.
    uint32_t pending_mask(uint32_t index) const { return states_.at(index).mask; }
    uint32_t effective_mask(uint32_t index, const RenderValues &values);
    void finish_snapshot(uint64_t generation);
    // Borrows the deduplicated touched-output prefix.
    const std::vector<uint32_t> &dirty_indices() const { return dirty_; }
    // Borrows immutable canonical physical binding identities.
    const std::vector<OutputBinding> &bindings() const { return bindings_; }
    // Reports retained raw and previous-state slots.
    size_t state_capacity() const { return states_.capacity(); }
    // Reports the retained maximum pending-index slots.
    size_t dirty_capacity() const { return dirty_.capacity(); }
    // Reports the exact dirty-output peak for this generation.
    size_t high_water() const { return high_water_; }
    size_t buffer_bytes() const;
    // Reports nominations before native deduplication.
    size_t candidates() const { return candidates_; }
    // Reports semantic rows with no installed renderer route.
    size_t unresolved_rows() const { return unresolved_rows_; }
private:
    static uint64_t target_key(int32_t section, int32_t target);
    uint64_t generation_ = 0;
    std::vector<OutputBinding> bindings_;
    std::vector<OutputState> states_;
    std::vector<uint32_t> dirty_;
    std::vector<PreparedOutput> prepared_;
    std::unordered_map<uint64_t, std::vector<uint32_t>> routes_;
    std::vector<int32_t> representatives_;
    std::vector<uint32_t> group_masks_;
    std::vector<PreparedOutput> prepared_groups_;
    size_t dynamic_candidates_ = 0;
    size_t high_water_ = 0;
    size_t candidates_ = 0;
    size_t unresolved_rows_ = 0;
    bool trace_enabled_ = false;
};
} // namespace peraviz::presentation
