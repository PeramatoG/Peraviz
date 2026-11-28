#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>
#include <tuple>
#include <map>

namespace peraviz::runtime {
// Captures complete held raw inputs at an exclusive control boundary for bounded native handoff.
std::vector<PeravizVisualRuntimeCore::HeldUniverse> PeravizVisualRuntimeCore::held_universes() const {
    std::vector<HeldUniverse> frames;
    for (const auto &[id,state]:universes_) frames.push_back({id,state.latest_frame});
    std::sort(frames.begin(),frames.end(),[](const auto &a,const auto &b) { return a.id<b.id; });
    return frames;
}
// Retain clocks and still-owned temporal state, then nominate actual held frames for evaluation.
void PeravizVisualRuntimeCore::inherit_mode_input(const PeravizVisualRuntimeCore &old, int edited_fixture,
                                                   const CompiledRuntimeScene &scene, bool same_geometry) {
    runtime_epoch_ = old.runtime_epoch_;
    test_runtime_now_seconds_ = old.test_runtime_now_seconds_;
    std::unordered_set<int32_t> beam_ids;
    for (const auto &beam : scene.beam_profiles)
        if (beam.fixture_id != edited_fixture) beam_ids.insert(beam.render_target_id);
    for (const auto &[key, value] : old.gobo_selection_state_by_layer_)
        if (beam_ids.count(int32_t(uint64_t(key) >> 32))) gobo_selection_state_by_layer_.emplace(key, value);
    for (const auto &[key, value] : old.gobo_rotation_state_by_layer_)
        if (beam_ids.count(int32_t(uint64_t(key) >> 32))) gobo_rotation_state_by_layer_.emplace(key, value);
    using ByteRoute = std::vector<std::tuple<int32_t, int32_t, int32_t>>;
    const auto route = [](const auto &core, int32_t id) {
        ByteRoute bytes;
        const auto source = core.source_programs_by_id_.find(id);
        if (source != core.source_programs_by_id_.end())
            for (const auto &byte : source->second.program.sources)
                bytes.emplace_back(byte.universe_id, byte.address, byte.byte_order);
        return bytes;
    };
    // A layer key identifies a physical emitter and wheel instance. Only compare it across
    // modes when the emitter geometry survived, then validate each contributing function.
    if (same_geometry) {
        const auto unit = [](const CompiledSubPhysicalUnit &value) {
            return std::tie(value.present, value.physical_unit, value.physical_from, value.physical_to);
        };
        const auto set = [](const CompiledWheelChannelSet &value) {
            return std::tie(value.dmx_from, value.dmx_to, value.wheel_slot_index, value.physical_from, value.physical_to);
        };
        const auto motion = [](const CompiledGoboMotionBinding &value) {
            return std::tie(value.wheel_id, value.semantic_kind, value.controlled_scope,
                            value.physical_from, value.physical_to, value.physical_unit);
        };
        const auto source_shape = [](const CompiledDmxSourceProgram &value) {
            const auto &activation = value.activation;
            return std::tie(value.dmx_from, value.dmx_to, value.physical_from, value.physical_to,
                value.attribute_name, value.geometry_name, activation.target_kind, activation.from,
                activation.to, activation.master_byte_count, activation.valid);
        };
        const auto compatible = [&](const GoboMotionRuntime &a, const GoboMotionRuntime &b) {
            const auto &lhs = a.binding;
            const auto &rhs = b.binding;
            if (motion(lhs) != motion(rhs) || unit(lhs.placement_offset) != unit(rhs.placement_offset) ||
                unit(lhs.amplitude) != unit(rhs.amplitude) ||
                !std::equal(lhs.channel_sets.begin(), lhs.channel_sets.end(), rhs.channel_sets.begin(),
                    rhs.channel_sets.end(), [&](const auto &x, const auto &y) { return set(x) == set(y); })) return false;
            return std::equal(a.dependency_program_ids.begin(), a.dependency_program_ids.end(),
                b.dependency_program_ids.begin(), b.dependency_program_ids.end(), [&](int32_t x, int32_t y) {
                    return route(*this, x) == route(old, y) &&
                        source_shape(source_programs_by_id_.at(x).program) == source_shape(old.source_programs_by_id_.at(y).program);
                });
        };
        for (const auto &[universe_id, current] : universes_) {
            const auto previous = old.universes_.find(universe_id);
            if (previous == old.universes_.end()) continue;
            const auto &prior_universe = previous->second;
            for (const auto &[key, indices] : current.gobo_motion_indices_by_layer) {
                if (current.gobo_motion_bindings[indices.front()].binding.fixture_id != edited_fixture) continue;
                const auto prior = old.gobo_rotation_state_by_layer_.find(key);
                const auto prior_indices = prior_universe.gobo_motion_indices_by_layer.find(key);
                if (prior == old.gobo_rotation_state_by_layer_.end() || !prior->second.initialized ||
                    prior_indices == prior_universe.gobo_motion_indices_by_layer.end() ||
                    indices.size() != prior_indices->second.size()) continue;
                auto state = prior->second;
                const bool matched = std::equal(indices.begin(), indices.end(), prior_indices->second.begin(),
                    [&](int a, int b) { return compatible(current.gobo_motion_bindings[a], prior_universe.gobo_motion_bindings[b]); });
                if (!matched) continue;
                for (size_t i = 0; i < indices.size(); ++i) {
                    const auto &binding = current.gobo_motion_bindings[indices[i]].binding;
                    const int32_t old_id = prior_universe.gobo_motion_bindings[prior_indices->second[i]].binding.binding_id;
                    if (prior->second.pos_binding_id == old_id) state.pos_binding_id = binding.binding_id;
                    if (prior->second.pos_rotate_binding_id == old_id) state.pos_rotate_binding_id = binding.binding_id;
                }
                gobo_rotation_state_by_layer_.emplace(key, state);
                mode_gobo_motion_replay_.insert(key);
            }
        }
    }
    // Shutter program numbers are setup-local. Preserve phase by matching the source function,
    // split-mode range and waveform within the same stable physical authority.
    using ShutterSignature = std::tuple<ByteRoute, ByteRoute, uint32_t, uint32_t, uint32_t, uint32_t, int32_t,
        double, double, double, double, double, double, double, double, int32_t, uint32_t, uint32_t>;
    const auto shutter_functions = [&](const PeravizVisualRuntimeCore &core) {
        std::unordered_map<int32_t, std::map<ShutterSignature, int32_t>> result;
        for (const auto &[universe_id, universe] : core.universes_)
            for (const auto &[authority, indices] : universe.shutter_layers)
                for (const auto index : indices) {
                    const auto &binding = universe.shutters[index].binding;
                    auto &functions = result[int32_t(authority)];
                    const ShutterSignature signature = {route(core, binding.source_program_id),
                        route(core, binding.mode_source_program_id), binding.dmx_from, binding.dmx_to,
                        binding.mode_from, binding.mode_to, int32_t(binding.wave), binding.physical_from,
                        binding.physical_to, binding.duration, binding.duration_to, binding.duty, binding.duty_to,
                        binding.offset, binding.offset_to, binding.timing_variable_mask,
                        binding.timing_dmx_from, binding.timing_dmx_to};
                    const auto inserted = functions.emplace(signature, binding.activation_function_id ?
                        binding.activation_function_id : binding.source_program_id);
                    if (!inserted.second) inserted.first->second = 0;
                }
        return result;
    };
    const auto old_functions = shutter_functions(old);
    const auto new_functions = shutter_functions(*this);
    std::unordered_set<int32_t> restored;
    for (const auto &[key, state] : shutter_states_) {
        if ((state.fixture_id == edited_fixture && !same_geometry) || !restored.insert(state.authority).second) continue;
        const auto prior = old.shutter_states_.find(key);
        if (prior == old.shutter_states_.end() || prior->second.fixture_id != state.fixture_id) continue;
        auto &authority = shutter_authorities_.at(state.authority);
        const auto &previous = old.shutter_authorities_.at(prior->second.authority);
        if (authority.targets != previous.targets) continue;
        const auto old_map = old_functions.find(prior->second.authority);
        const auto new_map = new_functions.find(state.authority);
        if (old_map == old_functions.end() || new_map == new_functions.end() ||
            old_map->second.size() != new_map->second.size() ||
            !std::equal(old_map->second.begin(), old_map->second.end(), new_map->second.begin(),
                [](const auto &a, const auto &b) { return a.first == b.first; })) continue;
        auto parameters = previous.parameters;
        if (parameters.function_id) {
            const auto signature = std::find_if(old_map->second.begin(), old_map->second.end(),
                [&](const auto &entry) { return entry.second == parameters.function_id; });
            if (signature == old_map->second.end()) continue;
            const auto match = new_map->second.find(signature->first);
            if (match == new_map->second.end() || !match->second) continue;
            parameters.function_id = match->second;
        }
        authority.seed = previous.seed;
        authority.parameters = parameters;
        authority.diagnosed = previous.diagnosed;
    }
    for (const auto &frame : old.held_universes())
        if (!frame.values.empty()) submit_universe_frame(frame.id, frame.values.data(), int(frame.values.size()));
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
    size_t extra=0;
    for(const auto &[universe_id,universe]:universes_)for(const auto &property:universe.properties) {
        if(!multi_transform_fixtures_.count(property.property.fixture_id) || (property.parameter!=SemanticParameter::Pan && property.parameter!=SemanticParameter::Tilt))continue;
        const auto state=property_state_by_property_.find(property.property.property_id);if(state==property_state_by_property_.end() || !state->second.initialized)continue;
        frame.integers.insert(frame.integers.end(),{property.property.fixture_id,property.parameter==SemanticParameter::Pan?property.property.component_id:0,property.parameter==SemanticParameter::Tilt?property.property.component_id:0,int32_t(VisualChangeTransform)});
        frame.floats.insert(frame.floats.end(),{state->second.pan,state->second.tilt});++extra;
    }
    if (!fixtures.empty() || extra) frame.descriptors={int32_t(VisualSectionType::GeometryTransform),int32_t(fixtures.size()+extra),0,0,0};
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
    replay_shutters(frame);
    return frame;
}
} // namespace peraviz::runtime
