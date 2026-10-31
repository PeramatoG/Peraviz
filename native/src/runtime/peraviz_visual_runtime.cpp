#include "runtime/peraviz_visual_runtime.h"
#include "runtime/color_science.h"
#include "runtime/gobo_motion_evaluator.h"

#include <algorithm>
#include <cmath>

namespace peraviz::runtime {
namespace {

constexpr float kDefaultEpsilon = 0.0001f;
constexpr float kAngleEpsilon = 0.01f;

// Adds one typed section descriptor to the frame descriptor table.
void append_descriptor(SectionedVisualFrame &frame, VisualSectionType type, int32_t row_count, int32_t int_offset, int32_t float_offset) {
    frame.descriptors.push_back(static_cast<int32_t>(type));
    frame.descriptors.push_back(row_count);
    frame.descriptors.push_back(int_offset);
    frame.descriptors.push_back(float_offset);
    frame.descriptors.push_back(0);
}

// Converts one linear RGB component into renderer-ready sRGB.
float linear_to_srgb(float value) {
    const float clamped = std::clamp(value, 0.0f, 1.0f);
    if (clamped <= 0.0031308f) return clamped * 12.92f;
    return 1.055f * std::pow(clamped, 1.0f / 2.4f) - 0.055f;
}

} // namespace

// Keeps serial construction cheap; parallel scratch is allocated only for an eligible scene session.
PeravizVisualRuntimeCore::PeravizVisualRuntimeCore() = default;
// Releases borrowed job views after the owning native coordinator has stopped its executor.
PeravizVisualRuntimeCore::~PeravizVisualRuntimeCore() = default;
// Changes execution only at an exclusive native control boundary.
void PeravizVisualRuntimeCore::set_native_executor(NativeBatchExecutor *executor) {
    prefetch_.reset();
    if (executor) prefetch_=std::make_unique<ParallelEvaluationPrefetch>(*this,*executor);
}
// Samples the latest coarse execution metrics without introducing clocks in scalar loops.
ParallelEvaluationMetrics PeravizVisualRuntimeCore::parallel_metrics() const { return prefetch_?prefetch_->metrics():ParallelEvaluationMetrics{}; }
// Reserves asynchronous publication for substantial independent work; temporal domains retain serial ownership.
bool PeravizVisualRuntimeCore::async_eligible_workload() const { return installed_sources_>=3072 && installed_colors_>=512 && !has_gobo_domains_; }
// Clears bindings, cached frames, fixture state, and runtime counters.
void PeravizVisualRuntimeCore::clear() {
    prefetch_.reset(); installed_sources_=installed_colors_=0; has_gobo_domains_=false;
    universes_.clear();
    diagnostics_.clear();
    render_params_by_fixture_.clear();
    transform_state_by_fixture_.clear();
    property_state_by_property_.clear();
    color_state_by_target_.clear();
    pan_component_id_by_fixture_.clear();
    tilt_component_id_by_fixture_.clear();
    installed_visual_mask_by_fixture_.clear();
    source_programs_by_id_.clear();
    emitter_resources_by_id_.clear();
    filter_resources_by_id_.clear();
    wheel_palettes_by_id_.clear();
    base_color_state_by_target_.clear();
    ordered_wheel_layers_.clear();
    wheel_state_by_physical_key_.clear();
    mapping_definitions_ = fixture_mode_definitions_ = 0;
    gobo_selection_state_by_layer_.clear();
    gobo_rotation_state_by_layer_.clear();
    diagnosed_ambiguous_gobo_selection_layers_.clear();
    diagnosed_ambiguous_gobo_pos_layers_.clear();
    diagnosed_ambiguous_gobo_posrotate_layers_.clear();
    diagnosed_simultaneous_gobo_posrotate_layers_.clear();
    shutter_states_.clear(); shutter_authorities_.clear(); shutter_unsupported_fixtures_.clear();
    runtime_epoch_ = std::chrono::steady_clock::now();
    test_runtime_now_seconds_ = -1.0;
    gobo_asset_by_wheel_slot_.clear();
    stats_ = VisualFrameStats();
    schema_ = make_visual_frame_schema(++next_schema_generation_, VisualFrameSchemaCapabilities());
}

// Submits a universe snapshot using latest-wins coalescing.
void PeravizVisualRuntimeCore::submit_universe_frame(int universe_id, const uint8_t *data, int length) {
    ++stats_.packets_submitted;
    auto universe_it = universes_.find(universe_id);
    if (universe_it == universes_.end() || data == nullptr || length <= 0) {
        ++stats_.universes_ignored;
        return;
    }
    UniverseState &universe = universe_it->second;
    if (universe.has_pending_frame) ++stats_.packets_coalesced;
    const int clamped_length = std::clamp(length, 0, 512);
    universe.latest_frame.assign(data, data + clamped_length);
    universe.has_pending_frame = true;
}

// Consumes newest dirty universes and returns one typed sectioned visual frame.
SectionedVisualFrame PeravizVisualRuntimeCore::consume_latest_visual_frame() {
    SectionedVisualFrame frame;
    consume_latest_visual_frame(frame);
    return frame;
}

// Reuses caller-owned semantic buffers; borrowed views expire at the next consume.
void PeravizVisualRuntimeCore::consume_latest_visual_frame(SectionedVisualFrame &frame) {
    frame.descriptors.clear(); frame.integers.clear(); frame.floats.clear();
    frame.schema_generation = schema_.schema_generation;
    if (prefetch_) prefetch_->prepare();
    struct PendingRow { int fixture_id = 0; int32_t render_target_id = 0; uint32_t changed_visual_mask = 0; ComponentState state; CookedEmitterColor color; int32_t wheel_id = 0; int32_t slot_a = 0; int32_t slot_b = 0; float normalized_phase = 0.0f; float split_fraction = 0.0f; float boundary_angle_degrees = 0.0f; CompiledWheelMode wheel_mode = CompiledWheelMode::Select; int32_t revision = 0; bool wheel_row = false; };
    std::vector<PendingRow> rows;
    struct GoboRow { int32_t fixture_id; int32_t beam_target_id; int32_t wheel_id; int32_t wheel_instance_index; int32_t slot_index; int32_t asset_id; CompiledGoboSelectionMode mode; int32_t revision; };
    std::vector<GoboRow> gobo_rows;
    struct GoboRotationRow { int32_t fixture_id; int32_t beam_target_id; int32_t wheel_id; int32_t wheel_instance_index; GoboRotationMode mode; float phase_degrees; float angular_velocity_dps; float reference_seconds; int32_t revision; };
    std::vector<GoboRotationRow> gobo_rotation_rows;

    for (auto &[universe_id, universe] : universes_) {
        if (!universe.has_pending_frame) continue;
        universe.has_pending_frame = false;
        ++stats_.universes_considered;
        auto &changed_offsets=universe.changed_offsets;
        const bool prepared_inputs=prefetch_ && prefetch_->inputs_prepared(universe_id);
        if (!prepared_inputs) {
        changed_offsets.clear();
        for (int offset : universe.interest_offsets) {
            const uint8_t value = offset >= 0 && offset < static_cast<int>(universe.latest_frame.size()) ? universe.latest_frame[static_cast<size_t>(offset)] : 0;
            if (!universe.has_last_relevant_values || universe.last_relevant_values[static_cast<size_t>(offset)] != value) {
                changed_offsets.push_back(offset);
                universe.last_relevant_values[static_cast<size_t>(offset)] = value;
            }
        }
        universe.has_last_relevant_values = true;
        }
        if (changed_offsets.empty()) continue;
        if (performance_trace_enabled_) stats_.changed_relevant_offsets += changed_offsets.size();

        auto &property_indices=universe.dirty_properties; property_indices.clear();
        auto &color_target_indices=universe.dirty_colors; color_target_indices.clear();
        auto &wheel_binding_indices=universe.dirty_wheels; wheel_binding_indices.clear();
        auto &gobo_selection_layers=universe.dirty_gobo_selections; gobo_selection_layers.clear();
        auto &gobo_motion_layers=universe.dirty_gobo_motions; gobo_motion_layers.clear();
        universe.dirty_shutters.clear();
        if (!prepared_inputs) universe.plan.begin_update(changed_offsets);
        if (prefetch_) prefetch_->inject_sources(universe_id);
        if (performance_trace_enabled_) for (int offset:changed_offsets) {
            const uint64_t fanout=universe.plan.color_offset_fanout(offset);
            if (!fanout) continue;
            ++stats_.color_changed_offsets; stats_.color_changed_offset_candidates+=fanout;
            stats_.color_offset_fanout_max=std::max(stats_.color_offset_fanout_max,fanout);
            if (fanout==1) ++stats_.color_offset_fanout_1;
            else if (fanout<=4) ++stats_.color_offset_fanout_2_4;
            else if (fanout<=16) ++stats_.color_offset_fanout_5_16;
            else if (fanout<=64) ++stats_.color_offset_fanout_17_64;
            else ++stats_.color_offset_fanout_65_plus;
        }
        size_t scheduled=0;
        for (int consumer_index:universe.plan.dirty_consumers()) {
            const auto &consumer=universe.plan.consumer(uint32_t(consumer_index));
            const int index=int(consumer.index);
            switch (consumer.domain) {
                case EvaluationDomain::Property: property_indices.push_back(index); break;
                case EvaluationDomain::Color: color_target_indices.push_back(index); break;
                case EvaluationDomain::Wheel: wheel_binding_indices.insert(&index,&index+1); break;
                case EvaluationDomain::GoboSelection: gobo_selection_layers.push_back(consumer.target); break;
                case EvaluationDomain::Shutter: universe.dirty_shutters.push_back(consumer.target); break;
                case EvaluationDomain::GoboMotion: gobo_motion_layers.push_back(consumer.target); break;
            }
            ++scheduled;
        }
        if (performance_trace_enabled_) {
            stats_.evaluation_consumers_scheduled+=scheduled;
            stats_.evaluation_consumers_avoided+=universe.plan.consumer_count()-scheduled;
        }

        evaluate_shutters(universe,frame);
        for (int64_t layer_key : gobo_selection_layers) {
            const auto layer_it = universe.gobo_binding_indices_by_layer.find(layer_key);
            if (layer_it == universe.gobo_binding_indices_by_layer.end()) continue;
            const CompiledGoboSelectionBinding *selected_binding = nullptr;
            const CompiledWheelChannelSet *selected_set = nullptr;
            int active_binding_count = 0;
            for (int binding_index : layer_it->second) {
                if (binding_index < 0 || binding_index >= static_cast<int>(universe.gobo_bindings.size())) continue;
                GoboBindingRuntime &runtime_binding = universe.gobo_bindings[static_cast<size_t>(binding_index)];
                if (!evaluate_cached_activation(universe,runtime_binding)) continue;
                const uint32_t raw_value = evaluate_cached_source(universe,runtime_binding.sources.front()).raw_value;
                const CompiledWheelChannelSet *active_set = nullptr;
                for (const CompiledWheelChannelSet &set : runtime_binding.binding.channel_sets) {
                    if (raw_value >= set.dmx_from && raw_value <= set.dmx_to) { active_set = &set; break; }
                }
                if (active_set == nullptr) continue;
                ++active_binding_count;
                if (selected_binding == nullptr) {
                    selected_binding = &runtime_binding.binding;
                    selected_set = active_set;
                }
            }
            if (selected_binding == nullptr || selected_set == nullptr) continue;
            if (active_binding_count > 1 && diagnosed_ambiguous_gobo_selection_layers_.insert(layer_key).second) diagnostics_.push_back({"PVZ-RUNTIME-AMBIGUOUS-GOBO-SELECTION", "warning", "Multiple active gobo selection bindings share one physical layer; parser declaration order is used.", std::to_string(layer_key)});
            const int64_t asset_key = (static_cast<int64_t>(selected_binding->wheel_id) << 32) | static_cast<uint32_t>(selected_set->wheel_slot_index);
            const int32_t asset_id = gobo_asset_by_wheel_slot_.count(asset_key) != 0 ? gobo_asset_by_wheel_slot_[asset_key] : 0;
            GoboSelectionState &state = gobo_selection_state_by_layer_[layer_key];
            if (state.initialized && state.slot_index == selected_set->wheel_slot_index && state.asset_id == asset_id) {
                ++stats_.gobo_selection_layers_deduplicated;
                continue;
            }
            state.slot_index = selected_set->wheel_slot_index;
            state.asset_id = asset_id;
            state.contributing_binding_id = selected_binding->binding_id;
            state.initialized = true;
            ++state.revision;
            gobo_rows.push_back({selected_binding->fixture_id, selected_binding->beam_render_target_id, selected_binding->wheel_id, selected_binding->wheel_instance_index, state.slot_index, state.asset_id, selected_binding->mode, state.revision});
            ++stats_.gobo_selection_rows;
            ++stats_.gobo_topology_updates;
        }

        const double motion_now = runtime_now_seconds();
        for (int64_t layer_key : gobo_motion_layers) {
            const auto layer_it = universe.gobo_motion_indices_by_layer.find(layer_key);
            if (layer_it == universe.gobo_motion_indices_by_layer.end()) continue;
            const CompiledGoboMotionBinding *pos_binding = nullptr;
            const CompiledGoboMotionBinding *rotate_binding = nullptr;
            EvaluatedGoboScalar pos_value;
            EvaluatedGoboScalar rotate_value;
            int active_pos_count = 0;
            int active_rotate_count = 0;
            for (int binding_index : layer_it->second) {
                if (binding_index < 0 || binding_index >= static_cast<int>(universe.gobo_motion_bindings.size())) continue;
                GoboMotionRuntime &motion = universe.gobo_motion_bindings[static_cast<size_t>(binding_index)];
                const bool active=evaluate_cached_activation(universe,motion);
                const auto value=evaluate_cached_source(universe,motion.sources.front());
                const EvaluatedGoboScalar evaluated = evaluate_active_gobo_motion_scalar(motion.binding,
                        universe.source_bindings[motion.sources.front()]->program,value.raw_value,active);
                if (!evaluated.active) continue;
                if (motion.binding.semantic_kind == gdtf_runtime::GoboSemanticKind::Pos) {
                    ++active_pos_count;
                    if (pos_binding == nullptr) { pos_binding = &motion.binding; pos_value = evaluated; }
                } else if (motion.binding.semantic_kind == gdtf_runtime::GoboSemanticKind::PosRotate) {
                    ++active_rotate_count;
                    if (rotate_binding == nullptr) { rotate_binding = &motion.binding; rotate_value = evaluated; }
                }
            }
            GoboRotationState &state = gobo_rotation_state_by_layer_[layer_key];
            const bool pos_active = pos_binding != nullptr;
            const bool rotate_active = rotate_binding != nullptr;
            if (!state.initialized && !pos_active && !rotate_active) continue;
            const double elapsed = state.initialized ? std::max(0.0, motion_now - state.reference_seconds) : 0.0;
            const double current_phase = state.initialized ? state.phase_degrees + state.angular_velocity_dps * elapsed : 0.0;
            const bool pos_changed = state.pos_active != pos_active ||
                (pos_active && (state.pos_binding_id != pos_binding->binding_id || !nearly_equal(static_cast<float>(state.pos_degrees), static_cast<float>(pos_value.physical_value), kAngleEpsilon)));
            const bool rotate_changed = state.pos_rotate_active != rotate_active ||
                (rotate_active && (state.pos_rotate_binding_id != rotate_binding->binding_id || !nearly_equal(static_cast<float>(state.pos_rotate_dps), static_cast<float>(rotate_value.physical_value), kAngleEpsilon)));
            GoboRotationMode next_mode = GoboRotationMode::Hold;
            double next_phase = current_phase;
            double next_velocity = 0.0;
            if (rotate_active) {
                next_mode = GoboRotationMode::Continuous;
                next_velocity = rotate_value.physical_value;
                if (pos_active && pos_changed) next_phase = pos_value.physical_value;
            } else if (pos_active) {
                next_mode = GoboRotationMode::Indexed;
                next_phase = pos_value.physical_value;
            }
            const bool changed = !state.initialized || state.mode != next_mode || pos_changed || rotate_changed ||
                !nearly_equal(static_cast<float>(state.angular_velocity_dps), static_cast<float>(next_velocity), kAngleEpsilon) ||
                (next_mode == GoboRotationMode::Indexed && !nearly_equal(static_cast<float>(state.phase_degrees), static_cast<float>(next_phase), kAngleEpsilon));
            state.pos_active = pos_active;
            state.pos_rotate_active = rotate_active;
            state.pos_binding_id = pos_active ? pos_binding->binding_id : 0;
            state.pos_rotate_binding_id = rotate_active ? rotate_binding->binding_id : 0;
            if (pos_active) state.pos_degrees = pos_value.physical_value;
            if (rotate_active) state.pos_rotate_dps = rotate_value.physical_value;
            if (!changed) continue;
            state.phase_degrees = next_phase;
            state.angular_velocity_dps = next_velocity;
            state.reference_seconds = motion_now;
            state.mode = next_mode;
            state.initialized = true;
            ++state.revision;
            if (active_pos_count > 1) ++stats_.ambiguous_gobo_pos_layers;
            if (active_rotate_count > 1) ++stats_.ambiguous_gobo_posrotate_layers;
            if (pos_active && rotate_active) ++stats_.simultaneous_gobo_pos_posrotate_layers;
            if (active_pos_count > 1 && diagnosed_ambiguous_gobo_pos_layers_.insert(layer_key).second) diagnostics_.push_back({"PVZ-RUNTIME-AMBIGUOUS-GOBO-POS", "warning", "Multiple active Gobo(n)Pos bindings share one physical layer; parser declaration order is used.", std::to_string(layer_key)});
            if (active_rotate_count > 1 && diagnosed_ambiguous_gobo_posrotate_layers_.insert(layer_key).second) diagnostics_.push_back({"PVZ-RUNTIME-AMBIGUOUS-GOBO-POSROTATE", "warning", "Multiple active Gobo(n)PosRotate bindings share one physical layer; parser declaration order is used.", std::to_string(layer_key)});
            if (pos_active && rotate_active && diagnosed_simultaneous_gobo_posrotate_layers_.insert(layer_key).second) diagnostics_.push_back({"PVZ-RUNTIME-SIMULTANEOUS-GOBO-POS-POSROTATE", "info", "Simultaneous Pos and PosRotate contribute indexed phase and signed velocity to one physical layer.", std::to_string(layer_key)});
            ++stats_.changed_gobo_rotation;
            ++stats_.gobo_parametric_updates;
            ++stats_.fixtures_dirty;
            const CompiledGoboMotionBinding &identity = rotate_active ? *rotate_binding : (pos_active ? *pos_binding : universe.gobo_motion_bindings[static_cast<size_t>(layer_it->second.front())].binding);
            gobo_rotation_rows.push_back({identity.fixture_id, identity.beam_render_target_id, identity.wheel_id, identity.wheel_instance_index, state.mode, static_cast<float>(state.phase_degrees), static_cast<float>(state.angular_velocity_dps), static_cast<float>(state.reference_seconds), state.revision});
        }

        std::unordered_map<int, ComponentState> pending_transform_by_fixture;
        for (int property_index : property_indices) {
            if (property_index < 0 || property_index >= static_cast<int>(universe.properties.size())) continue;
            const CompiledPropertyProgram &program = universe.properties[static_cast<size_t>(property_index)];
            const EvaluationResult evaluated = evaluate_property_value(universe, program);
            if (!evaluated.valid) continue;
            const float semantic_value = program.parameter == SemanticParameter::Dimmer ? evaluated.normalized_value : evaluated.physical_value;
            if (program.parameter == SemanticParameter::Dimmer || program.parameter == SemanticParameter::Zoom) {
                ComponentState state;
                auto existing = property_state_by_property_.find(program.property.property_id);
                if (existing != property_state_by_property_.end()) state = existing->second;
                apply_semantic_value(state, program.parameter, semantic_value);
                if (program.parameter == SemanticParameter::Zoom) { state.zoom_normalized = evaluated.normalized_value; state.has_zoom_physical = true; }
                const auto params_it = render_params_by_fixture_.find(program.property.fixture_id);
                cook_render_state(state, params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams());
                const FixtureChangeResult change = merge_property_state(program.property.property_id, state, visual_mask_for_parameter(program.parameter));
                if (!change.changed) { ++stats_.fixtures_skipped; continue; }
                add_visual_mask_stats(change.changed_visual_mask);
                ++stats_.fixtures_dirty;
                rows.push_back({program.property.fixture_id, program.property.render_target_id, change.changed_visual_mask, state, {}});
                continue;
            }
            ComponentState &state = pending_transform_by_fixture[program.property.fixture_id];
            auto existing = transform_state_by_fixture_.find(program.property.fixture_id);
            if (!state.initialized && existing != transform_state_by_fixture_.end()) state = existing->second;
            apply_semantic_value(state, program.parameter, semantic_value);
        }

        auto &dirty_color_targets=universe.dirty_color_targets; dirty_color_targets.clear();
        const auto color_start=performance_trace_enabled_?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
        for (int target_index : color_target_indices) {
            if (target_index < 0 || target_index >= static_cast<int>(universe.color_targets.size())) continue;
            ColorTargetRuntime &target = universe.color_targets[static_cast<size_t>(target_index)];
            bool input_changed = false;
            const bool prepared_color=prefetch_ && prefetch_->commit_color_inputs(universe_id,size_t(target_index),input_changed);
            if (!prepared_color) for (ColorInputRuntime &input : target.inputs) {
                if (input.initialized && !universe.plan.source_changed(input.source)) continue;
                const EvaluationResult evaluated = evaluate_cached_source(universe,input.source);
                if (!evaluated.valid) continue;
                const float next_value = color_value_from_evaluation(input.binding.semantic, evaluated);
                input_changed = input_changed || !input.initialized || !nearly_equal(input.value, next_value, kDefaultEpsilon);
                input.value = next_value;
                input.initialized = true;
                ++stats_.color_inputs_evaluated;
            }
            if (!input_changed) continue;
            dirty_color_targets.push_back(target.target.beam_render_target_id);
            ++stats_.color_targets_dirty;
            CookedEmitterColor cooked;
            if (!prefetch_ || !prefetch_->cooked_color(universe_id,size_t(target_index),cooked)) cooked=cook_emitter_color(target);
            base_color_state_by_target_[target.target.beam_render_target_id] = cooked;
            base_color_state_by_target_[target.target.beam_render_target_id].initialized = true;
            ++stats_.color_targets_cooked;
            auto dependent_wheels = universe.wheel_binding_indices_by_target.find(target.target.beam_render_target_id);
            if (dependent_wheels != universe.wheel_binding_indices_by_target.end()) wheel_binding_indices.insert(dependent_wheels->second.begin(), dependent_wheels->second.end());
        }


        if (performance_trace_enabled_) stats_.color_evaluation_us+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-color_start).count();
        auto &dirty_physical_wheels=universe.dirty_physical_wheels; dirty_physical_wheels.clear();
        for (int wheel_index : wheel_binding_indices) {
            if (wheel_index < 0 || wheel_index >= static_cast<int>(universe.wheel_bindings.size())) continue;
            const CompiledWheelTargetBinding &binding = universe.wheel_bindings[static_cast<size_t>(wheel_index)].binding;
            dirty_physical_wheels.push_back(wheel_physical_key(binding.beam_render_target_id, binding.wheel_renderer_id));
        }

        std::sort(dirty_physical_wheels.begin(),dirty_physical_wheels.end());
        dirty_physical_wheels.erase(std::unique(dirty_physical_wheels.begin(),dirty_physical_wheels.end()),dirty_physical_wheels.end());
        auto &wheel_dirty_targets=universe.wheel_dirty_targets; wheel_dirty_targets.clear();
        for (int64_t physical_key : dirty_physical_wheels) {
            auto group_it = universe.wheel_binding_indices_by_physical_key.find(physical_key);
            if (group_it == universe.wheel_binding_indices_by_physical_key.end()) continue;
            const WheelBindingRuntime *active_wheel = nullptr;
            const InstalledSourceProgram *active_program = nullptr;
            EvaluationResult active_evaluation;
            for (int wheel_index : group_it->second) {
                if (wheel_index < 0 || wheel_index >= static_cast<int>(universe.wheel_bindings.size())) continue;
                const WheelBindingRuntime &candidate = universe.wheel_bindings[static_cast<size_t>(wheel_index)];
                const InstalledSourceProgram *program=universe.source_bindings[candidate.source];
                const EvaluationResult evaluated = evaluate_cached_source(universe,candidate.source);
                if (!evaluated.valid) continue;
                ++stats_.wheel_inputs_evaluated;
                if (evaluated.raw_value < program->program.dmx_from || evaluated.raw_value > program->program.dmx_to) continue;
                if (active_wheel == nullptr) {
                    active_wheel = &candidate;
                    active_program = program;
                    active_evaluation = evaluated;
                } else {
                    diagnostics_.push_back({"PVZ-RUNTIME-WHEEL-RANGE-OVERLAP", "warning", "Multiple wheel control bindings were active for one physical wheel; using deterministic binding order.", std::to_string(candidate.binding.beam_render_target_id) + ":" + std::to_string(candidate.binding.wheel_renderer_id)});
                }
            }
            WheelTargetState &previous = wheel_state_by_physical_key_[physical_key];
            if (active_wheel == nullptr || active_program == nullptr) {
                if (previous.initialized) {
                    const int32_t previous_revision = previous.revision;
                    const int32_t beam_target_id = previous.beam_target_id;
                    const int32_t wheel_renderer_id = previous.wheel_renderer_id;
                    previous = {};
                    previous.beam_target_id = beam_target_id;
                    previous.wheel_renderer_id = wheel_renderer_id;
                    previous.revision = previous_revision + 1;
                    ++stats_.wheel_targets_dirty;
                    wheel_dirty_targets.push_back(beam_target_id);
                }
                continue;
            }
            const CompiledWheelTargetBinding &binding = active_wheel->binding;
            auto palette_it = wheel_palettes_by_id_.find(binding.wheel_renderer_id);
            if (palette_it == wheel_palettes_by_id_.end()) continue;
            const CompiledWheelPaletteSlot *slot_a = nullptr;
            const CompiledWheelPaletteSlot *slot_b = nullptr;
            float normalized_phase = 0.0f;
            float split_fraction = 0.0f;
            float boundary_angle_degrees = 0.0f;
            CookedEmitterColor cooked;
            if (binding.mode == CompiledWheelMode::Index) {
                const int32_t slot_count = static_cast<int32_t>(palette_it->second.slots.size());
                if (slot_count <= 0) continue;
                auto normalize_degrees = [](float degrees) { float wrapped = std::fmod(degrees, 360.0f); return wrapped < 0.0f ? wrapped + 360.0f : wrapped; };
                boundary_angle_degrees = normalize_degrees(active_evaluation.physical_value + binding.placement_offset_degrees);
                normalized_phase = boundary_angle_degrees / 360.0f;
                const float coordinate = normalized_phase * static_cast<float>(slot_count);
                const int32_t base_index = static_cast<int32_t>(std::floor(coordinate)) % slot_count;
                split_fraction = coordinate - std::floor(coordinate);
                slot_a = &palette_it->second.slots[static_cast<size_t>(base_index)];
                slot_b = &palette_it->second.slots[static_cast<size_t>((base_index + 1) % slot_count)];
                cooked = aggregate_indexed_wheel_layer(*slot_a, *slot_b, split_fraction);
            } else if (binding.mode == CompiledWheelMode::Select) {
                const CompiledWheelChannelSet *active_set = nullptr;
                for (const CompiledWheelChannelSet &set : binding.channel_sets) {
                    if (active_evaluation.raw_value >= set.dmx_from && active_evaluation.raw_value <= set.dmx_to) { active_set = &set; break; }
                }
                if (active_set == nullptr) continue;
                int slot_match_count = 0;
                for (const CompiledWheelPaletteSlot &candidate : palette_it->second.slots) {
                    if (candidate.slot_index != active_set->wheel_slot_index) continue;
                    slot_a = &candidate;
                    slot_b = &candidate;
                    ++slot_match_count;
                }
                if (slot_match_count != 1 || slot_a == nullptr) {
                    diagnostics_.push_back({"PVZ-RUNTIME-WHEEL-SLOT-LOOKUP", "error", "WheelSelection could not resolve exactly one palette slot for ChannelSet.WheelSlotIndex.", std::to_string(binding.binding_id) + " slot=" + std::to_string(active_set->wheel_slot_index)});
                    continue;
                }
                cooked = cook_wheel_slot_layer(*slot_a);
            } else {
                cooked = cook_wheel_slot_layer(palette_it->second.slots.front());
                slot_a = &palette_it->second.slots.front();
                slot_b = slot_a;
            }
            if (slot_a == nullptr || slot_b == nullptr) continue;
            const bool changed = !previous.initialized || previous.active_binding_id != binding.binding_id || previous.mode != binding.mode || previous.slot_a != slot_a->slot_index || previous.slot_b != slot_b->slot_index || !nearly_equal(previous.normalized_phase, normalized_phase, kDefaultEpsilon) || !nearly_equal(previous.split_fraction, split_fraction, kDefaultEpsilon) || !nearly_equal(previous.srgb_red, cooked.srgb_red, kDefaultEpsilon) || !nearly_equal(previous.srgb_green, cooked.srgb_green, kDefaultEpsilon) || !nearly_equal(previous.srgb_blue, cooked.srgb_blue, kDefaultEpsilon) || !nearly_equal(previous.gain, cooked.gain, kDefaultEpsilon);
            if (!changed) { ++stats_.wheel_states_skipped; continue; }
            const int32_t next_revision = previous.revision + 1;
            previous = {};
            previous.initialized = true;
            previous.active_binding_id = binding.binding_id;
            previous.beam_target_id = binding.beam_render_target_id;
            previous.wheel_renderer_id = binding.wheel_renderer_id;
            previous.mode = binding.mode;
            previous.slot_a = slot_a->slot_index;
            previous.slot_b = slot_b->slot_index;
            previous.normalized_phase = normalized_phase;
            previous.split_fraction = split_fraction;
            previous.boundary_angle_degrees = boundary_angle_degrees;
            previous.srgb_red = cooked.srgb_red;
            previous.srgb_green = cooked.srgb_green;
            previous.srgb_blue = cooked.srgb_blue;
            previous.gain = cooked.gain;
            previous.linear_red = cooked.linear_red;
            previous.linear_green = cooked.linear_green;
            previous.linear_blue = cooked.linear_blue;
            previous.revision = next_revision;
            ++stats_.wheel_targets_dirty;
            wheel_dirty_targets.push_back(binding.beam_render_target_id);
            ++stats_.wheel_selection_rows;
            ++stats_.fixtures_dirty;
            rows.push_back({binding.fixture_id, binding.beam_render_target_id, VisualChangeColor, {}, cooked, binding.wheel_renderer_id, slot_a->slot_index, slot_b->slot_index, normalized_phase, split_fraction, boundary_angle_degrees, binding.mode, previous.revision, true});
        }

        const auto composition_start=performance_trace_enabled_?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
        dirty_color_targets.insert(dirty_color_targets.end(),wheel_dirty_targets.begin(),wheel_dirty_targets.end());
        std::sort(dirty_color_targets.begin(),dirty_color_targets.end());
        dirty_color_targets.erase(std::unique(dirty_color_targets.begin(),dirty_color_targets.end()),dirty_color_targets.end());
        if (performance_trace_enabled_) stats_.color_dirty_candidates += dirty_color_targets.size();
        for (int32_t beam_target_id : dirty_color_targets) {
            CookedEmitterColor composed;
            if (!prefetch_ || !prefetch_->final_color(universe_id,beam_target_id,composed)) composed=compose_ordered_target_color(beam_target_id);
            CookedEmitterColor &previous = color_state_by_target_[beam_target_id];
            const bool initialized = previous.initialized;
            const float useful_delta = initialized ? std::max({std::fabs(previous.srgb_red - composed.srgb_red), std::fabs(previous.srgb_green - composed.srgb_green), std::fabs(previous.srgb_blue - composed.srgb_blue), std::fabs(previous.gain - composed.gain)}) : 1.0f;
            const bool changed = !initialized || useful_delta > kDefaultEpsilon || previous.valid != composed.valid;
            previous = composed;
            previous.initialized = true;
            if (!changed) {
                ++stats_.fixtures_skipped;
                if (performance_trace_enabled_) ++stats_.color_composed_unchanged;
                continue;
            }
            if (performance_trace_enabled_) {
                const uint64_t delta_microunits = static_cast<uint64_t>(std::llround(static_cast<double>(useful_delta) * 1000000.0));
                stats_.color_delta_sum_microunits += delta_microunits;
                stats_.color_delta_max_microunits = std::max(stats_.color_delta_max_microunits, delta_microunits);
                if (useful_delta < 0.001f) ++stats_.color_delta_tiny;
                else if (useful_delta < 0.01f) ++stats_.color_delta_small;
                else ++stats_.color_delta_visible;
            }
            // Canonical owner lookup is setup-indexed; dynamic Color must not scan every peer target.
            const auto owner=universe.color_fixture_by_target.find(beam_target_id);
            const int fixture_id=owner==universe.color_fixture_by_target.end()?0:owner->second;
            add_visual_mask_stats(VisualChangeColor);
            ++stats_.fixtures_dirty;
            ++stats_.color_rows;
            rows.push_back({fixture_id, beam_target_id, VisualChangeColor, {}, composed});
        }
        if (performance_trace_enabled_) stats_.color_composition_us+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-composition_start).count();
        for (auto &[fixture_id, next_state] : pending_transform_by_fixture) {
            const auto params_it = render_params_by_fixture_.find(fixture_id);
            cook_render_state(next_state, params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams());
            const FixtureChangeResult change = merge_transform_state(fixture_id, next_state);
            if (!change.changed) { ++stats_.fixtures_skipped; continue; }
            add_visual_mask_stats(change.changed_visual_mask);
            ++stats_.fixtures_dirty;
            rows.push_back({fixture_id, 0, change.changed_visual_mask, next_state, {}});
        }
    }

    auto section_count_for = [&rows](uint32_t mask) { return static_cast<int32_t>(std::count_if(rows.begin(), rows.end(), [mask](const PendingRow &row) { return (row.changed_visual_mask & mask) != 0U; })); };
    const int32_t transform_count = section_count_for(VisualChangeTransform);
    if (transform_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeTransform) == 0U) continue;
            const int32_t pan_component_id = pan_component_id_by_fixture_.count(row.fixture_id) != 0 ? pan_component_id_by_fixture_[row.fixture_id] : 0;
            const int32_t tilt_component_id = tilt_component_id_by_fixture_.count(row.fixture_id) != 0 ? tilt_component_id_by_fixture_[row.fixture_id] : 0;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, pan_component_id, tilt_component_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.pan, row.state.tilt});
        }
        append_descriptor(frame, VisualSectionType::GeometryTransform, transform_count, int_offset, float_offset);
    }
    const int32_t intensity_count = section_count_for(VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology);
    if (intensity_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & (VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology)) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.render_target_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.dimmer, row.state.beam_energy, row.state.spot_energy, row.state.beam_intensity, row.state.material_energy});
        }
        append_descriptor(frame, VisualSectionType::EmitterIntensity, intensity_count, int_offset, float_offset);
    }
    const int32_t color_count = static_cast<int32_t>(std::count_if(rows.begin(), rows.end(), [](const PendingRow &row) { return (row.changed_visual_mask & VisualChangeColor) != 0U && !row.wheel_row; }));
    if (color_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeColor) == 0U || row.wheel_row) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.render_target_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.color.srgb_red, row.color.srgb_green, row.color.srgb_blue, row.color.gain});
        }
        append_descriptor(frame, VisualSectionType::EmitterColor, color_count, int_offset, float_offset);
    }

    const int32_t wheel_count = static_cast<int32_t>(std::count_if(rows.begin(), rows.end(), [](const PendingRow &row) { return row.wheel_row; }));
    if (wheel_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if (!row.wheel_row) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.render_target_id, row.wheel_id, static_cast<int32_t>(row.wheel_mode), row.slot_a, row.slot_b, static_cast<int32_t>(VisualChangeColor), row.revision});
            frame.floats.insert(frame.floats.end(), {row.normalized_phase, row.split_fraction, row.boundary_angle_degrees, row.color.srgb_red, row.color.srgb_green, row.color.srgb_blue, row.color.gain, 0.02f});
        }
        append_descriptor(frame, VisualSectionType::WheelSelection, wheel_count, int_offset, float_offset);
    }
    const int32_t optics_count = section_count_for(VisualChangeZoom);
    if (optics_count > 0) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const PendingRow &row : rows) {
            if ((row.changed_visual_mask & VisualChangeZoom) == 0U) continue;
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.render_target_id, static_cast<int32_t>(row.changed_visual_mask)});
            frame.floats.insert(frame.floats.end(), {row.state.beam_half_angle, row.state.beam_angle, row.state.zoom_normalized});
        }
        append_descriptor(frame, VisualSectionType::BeamOptics, optics_count, int_offset, float_offset);
    }
    if (!gobo_rows.empty()) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const GoboRow &row : gobo_rows) {
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.beam_target_id, row.wheel_id, row.wheel_instance_index, row.slot_index, row.asset_id, static_cast<int32_t>(row.mode), static_cast<int32_t>(VisualChangeGobo | VisualChangeBeamTopology), row.revision});
            frame.floats.push_back(0.0f);
        }
        append_descriptor(frame, VisualSectionType::GoboSelection, static_cast<int32_t>(gobo_rows.size()), int_offset, float_offset);
    }
    if (!gobo_rotation_rows.empty()) {
        const int32_t int_offset = static_cast<int32_t>(frame.integers.size());
        const int32_t float_offset = static_cast<int32_t>(frame.floats.size());
        for (const GoboRotationRow &row : gobo_rotation_rows) {
            frame.integers.insert(frame.integers.end(), {row.fixture_id, row.beam_target_id, row.wheel_id, row.wheel_instance_index, static_cast<int32_t>(row.mode), static_cast<int32_t>(VisualChangeGoboRotation), row.revision});
            frame.floats.insert(frame.floats.end(), {row.phase_degrees, row.angular_velocity_dps, row.reference_seconds});
        }
        append_descriptor(frame, VisualSectionType::GoboRotation, static_cast<int32_t>(gobo_rotation_rows.size()), int_offset, float_offset);
    }
    if (prefetch_) prefetch_->observe_completion();
    frame.stats = stats_;
}

