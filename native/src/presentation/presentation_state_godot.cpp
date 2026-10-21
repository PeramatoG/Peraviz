#include "presentation/presentation_state_godot.h"
#include <godot_cpp/core/class_db.hpp>
#include <chrono>
#include <algorithm>

namespace godot {
using namespace peraviz::presentation;
namespace {
// Reads a monotonic clock only for explicitly traced presentation work.
int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
}
// Exposes batched setup and snapshot operations; no per-output Godot calls exist.
void PeravizPresentationState::_bind_methods() {
    ClassDB::bind_method(D_METHOD("install", "ids", "scales", "routes"), &PeravizPresentationState::install);
    ClassDB::bind_method(D_METHOD("invalidate_renderer"), &PeravizPresentationState::invalidate_renderer);
    ClassDB::bind_method(D_METHOD("install_groups", "representatives"), &PeravizPresentationState::install_groups);
    ClassDB::bind_method(D_METHOD("clear"), &PeravizPresentationState::clear);
    ClassDB::bind_method(D_METHOD("compose", "generation", "descriptors", "integers", "values", "trace"), &PeravizPresentationState::compose);
    ClassDB::bind_method(D_METHOD("get_sizes"), &PeravizPresentationState::get_sizes);
}
// Resolves setup-only packed binding data into immutable native routes and dense indices.
int64_t PeravizPresentationState::install(const PackedInt32Array &ids, const PackedFloat32Array &scales, const PackedInt32Array &routes) {
    if (ids.size() != scales.size() || routes.size() % 3 != 0) return -1;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> targets;
    outputs.reserve(ids.size()); targets.reserve(routes.size() / 3);
    for (int64_t i = 0; i < ids.size(); ++i) outputs.push_back({ids[i], scales[i]});
    for (int64_t i = 0; i < routes.size(); i += 3) targets.push_back({routes[i], routes[i+1], uint32_t(routes[i+2])});
    if (!state_.install(outputs, targets)) return -1;
    indices_masks_.resize(ids.size() * 2);
    values_.resize(ids.size() * ValueCount);
    return int64_t(state_.generation());
}
// Accepts only setup-time renderer-compatible physical membership.
bool PeravizPresentationState::install_groups(const PackedInt32Array &representatives) {
    std::vector<int32_t> mapping;
    mapping.reserve(representatives.size());
    for (int64_t i = 0; i < representatives.size(); ++i) mapping.push_back(representatives[i]);
    if (!state_.install_groups(mapping)) return false;
    group_indices_masks_.resize(representatives.size() * 2);
    group_values_.resize(representatives.size() * ValueCount);
    return true;
}
// Invalidates all borrowed indices and releases packed binding-generation capacity.
void PeravizPresentationState::clear() {
    state_.clear();
    indices_masks_ = PackedInt32Array(); values_ = PackedFloat32Array();
    group_indices_masks_ = PackedInt32Array(); group_values_ = PackedFloat32Array();
}
// Requests a forced replay while preserving current native control values.
void PeravizPresentationState::invalidate_renderer() {
    state_.invalidate_renderer();
}
// Composes one complete semantic snapshot and copies only dirty values into reused packed buffers.
Dictionary PeravizPresentationState::compose(int64_t generation, const PackedInt32Array &descriptors,
        const PackedInt32Array &integers, const PackedFloat32Array &values, bool trace) {
    Dictionary result;
    state_.set_trace_enabled(trace);
    const int64_t start = trace ? now_us() : 0;
    if (!state_.compose_sections(uint64_t(generation), descriptors.ptr(), size_t(descriptors.size()),
            integers.ptr(), size_t(integers.size()), values.ptr(), size_t(values.size()))) {
        result["valid"] = false;
        return result;
    }
    state_.prepare_snapshot();
    const int64_t compose_us = trace ? now_us() - start : 0;
    const int64_t copy_start = trace ? now_us() : 0;
    const size_t dirty_count = state_.dirty_indices().size();
    int32_t *indices = indices_masks_.ptrw();
    float *packed = values_.ptrw();
    int64_t count = 0;
    for (const auto &output : state_.prepared()) {
        indices[count * 2] = int32_t(output.index);
        indices[count * 2 + 1] = int32_t(output.mask);
        std::copy(output.values.begin(), output.values.end(), packed + count * ValueCount);
        ++count;
    }
    int64_t group_count = 0;
    if (!state_.prepared_groups().empty()) {
        auto *group_indices = group_indices_masks_.ptrw();
        auto *group_values = group_values_.ptrw();
        for (const auto &group : state_.prepared_groups()) {
            group_indices[group_count * 2] = int32_t(group.index);
            group_indices[group_count * 2 + 1] = int32_t(group.mask);
            std::copy(group.values.begin(), group.values.end(), group_values + group_count * ValueCount);
            ++group_count;
        }
    }
    result["group_count"] = group_count;
    result["group_indices_masks"] = group_indices_masks_;
    result["group_values"] = group_values_;
    const int64_t conversion_us = trace ? now_us() - copy_start : 0;
    result["valid"] = true; result["generation"] = generation;
    result["unresolved_rows"] = int64_t(state_.unresolved_rows());
    result["count"] = count; result["indices_masks"] = indices_masks_; result["values"] = values_;
    if (trace) {
        result["physical_dynamic_candidates"] = int64_t(state_.dynamic_candidates());
        result["control_group_dynamic_updates"] = group_count;
        result["native_compose_us"] = compose_us;
        result["payload_conversion_us"] = conversion_us;
        result["dirty_count"] = int64_t(dirty_count);
        result["candidates"] = int64_t(std::max(state_.candidates(), dirty_count));
        result["signature_skipped"] = int64_t(dirty_count) - count;
    }
    state_.finish_snapshot(uint64_t(generation));
    return result;
}
// Samples fixed native capacities only at the trace report boundary.
Dictionary PeravizPresentationState::get_sizes() const {
    Dictionary sizes;
    sizes["physical_outputs"] = int64_t(state_.bindings().size());
    sizes["state_capacity"] = int64_t(state_.state_capacity());
    sizes["dirty_capacity"] = int64_t(state_.dirty_capacity());
    sizes["dirty_high_water"] = int64_t(state_.high_water());
    sizes["native_buffer_bytes"] = int64_t(state_.buffer_bytes());
    sizes["packed_buffer_bytes"] = (indices_masks_.size() + group_indices_masks_.size()) * int64_t(sizeof(int32_t)) + (values_.size() + group_values_.size()) * int64_t(sizeof(float));
    return sizes;
}
} // namespace godot
