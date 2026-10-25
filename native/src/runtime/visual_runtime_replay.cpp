#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>

namespace peraviz::runtime {
// Captures complete held raw inputs at an exclusive control boundary for bounded native handoff.
std::vector<PeravizVisualRuntimeCore::HeldUniverse> PeravizVisualRuntimeCore::held_universes() const {
    std::vector<HeldUniverse> frames;
    for (const auto &[id,state]:universes_) frames.push_back({id,state.latest_frame});
    std::sort(frames.begin(),frames.end(),[](const auto &a,const auto &b) { return a.id<b.id; });
    return frames;
}
// Rehydrates held mechanical domains after a renderer-only retirement, without resetting physical semantics.
SectionedVisualFrame PeravizVisualRuntimeCore::held_domain_replay() const {
    SectionedVisualFrame frame; frame.schema_generation=schema_.schema_generation;
    std::vector<int> fixtures;
    for (const auto &[id,state]:transform_state_by_fixture_) if (state.initialized) fixtures.push_back(id);
    std::sort(fixtures.begin(),fixtures.end());
    for (int id:fixtures) {
        const auto &state=transform_state_by_fixture_.at(id);
        const auto pan=pan_component_id_by_fixture_.find(id),tilt=tilt_component_id_by_fixture_.find(id);
        frame.integers.insert(frame.integers.end(),{id,pan==pan_component_id_by_fixture_.end()?0:pan->second,
            tilt==tilt_component_id_by_fixture_.end()?0:tilt->second,int32_t(VisualChangeTransform)});
        frame.floats.insert(frame.floats.end(),{state.pan,state.tilt});
    }
    if (!fixtures.empty()) frame.descriptors={int32_t(VisualSectionType::GeometryTransform),int32_t(fixtures.size()),0,0,0};
    const int32_t int_offset=int32_t(frame.integers.size()),float_offset=int32_t(frame.floats.size());
    int32_t wheel_count=0;
    std::vector<int64_t> wheels;
    for (const auto &[key,state]:wheel_state_by_physical_key_) if (state.initialized) wheels.push_back(key);
    std::sort(wheels.begin(),wheels.end());
    for (int64_t key:wheels) {
        const auto &state=wheel_state_by_physical_key_.at(key);
        int fixture=0;
        for (const auto &[universe_id,universe]:universes_) {
            const auto owner=universe.color_fixture_by_target.find(state.beam_target_id);
            if (owner!=universe.color_fixture_by_target.end()) { fixture=owner->second; break; }
        }
        frame.integers.insert(frame.integers.end(),{fixture,state.beam_target_id,state.wheel_renderer_id,int32_t(state.mode),
            state.slot_a,state.slot_b,int32_t(VisualChangeColor),state.revision});
        frame.floats.insert(frame.floats.end(),{state.normalized_phase,state.split_fraction,state.boundary_angle_degrees,
            state.srgb_red,state.srgb_green,state.srgb_blue,state.gain,0.02f});
        ++wheel_count;
    }
    if (wheel_count) frame.descriptors.insert(frame.descriptors.end(),{int32_t(VisualSectionType::WheelSelection),wheel_count,int_offset,float_offset,0});
    return frame;
}
} // namespace peraviz::runtime