// Returns the immutable schema currently used by emitted sectioned frames.
const VisualFrameSchema &PeravizVisualRuntimeCore::schema() const { return schema_; }

// Returns cumulative runtime counters for debug UI and benchmarks.
const VisualFrameStats &PeravizVisualRuntimeCore::stats() const { return stats_; }

// Enables bounded color-dirty diagnostics without affecting production playback.
void PeravizVisualRuntimeCore::set_performance_trace_enabled(bool enabled) { performance_trace_enabled_ = enabled; }

// Returns the runtime-local monotonic time used by authoritative motion commands.
double PeravizVisualRuntimeCore::runtime_now_seconds() const {
    if (test_runtime_now_seconds_ >= 0.0) return test_runtime_now_seconds_;
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - runtime_epoch_).count();
}

// Overrides the monotonic clock for deterministic native tests.
void PeravizVisualRuntimeCore::set_runtime_now_seconds_for_testing(double seconds) { test_runtime_now_seconds_ = seconds; }

// Maps compiled semantic identifiers into runtime component state parameters.
SemanticParameter PeravizVisualRuntimeCore::semantic_parameter_for_compiled(CompiledSemantic semantic) {
    switch (semantic) {
        case CompiledSemantic::Pan: return SemanticParameter::Pan;
        case CompiledSemantic::Tilt: return SemanticParameter::Tilt;
        case CompiledSemantic::Dimmer: return SemanticParameter::Dimmer;
        case CompiledSemantic::Zoom: return SemanticParameter::Zoom;
        case CompiledSemantic::ColorAddRed: return SemanticParameter::ColorAddRed;
        case CompiledSemantic::ColorAddGreen: return SemanticParameter::ColorAddGreen;
        case CompiledSemantic::ColorAddBlue: return SemanticParameter::ColorAddBlue;
        case CompiledSemantic::ColorAddWhite: return SemanticParameter::ColorAddWhite;
        case CompiledSemantic::ColorAddAmber: return SemanticParameter::ColorAddAmber;
        case CompiledSemantic::ColorAddLime: return SemanticParameter::ColorAddLime;
        case CompiledSemantic::ColorSubCyan: return SemanticParameter::ColorSubCyan;
        case CompiledSemantic::ColorSubMagenta: return SemanticParameter::ColorSubMagenta;
        case CompiledSemantic::ColorSubYellow: return SemanticParameter::ColorSubYellow;
        case CompiledSemantic::Unknown: return SemanticParameter::Unknown;
    }
    return SemanticParameter::Unknown;
}

