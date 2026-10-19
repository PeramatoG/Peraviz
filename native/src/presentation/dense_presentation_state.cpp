#include "presentation/dense_presentation_state.h"
#include "runtime/visual_runtime_types.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <unordered_set>

namespace peraviz::presentation {
using namespace peraviz::runtime;
namespace {
std::atomic<uint64_t> next_generation{0};
// Matches Godot's float comparison used by the compatibility commit signatures.
bool approximately(float a, float b) {
    return a == b || std::abs(a - b) < std::max(0.00001f, 0.00001f * std::abs(a));
}
// Keeps the existing perceptual wheel attenuation separate from physical energy.
float visual_gain(float gain) {
    return gain <= 0.000001f ? 0.0f : 0.25f + 0.75f * std::pow(std::clamp(gain, 0.0f, 1.0f), 1.0f / 2.2f);
}
}
// Combines static section and canonical target identities without String hashing.
uint64_t DensePresentationState::target_key(int32_t section, int32_t target) {
    return (uint64_t(uint32_t(section)) << 32U) | uint32_t(target);
}
// Replaces the binding generation after complete setup validation.
bool DensePresentationState::install(const std::vector<OutputBinding> &outputs, const std::vector<TargetBinding> &targets) {
    std::unordered_set<int32_t> ids;
    for (const auto &output : outputs) {
        if (output.canonical_id <= 0 || !ids.insert(output.canonical_id).second ||
                !std::isfinite(output.projected_scale) || output.projected_scale < 0.0f) return false;
    }
    std::unordered_map<uint64_t, std::vector<uint32_t>> routes;
    for (const auto &target : targets) {
        if (target.output_index >= outputs.size() || target.target_id <= 0 ||
                (target.section != 2 && target.section != 3 && target.section != 4)) return false;
        auto &indices = routes[target_key(target.section, target.target_id)];
        if (std::find(indices.begin(), indices.end(), target.output_index) == indices.end()) indices.push_back(target.output_index);
    }
    clear();
    bindings_ = outputs;
    states_.resize(outputs.size());
    dirty_.reserve(outputs.size());
    prepared_.reserve(outputs.size());
    routes_ = std::move(routes);
    return true;
}
// Retires every index and releases scene-sized allocations, including on empty rebuilds.
void DensePresentationState::clear() {
    generation_ = ++next_generation;
    std::vector<OutputBinding>().swap(bindings_);
    std::vector<OutputState>().swap(states_);
    std::vector<uint32_t>().swap(dirty_);
    std::vector<PreparedOutput>().swap(prepared_);
    decltype(routes_)().swap(routes_);
    high_water_ = candidates_ = unresolved_rows_ = 0;
}
// Replays held state after a renderer-only replacement without changing semantic ownership.
void DensePresentationState::invalidate_renderer() {
    for (uint32_t index = 0; index < states_.size(); ++index) {
        auto &s = states_[index];
        if (s.mask == 0) dirty_.push_back(index);
        s.mask |= VisualChangeBeamTopology;
        s.committed = false;
        if (trace_enabled_) ++candidates_;
    }
    if (trace_enabled_) high_water_ = std::max(high_water_, dirty_.size());
}
// Updates one independently addressable physical output with latest-state-wins semantics.
bool DensePresentationState::update(uint64_t generation, uint32_t index, int32_t section, uint32_t mask, const float *v) {
    if (generation != generation_ || index >= states_.size() || v == nullptr ||
            (section != 2 && section != 3 && section != 4)) return false;
    const size_t count = section == 2 ? 5 : (section == 3 ? 4 : 3);
    for (size_t i = 0; i < count; ++i) if (!std::isfinite(v[i])) return false;
    auto &s = states_[index];
    if (section == 2) {
        s.dimmer = v[0]; s.beam_energy = v[1]; s.spot_energy = v[2]; s.beam_intensity = v[3]; s.material_energy = v[4];
    } else if (section == 3) {
        s.red = v[0]; s.green = v[1]; s.blue = v[2]; s.gain = std::max(v[3], 0.0f);
    } else {
        s.half_angle = v[0]; s.full_angle = v[1];
    }
    if (trace_enabled_) ++candidates_;
    // A pending mask is the O(1) membership bit; zero input masks still carry their domain.
    if (s.mask == 0) dirty_.push_back(index);
    s.mask |= mask | (section == 2 ? VisualChangeDimmer : (section == 3 ? VisualChangeColor : VisualChangeZoom));
    if (trace_enabled_) high_water_ = std::max(high_water_, dirty_.size());
    return true;
}
// Fans out a semantic control through immutable integer routes into dense state.
bool DensePresentationState::update_target(uint64_t generation, int32_t section, int32_t target, uint32_t mask, const float *values) {
    if (generation != generation_) return false;
    const auto route = routes_.find(target_key(section, target));
    if (route == routes_.end()) return false;
    bool result = true;
    for (uint32_t index : route->second) result = update(generation, index, section, mask, values) && result;
    return result;
}
// Validates all supported section ranges before changing any held presentation state.
bool DensePresentationState::compose_sections(uint64_t generation, const int32_t *d, size_t nd,
        const int32_t *ints, size_t ni, const float *v, size_t nv) {
    if (generation != generation_ || nd % 5 != 0 || (nd && !d) || (ni && !ints) || (nv && !v)) return false;
    for (size_t b = 0; b < nd; b += 5) {
        const int section = d[b];
        if (section != 2 && section != 3 && section != 4) continue;
        const int stride = section == 2 ? 5 : (section == 3 ? 4 : 3);
        if (d[b+1] < 0 || d[b+2] < 0 || d[b+3] < 0 ||
                uint64_t(d[b+2]) + uint64_t(d[b+1]) * 3 > ni ||
                uint64_t(d[b+3]) + uint64_t(d[b+1]) * stride > nv) return false;
        for (size_t i = size_t(d[b+3]); i < size_t(d[b+3]) + size_t(d[b+1]) * stride; ++i)
            if (!std::isfinite(v[i])) return false;
    }
    unresolved_rows_ = 0;
    for (size_t b = 0; b < nd; b += 5) {
        const int section = d[b];
        if (section != 2 && section != 3 && section != 4) continue;
        const int stride = section == 2 ? 5 : (section == 3 ? 4 : 3);
        for (int row = 0; row < d[b+1]; ++row) {
            const size_t ib = size_t(d[b+2]) + size_t(row) * 3;
            if (!update_target(generation, section, ints[ib+1], uint32_t(ints[ib+2]), v + size_t(d[b+3]) + size_t(row) * stride)) ++unresolved_rows_;
        }
    }
    return true;
}
// Composes the canonical physical and perceptual gains without any boundary objects.
RenderValues DensePresentationState::render_values(uint32_t index) const {
    const auto &s = states_.at(index);
    const float scale = bindings_[index].projected_scale;
    // Existing presentation clamps before and after the projected-output scale.
    const float intensity = std::clamp(std::clamp(s.beam_intensity * visual_gain(s.gain), 0.0f, 50.0f) * scale, 0.0f, 50.0f);
    return {s.dimmer, s.red, s.green, s.blue, s.beam_energy * s.gain * scale,
        s.spot_energy * s.gain * scale, intensity, s.material_energy * s.gain,
        s.half_angle, s.full_angle, s.gain,
        s.dimmer > 0.0001f && scale > 0.0f && std::clamp(s.beam_intensity * visual_gain(s.gain), 0.0f, 50.0f) > 0.000001f ? 1.0f : 0.0f};
}
// Filters signature no-ops and publishes a scalar mask instead of a result Dictionary.
uint32_t DensePresentationState::effective_mask(uint32_t index, const RenderValues &v) {
    auto &s = states_.at(index);
    const auto &p = s.previous;
    uint32_t mask = 0;
    if (!s.committed || (s.mask & VisualChangeBeamTopology)) mask = s.mask | VisualChangeDimmer | VisualChangeColor | VisualChangeMaterial;
    else {
        if ((s.mask & VisualChangeDimmer) && (!approximately(p[Dimmer], v[Dimmer]) ||
                !approximately(p[BeamIntensity], v[BeamIntensity]) || p[BeamEnergy] != v[BeamEnergy] ||
                p[SpotEnergy] != v[SpotEnergy] || p[MaterialEnergy] != v[MaterialEnergy])) mask |= VisualChangeDimmer;
        if ((s.mask & VisualChangeColor) && (p[Red] != v[Red] || p[Green] != v[Green] || p[Blue] != v[Blue] ||
                !approximately(p[ColorGain], v[ColorGain]))) mask |= VisualChangeColor;
        if (s.mask & VisualChangeMaterial) mask |= VisualChangeMaterial;
        if ((s.mask & VisualChangeZoom) && (p[HalfAngle] != v[HalfAngle] || p[FullAngle] != v[FullAngle])) mask |= VisualChangeZoom;
    }
    if (mask != 0) { s.previous = v; s.committed = true; }
    return mask;
}
// Composes and filters every dirty output in native contiguous scratch before conversion.
void DensePresentationState::prepare_snapshot() {
    if (trace_enabled_) high_water_ = std::max(high_water_, dirty_.size());
    prepared_.clear();
    for (uint32_t index : dirty_) {
        const auto values = render_values(index);
        const auto mask = effective_mask(index, values);
        if (mask) prepared_.push_back({index, mask, values});
    }
}
// Clears only touched membership bits and reuses all snapshot capacity.
void DensePresentationState::finish_snapshot(uint64_t generation) {
    if (generation != generation_) return;
    for (uint32_t index : dirty_) states_[index].mask = 0;
    dirty_.clear();
    prepared_.clear();
    candidates_ = 0;
}
// Reports retained contiguous buffer bytes without walking per-output state.
size_t DensePresentationState::buffer_bytes() const {
    return bindings_.capacity() * sizeof(OutputBinding) + states_.capacity() * sizeof(OutputState) + dirty_.capacity() * sizeof(uint32_t) + prepared_.capacity() * sizeof(PreparedOutput);
}
} // namespace peraviz::presentation