// Returns true when a compiled semantic belongs to the corrected color target slice.
bool PeravizVisualRuntimeCore::is_color_semantic(CompiledSemantic semantic) {
    return semantic == CompiledSemantic::ColorAddRed || semantic == CompiledSemantic::ColorAddGreen || semantic == CompiledSemantic::ColorAddBlue || semantic == CompiledSemantic::ColorAddWhite || semantic == CompiledSemantic::ColorAddAmber || semantic == CompiledSemantic::ColorAddLime || semantic == CompiledSemantic::ColorSubCyan || semantic == CompiledSemantic::ColorSubMagenta || semantic == CompiledSemantic::ColorSubYellow || semantic == CompiledSemantic::CieX || semantic == CompiledSemantic::CieY || semantic == CompiledSemantic::CieBrightness || semantic == CompiledSemantic::Cto || semantic == CompiledSemantic::Ctb || semantic == CompiledSemantic::Ctc || semantic == CompiledSemantic::Tint;
}

// Returns the maximum assembled raw DMX value for an ordered source width.
uint32_t PeravizVisualRuntimeCore::max_raw_value_for_source_count(size_t source_count) {
    uint32_t max_value = 0;
    for (size_t index = 0; index < source_count && index < 4; ++index) max_value = (max_value << 8U) | 0xffU;
    return max_value;
}

// Maps a semantic parameter to the render domains it can dirty.
uint32_t PeravizVisualRuntimeCore::visual_mask_for_parameter(SemanticParameter parameter) {
    switch (parameter) {
        case SemanticParameter::Dimmer: return VisualChangeDimmer | VisualChangeMaterial;
        case SemanticParameter::Pan:
        case SemanticParameter::Tilt: return VisualChangeTransform;
        case SemanticParameter::Zoom: return VisualChangeZoom;
        case SemanticParameter::ColorAddRed:
        case SemanticParameter::ColorAddGreen:
        case SemanticParameter::ColorAddBlue:
        case SemanticParameter::ColorAddWhite:
        case SemanticParameter::ColorAddAmber:
        case SemanticParameter::ColorAddLime:
        case SemanticParameter::ColorSubCyan:
        case SemanticParameter::ColorSubMagenta:
        case SemanticParameter::ColorSubYellow:
        case SemanticParameter::Cyan:
        case SemanticParameter::Magenta:
        case SemanticParameter::Yellow: return VisualChangeColor;
        case SemanticParameter::GoboSelect:
        case SemanticParameter::GoboIndex: return VisualChangeGobo | VisualChangeBeamTopology;
        case SemanticParameter::GoboRotation: return VisualChangeGoboRotation;
        case SemanticParameter::PrismSelect:
        case SemanticParameter::PrismRotation: return VisualChangePrism;
        case SemanticParameter::Strobe: return VisualChangeStrobe;
        case SemanticParameter::Unknown: return VisualChangeNone;
    }
    return VisualChangeNone;
}

// Writes the incoming semantic value into the component-oriented fixture state.
void PeravizVisualRuntimeCore::apply_semantic_value(ComponentState &state, SemanticParameter parameter, float value) {
    switch (parameter) {
        case SemanticParameter::Pan: state.pan = value; break;
        case SemanticParameter::Tilt: state.tilt = value; break;
        case SemanticParameter::Dimmer: state.dimmer = value; break;
        case SemanticParameter::Zoom: state.zoom = value; break;
        default: break;
    }
}

// Cooks physical render values from component state without changing semantic ownership.
void PeravizVisualRuntimeCore::cook_render_state(ComponentState &state, const FixtureRenderParams &params) {
    constexpr double energy_scale = 0.02;
    constexpr double default_zoom_min = 4.0;
    constexpr double max_beam_angle = 90.0;
    constexpr double beam_intensity_max = 50.0;
    double beam_angle = std::clamp(params.beam_angle_default, 0.1, max_beam_angle);
    if (params.has_zoom) {
        if (state.has_zoom_physical) beam_angle = std::clamp(static_cast<double>(state.zoom), 0.0, max_beam_angle);
        else {
            double zoom_min = params.zoom_min_deg >= 0.0 ? params.zoom_min_deg : default_zoom_min;
            double zoom_max = params.zoom_max_deg >= 0.0 ? params.zoom_max_deg : max_beam_angle;
            beam_angle = std::clamp(zoom_min + ((zoom_max - zoom_min) * state.zoom_normalized), 0.0, max_beam_angle);
        }
    }
    const double base_energy = std::max(params.luminous_flux, 0.0) * state.dimmer * energy_scale;
    state.beam_energy = static_cast<float>(base_energy);
    state.spot_energy = static_cast<float>(base_energy * params.spot_multiplier);
    state.beam_half_angle = static_cast<float>(beam_angle * 0.5);
    state.beam_angle = static_cast<float>(beam_angle);
    state.beam_intensity = static_cast<float>(std::clamp(state.dimmer * params.beam_multiplier, 0.0, beam_intensity_max));
    state.material_energy = state.dimmer * 4.0f;
}

// Compares two component values using section-appropriate tolerances.
bool PeravizVisualRuntimeCore::nearly_equal(float a, float b, float epsilon) { return std::fabs(a - b) <= epsilon; }

// Selects normalized or physical color input values for the supported fallback color slice.
float PeravizVisualRuntimeCore::color_value_from_evaluation(CompiledSemantic semantic, const EvaluationResult &evaluated) {
    const bool unit_physical = semantic == CompiledSemantic::ColorAddRed || semantic == CompiledSemantic::ColorAddGreen || semantic == CompiledSemantic::ColorAddBlue || semantic == CompiledSemantic::ColorAddWhite || semantic == CompiledSemantic::ColorAddAmber || semantic == CompiledSemantic::ColorAddLime || semantic == CompiledSemantic::CieX || semantic == CompiledSemantic::CieY || semantic == CompiledSemantic::CieBrightness || semantic == CompiledSemantic::Tint;
    if (unit_physical && evaluated.physical_value >= -1.0f && evaluated.physical_value <= 1.0f) return evaluated.physical_value;
    if ((semantic == CompiledSemantic::Cto || semantic == CompiledSemantic::Ctb || semantic == CompiledSemantic::Ctc) && evaluated.physical_value > 0.0f) return evaluated.physical_value;
    return std::clamp(evaluated.normalized_value, 0.0f, 1.0f);
}

// Builds a stable key for one physical wheel layer on one Beam target.
int64_t PeravizVisualRuntimeCore::wheel_physical_key(int32_t beam_target_id, int32_t wheel_renderer_id) {
    return (static_cast<int64_t>(beam_target_id) << 32) ^ static_cast<uint32_t>(wheel_renderer_id);
}


// Composes one complete color target once into renderer-ready sRGB plus linear gain.
PeravizVisualRuntimeCore::CookedEmitterColor PeravizVisualRuntimeCore::cook_emitter_color(const ColorTargetRuntime &target,const float *overrides) const {
    runtime::LinearRgb add;
    float sub_c = 0.0f, sub_m = 0.0f, sub_y = 0.0f;
    std::vector<std::pair<const CompiledFilterResource *, float>> physical_filters;
    bool has_additive = target.target.additive_source;
    bool has_cie_x = false, has_cie_y = false, has_cie_brightness = false;
    float cie_x = 0.0f, cie_y = 0.0f, cie_brightness = 0.0f;
    float cct_kelvin = 0.0f;
    float tint_value = 0.0f;
    bool has_tint = false;
    for (size_t i=0;i<target.inputs.size();++i) {
        const ColorInputRuntime &input=target.inputs[i];
        const float raw=overrides?overrides[i]:input.value;
        const float v = std::clamp(raw, 0.0f, 1.0f);
        const auto emitter_it = emitter_resources_by_id_.find(input.binding.emitter_resource_id);
        const auto filter_it = filter_resources_by_id_.find(input.binding.filter_resource_id);
        if (emitter_it != emitter_resources_by_id_.end() && emitter_it->second.valid) {
            const CompiledEmitterResource &emitter = emitter_it->second;
            add.r += emitter.fallback_linear_r * v;
            add.g += emitter.fallback_linear_g * v;
            add.b += emitter.fallback_linear_b * v;
            has_additive = true;
            continue;
        }
        if (filter_it != filter_resources_by_id_.end() && filter_it->second.valid) {
            physical_filters.push_back({&filter_it->second, v});
            continue;
        }
        switch (input.binding.semantic) {
            case CompiledSemantic::ColorAddRed: add.r += v; has_additive = true; break;
            case CompiledSemantic::ColorAddGreen: add.g += v; has_additive = true; break;
            case CompiledSemantic::ColorAddBlue: add.b += v; has_additive = true; break;
            case CompiledSemantic::ColorAddWhite: add.r += v; add.g += v; add.b += v; has_additive = true; break;
            case CompiledSemantic::ColorAddAmber: add.r += v; add.g += v * 0.45f; has_additive = true; break;
            case CompiledSemantic::ColorAddLime: add.g += v; add.r += v * 0.15f; has_additive = true; break;
            case CompiledSemantic::ColorSubCyan: sub_c = std::max(sub_c, v); break;
            case CompiledSemantic::ColorSubMagenta: sub_m = std::max(sub_m, v); break;
            case CompiledSemantic::ColorSubYellow: sub_y = std::max(sub_y, v); break;
            case CompiledSemantic::CieX: cie_x = raw; has_cie_x = true; break;
            case CompiledSemantic::CieY: cie_y = raw; has_cie_y = true; break;
            case CompiledSemantic::CieBrightness: cie_brightness = std::max(0.0f, raw); has_cie_brightness = true; break;
            case CompiledSemantic::Cto:
            case CompiledSemantic::Ctb:
            case CompiledSemantic::Ctc: cct_kelvin = raw; break;
            case CompiledSemantic::Tint: tint_value = raw; has_tint = true; break;
            default: break;
        }
    }
    runtime::LinearRgb linear = has_additive ? add : runtime::LinearRgb{1.0, 1.0, 1.0};
    if (has_cie_x && has_cie_y && has_cie_brightness) {
        linear = runtime::xyz_to_linear_srgb(runtime::cie_xyy_to_xyz({cie_x, cie_y, cie_brightness, true}));
    }
    for (const auto &entry : physical_filters) {
        const CompiledFilterResource &filter = *entry.first;
        const double insertion = std::clamp<double>(entry.second, 0.0, 1.0);
        const double transmission = 1.0 + (std::clamp(filter.fallback_transmission, 0.0, 1.0) - 1.0) * insertion;
        linear.r *= transmission * (1.0 + (std::clamp(filter.fallback_linear_r, 0.0, 1.0) - 1.0) * insertion);
        linear.g *= transmission * (1.0 + (std::clamp(filter.fallback_linear_g, 0.0, 1.0) - 1.0) * insertion);
        linear.b *= transmission * (1.0 + (std::clamp(filter.fallback_linear_b, 0.0, 1.0) - 1.0) * insertion);
    }
    linear.r *= 1.0f - std::clamp(sub_c, 0.0f, 1.0f);
    linear.g *= 1.0f - std::clamp(sub_m, 0.0f, 1.0f);
    linear.b *= 1.0f - std::clamp(sub_y, 0.0f, 1.0f);
    if (cct_kelvin > 0.0f && std::isfinite(cct_kelvin)) {
        const runtime::LinearRgb white = runtime::cct_to_linear_srgb(cct_kelvin);
        linear.r *= white.r;
        linear.g *= white.g;
        linear.b *= white.b;
    }
    if (has_tint) {
        const double shift = std::clamp<double>(tint_value, -1.0, 1.0) * 0.08;
        linear.g *= 1.0 + shift;
        linear.r *= 1.0 - shift * 0.5;
        linear.b *= 1.0 - shift * 0.5;
    }
    double gain = 0.0;
    const runtime::LinearRgb normalized = runtime::normalize_color_gain(linear, gain);
    if (gain <= 0.0) return {0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, true, true};
    return {static_cast<float>(runtime::srgb_encode(normalized.r)), static_cast<float>(runtime::srgb_encode(normalized.g)), static_cast<float>(runtime::srgb_encode(normalized.b)), static_cast<float>(gain), normalized.r, normalized.g, normalized.b, true, true};
}


// Composes the authoritative final color from the target-local base state and ordered wheel layers.
PeravizVisualRuntimeCore::CookedEmitterColor PeravizVisualRuntimeCore::compose_ordered_target_color(int32_t beam_target_id,const CookedEmitterColor *base_override) const {
    CookedEmitterColor base;
    if (base_override) base=*base_override;
    else {
        const auto base_it = base_color_state_by_target_.find(beam_target_id);
        if (base_it != base_color_state_by_target_.end() && base_it->second.initialized) base = base_it->second;
    }
    runtime::LinearRgb absolute = {base.linear_red * base.gain, base.linear_green * base.gain, base.linear_blue * base.gain};
    const auto layers=ordered_wheel_layers_.find(beam_target_id);
    if (layers!=ordered_wheel_layers_.end()) for (const WheelTargetState *entry:layers->second) {
        const WheelTargetState &layer = *entry;
        if (!layer.initialized) continue;
        absolute.r *= layer.linear_red * layer.gain;
        absolute.g *= layer.linear_green * layer.gain;
        absolute.b *= layer.linear_blue * layer.gain;
    }
    double gain = 0.0;
    const runtime::LinearRgb normalized = runtime::normalize_color_gain(absolute, gain);
    if (gain <= 0.0) return {0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, true, true};
    return {static_cast<float>(runtime::srgb_encode(normalized.r)), static_cast<float>(runtime::srgb_encode(normalized.g)), static_cast<float>(runtime::srgb_encode(normalized.b)), static_cast<float>(gain), normalized.r, normalized.g, normalized.b, true, true};
}

// Cooks one seated wheel slot as a target-local optical layer without reading upstream color.
PeravizVisualRuntimeCore::CookedEmitterColor PeravizVisualRuntimeCore::cook_wheel_slot_layer(const CompiledWheelPaletteSlot &slot) const {
    runtime::LinearRgb linear = {std::clamp<double>(slot.linear_red, 0.0, 1.0), std::clamp<double>(slot.linear_green, 0.0, 1.0), std::clamp<double>(slot.linear_blue, 0.0, 1.0)};
    const float gain = std::max(0.0f, slot.gain);
    if (gain <= 0.0f || (linear.r <= 0.0 && linear.g <= 0.0 && linear.b <= 0.0)) return {0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, true, true};
    return {static_cast<float>(runtime::srgb_encode(linear.r)), static_cast<float>(runtime::srgb_encode(linear.g)), static_cast<float>(runtime::srgb_encode(linear.b)), gain, linear.r, linear.g, linear.b, true, true};
}

// Aggregates adjacent indexed wheel slots as a temporary non-spatial optical layer.
PeravizVisualRuntimeCore::CookedEmitterColor PeravizVisualRuntimeCore::aggregate_indexed_wheel_layer(const CompiledWheelPaletteSlot &slot_a, const CompiledWheelPaletteSlot &slot_b, float split_fraction) const {
    const double b_weight = std::clamp(static_cast<double>(split_fraction), 0.0, 1.0);
    const double a_weight = 1.0 - b_weight;
    runtime::LinearRgb aggregate;
    aggregate.r = std::clamp<double>(slot_a.linear_red, 0.0, 1.0) * std::max(0.0f, slot_a.gain) * a_weight + std::clamp<double>(slot_b.linear_red, 0.0, 1.0) * std::max(0.0f, slot_b.gain) * b_weight;
    aggregate.g = std::clamp<double>(slot_a.linear_green, 0.0, 1.0) * std::max(0.0f, slot_a.gain) * a_weight + std::clamp<double>(slot_b.linear_green, 0.0, 1.0) * std::max(0.0f, slot_b.gain) * b_weight;
    aggregate.b = std::clamp<double>(slot_a.linear_blue, 0.0, 1.0) * std::max(0.0f, slot_a.gain) * a_weight + std::clamp<double>(slot_b.linear_blue, 0.0, 1.0) * std::max(0.0f, slot_b.gain) * b_weight;
    double gain = 0.0;
    const runtime::LinearRgb normalized = runtime::normalize_color_gain(aggregate, gain);
    if (gain <= 0.0) return {0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, true, true};
    return {static_cast<float>(runtime::srgb_encode(normalized.r)), static_cast<float>(runtime::srgb_encode(normalized.g)), static_cast<float>(runtime::srgb_encode(normalized.b)), static_cast<float>(gain), normalized.r, normalized.g, normalized.b, true, true};
}

// Adds cumulative per-category visual mask counters for diagnostics.
void PeravizVisualRuntimeCore::add_visual_mask_stats(uint32_t visual_mask) {
    if ((visual_mask & VisualChangeTransform) != 0U) ++stats_.changed_transform;
    if ((visual_mask & VisualChangeDimmer) != 0U) ++stats_.changed_dimmer;
    if ((visual_mask & VisualChangeColor) != 0U) ++stats_.changed_color;
    if ((visual_mask & VisualChangeZoom) != 0U) ++stats_.changed_zoom;
    if ((visual_mask & VisualChangeGobo) != 0U) { ++stats_.changed_gobo; ++stats_.gobo_topology_updates; }
    if ((visual_mask & VisualChangeGoboRotation) != 0U) { ++stats_.changed_gobo_rotation; ++stats_.gobo_parametric_updates; }
    if ((visual_mask & VisualChangeZoom) != 0U) { ++stats_.beam_optics_rows; ++stats_.beam_optics_parametric_updates; }
}

// Updates cached transform state and returns the semantic render domains that changed.
PeravizVisualRuntimeCore::FixtureChangeResult PeravizVisualRuntimeCore::merge_transform_state(int fixture_id, const ComponentState &next_state) {
    ComponentState &previous = transform_state_by_fixture_[fixture_id];
    FixtureChangeResult result;
    if (!previous.initialized) {
        const auto mask_it = installed_visual_mask_by_fixture_.find(fixture_id);
        const uint32_t installed_mask = mask_it != installed_visual_mask_by_fixture_.end() ? mask_it->second : VisualChangeNone;
        result.changed_visual_mask = installed_mask & VisualChangeTransform;
    } else if (!nearly_equal(previous.pan, next_state.pan, kDefaultEpsilon) || !nearly_equal(previous.tilt, next_state.tilt, kDefaultEpsilon)) {
        result.changed_visual_mask = VisualChangeTransform;
    }
    result.changed = result.changed_visual_mask != VisualChangeNone;
    previous = next_state;
    previous.initialized = true;
    return result;
}

// Updates cached property state and returns target-local render domains that changed.
PeravizVisualRuntimeCore::FixtureChangeResult PeravizVisualRuntimeCore::merge_property_state(int32_t property_id, const ComponentState &next_state, uint32_t installed_mask) {
    ComponentState &previous = property_state_by_property_[property_id];
    FixtureChangeResult result;
    if (!previous.initialized) {
        result.changed_visual_mask = installed_mask;
    } else {
        if (!nearly_equal(previous.dimmer, next_state.dimmer, kDefaultEpsilon)) result.changed_visual_mask |= installed_mask & visual_mask_for_parameter(SemanticParameter::Dimmer);
        if (previous.has_zoom_physical != next_state.has_zoom_physical || !nearly_equal(previous.zoom, next_state.zoom, kAngleEpsilon) || !nearly_equal(previous.zoom_normalized, next_state.zoom_normalized, kDefaultEpsilon) || !nearly_equal(previous.beam_angle, next_state.beam_angle, kAngleEpsilon)) result.changed_visual_mask |= installed_mask & visual_mask_for_parameter(SemanticParameter::Zoom);
    }
    result.changed_visual_mask &= installed_mask;
    result.changed = result.changed_visual_mask != VisualChangeNone;
    previous = next_state;
    previous.initialized = true;
    return result;
}

} // namespace peraviz::runtime
