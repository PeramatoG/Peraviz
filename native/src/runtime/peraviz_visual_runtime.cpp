#include "runtime/peraviz_visual_runtime.h"
#include "runtime/color_science.h"

#include <algorithm>
#include <cmath>
#include <set>

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

// Clears bindings, cached frames, fixture state, and runtime counters.
void PeravizVisualRuntimeCore::clear() {
    universes_.clear();
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
    wheel_state_by_binding_.clear();
    stats_ = VisualFrameStats();
    schema_ = make_visual_frame_schema(++next_schema_generation_, VisualFrameSchemaCapabilities());
}

// Installs parser-owned compiled scene programs as the only runtime setup authority.
void PeravizVisualRuntimeCore::install_compiled_scene(const CompiledRuntimeScene &scene) {
    clear();
    diagnostics_ = scene.diagnostics;
    VisualFrameSchemaCapabilities capabilities;
    if (scene.fixtures.empty()) {
        diagnostics_.push_back({"PVZ-RUNTIME-EMPTY-SCENE", "error", "Compiled runtime scene contains no fixture instances.", "CompiledRuntimeScene"});
    }
    for (const CompiledEmitterResource &resource : scene.emitter_resources) emitter_resources_by_id_[resource.resource_id] = resource;
    for (const CompiledFilterResource &resource : scene.filter_resources) filter_resources_by_id_[resource.resource_id] = resource;
    for (const CompiledWheelPalette &palette : scene.wheel_palettes) wheel_palettes_by_id_[palette.wheel_renderer_id] = palette;
    for (const CompiledDmxSourceProgram &program : scene.source_programs) {
        if (program.program_id <= 0 || source_programs_by_id_.find(program.program_id) != source_programs_by_id_.end()) {
            diagnostics_.push_back({"PVZ-RUNTIME-DUPLICATE-PROGRAM", "error", "Compiled source program ID is invalid or duplicated.", std::to_string(program.program_id)});
            continue;
        }
        InstalledSourceProgram installed;
        installed.program = program;
        std::sort(installed.program.sources.begin(), installed.program.sources.end(), [](const CompiledDmxByteSource &a, const CompiledDmxByteSource &b) { return a.byte_order < b.byte_order; });
        installed.max_value = max_raw_value_for_source_count(installed.program.sources.size());
        installed.inverse_max_value = installed.max_value > 0U ? 1.0 / static_cast<double>(installed.max_value) : 0.0;
        source_programs_by_id_[program.program_id] = installed;
    }
    for (const CompiledFixtureInstance &fixture : scene.fixtures) {
        if (fixture.fixture_id <= 0 || fixture.universe_id < 0 || fixture.start_address < 1 || fixture.start_address > 512) {
            diagnostics_.push_back({"PVZ-RUNTIME-INVALID-PATCH", "error", "Compiled fixture has an invalid ID, universe, or patch address.", fixture.fixture_uuid});
            continue;
        }
        FixtureRenderParams params;
        params.luminous_flux = fixture.luminous_flux;
        params.beam_angle_default = fixture.beam_angle_default;
        params.spot_multiplier = fixture.spot_multiplier;
        params.beam_multiplier = fixture.beam_multiplier;
        render_params_by_fixture_[fixture.fixture_id] = params;
    }
    int installed_properties = 0;
    for (const CompiledComponentProperty &property : scene.properties) {
        const SemanticParameter parameter = semantic_parameter_for_compiled(property.semantic);
        if (property.property_id <= 0 || property.fixture_id <= 0 || parameter == SemanticParameter::Unknown || property.contributors.empty()) {
            diagnostics_.push_back({"PVZ-RUNTIME-INVALID-PROPERTY", "warning", "Compiled property is missing property ID, fixture, semantic, or contributors.", std::to_string(property.fixture_id)});
            continue;
        }
        int property_universe = -1;
        bool valid_property = true;
        for (const CompiledPropertyContributor &contributor : property.contributors) {
            auto program_it = source_programs_by_id_.find(contributor.source_program_id);
            if (program_it == source_programs_by_id_.end()) {
                diagnostics_.push_back({"PVZ-RUNTIME-MISSING-PROGRAM", "warning", "Compiled property references a missing source program.", std::to_string(contributor.source_program_id)});
                valid_property = false;
                continue;
            }
            const CompiledDmxSourceProgram &program = program_it->second.program;
            if (program.sources.empty() || program.sources.size() > 4) {
                diagnostics_.push_back({"PVZ-RUNTIME-INVALID-SOURCE-COUNT", "warning", "Compiled source program must contain one to four DMX byte sources.", std::to_string(program.program_id)});
                valid_property = false;
                continue;
            }
            for (const CompiledDmxByteSource &source : program.sources) {
                if (source.address < 0 || source.address >= 512) {
                    diagnostics_.push_back({"PVZ-RUNTIME-SOURCE-OUT-OF-RANGE", "warning", "Compiled DMX byte source is outside the 512-slot universe.", std::to_string(program.program_id)});
                    valid_property = false;
                }
                if (property_universe < 0) property_universe = source.universe_id;
                if (source.universe_id != property_universe) {
                    diagnostics_.push_back({"PVZ-RUNTIME-CROSS-UNIVERSE-PROPERTY", "warning", "Compiled property spans universes, which is not supported by this evaluator.", std::to_string(program.program_id)});
                    valid_property = false;
                }
            }
        }
        if (!valid_property || property_universe < 0) continue;
        if (parameter == SemanticParameter::Pan) pan_component_id_by_fixture_[property.fixture_id] = property.component_id;
        if (parameter == SemanticParameter::Tilt) tilt_component_id_by_fixture_[property.fixture_id] = property.component_id;
        if (parameter == SemanticParameter::Zoom) render_params_by_fixture_[property.fixture_id].has_zoom = true;
        const uint32_t installed_mask = visual_mask_for_parameter(parameter);
        installed_visual_mask_by_fixture_[property.fixture_id] |= installed_mask;
        capabilities.has_transform = capabilities.has_transform || parameter == SemanticParameter::Pan || parameter == SemanticParameter::Tilt;
        capabilities.has_intensity = capabilities.has_intensity || parameter == SemanticParameter::Dimmer;
        capabilities.has_optics = capabilities.has_optics || parameter == SemanticParameter::Zoom;
        UniverseState &universe = universes_[property_universe];
        const int property_index = static_cast<int>(universe.properties.size());
        universe.properties.push_back({property, parameter});
        for (const CompiledPropertyContributor &contributor : property.contributors) {
            const CompiledDmxSourceProgram &program = source_programs_by_id_[contributor.source_program_id].program;
            for (const CompiledDmxByteSource &source : program.sources) {
                universe.interest_offsets.push_back(source.address);
                universe.property_indices_by_offset[source.address].push_back(property_index);
            }
        }
        ++installed_properties;
    }
    for (const CompiledColorTargetProgram &target : scene.color_targets) {
        if (target.fixture_id <= 0 || target.beam_render_target_id <= 0 || target.inputs.empty()) continue;
        int target_universe = -1;
        bool valid_target = true;
        ColorTargetRuntime runtime_target;
        runtime_target.target = target;
        runtime_target.inputs.reserve(target.inputs.size());
        for (const CompiledColorInputBinding &input : target.inputs) {
            auto program_it = source_programs_by_id_.find(input.source_program_id);
            if (program_it == source_programs_by_id_.end()) { valid_target = false; continue; }
            const CompiledDmxSourceProgram &program = program_it->second.program;
            if (program.sources.empty()) { valid_target = false; continue; }
            for (const CompiledDmxByteSource &source : program.sources) {
                if (target_universe < 0) target_universe = source.universe_id;
                if (source.universe_id != target_universe) valid_target = false;
            }
            runtime_target.inputs.push_back({input, static_cast<float>(input.default_value), false});
        }
        if (!valid_target || target_universe < 0 || runtime_target.inputs.empty()) continue;
        UniverseState &universe = universes_[target_universe];
        const int color_target_index = static_cast<int>(universe.color_targets.size());
        universe.color_targets.push_back(runtime_target);
        for (const ColorInputRuntime &input : runtime_target.inputs) {
            const CompiledDmxSourceProgram &program = source_programs_by_id_[input.binding.source_program_id].program;
            for (const CompiledDmxByteSource &source : program.sources) {
                universe.interest_offsets.push_back(source.address);
                universe.color_target_indices_by_offset[source.address].push_back(color_target_index);
            }
        }
        capabilities.has_color = true;
        installed_visual_mask_by_fixture_[target.fixture_id] |= VisualChangeColor;
    }

    int installed_wheel_bindings = 0;
    for (const CompiledWheelTargetBinding &binding : scene.wheel_bindings) {
        auto program_it = source_programs_by_id_.find(binding.source_program_id);
        auto palette_it = wheel_palettes_by_id_.find(binding.wheel_renderer_id);
        if (binding.binding_id <= 0 || binding.fixture_id <= 0 || binding.beam_render_target_id <= 0 || program_it == source_programs_by_id_.end() || palette_it == wheel_palettes_by_id_.end() || (binding.mode == CompiledWheelMode::Select && binding.channel_sets.empty())) {
            diagnostics_.push_back({"PVZ-RUNTIME-INVALID-WHEEL-BINDING", "warning", "Compiled wheel binding is missing a source, palette, target, or required ChannelSets.", std::to_string(binding.binding_id)});
            continue;
        }
        UniverseState &universe = universes_[program_it->second.program.sources.front().universe_id];
        const int wheel_index = static_cast<int>(universe.wheel_bindings.size());
        universe.wheel_bindings.push_back({binding});
        universe.wheel_binding_indices_by_target[binding.beam_render_target_id].push_back(wheel_index);
        for (const CompiledDmxByteSource &source : program_it->second.program.sources) {
            universe.interest_offsets.push_back(source.address);
            universe.wheel_binding_indices_by_offset[source.address].push_back(wheel_index);
        }
        wheel_state_by_binding_[binding.binding_id] = {};
        capabilities.has_wheel_selection = true;
        installed_visual_mask_by_fixture_[binding.fixture_id] |= VisualChangeColor;
        ++installed_wheel_bindings;
    }
    if (installed_properties == 0 && scene.color_targets.empty() && installed_wheel_bindings == 0) {
        diagnostics_.push_back({"PVZ-RUNTIME-NO-PROPERTIES", "error", "Compiled runtime scene installed zero supported native properties.", "CompiledRuntimeScene"});
    }
    for (auto &[_, universe] : universes_) {
        std::sort(universe.interest_offsets.begin(), universe.interest_offsets.end());
        universe.interest_offsets.erase(std::unique(universe.interest_offsets.begin(), universe.interest_offsets.end()), universe.interest_offsets.end());
    }
    schema_ = make_visual_frame_schema(++next_schema_generation_, capabilities);
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
    frame.schema_generation = schema_.schema_generation;
    struct PendingRow { int fixture_id = 0; int32_t render_target_id = 0; uint32_t changed_visual_mask = 0; ComponentState state; CookedEmitterColor color; int32_t wheel_id = 0; int32_t slot_a = 0; int32_t slot_b = 0; float normalized_phase = 0.0f; float split_fraction = 0.0f; float boundary_angle_degrees = 0.0f; CompiledWheelMode wheel_mode = CompiledWheelMode::Select; int32_t revision = 0; bool wheel_row = false; };
    std::vector<PendingRow> rows;

    for (auto &[_, universe] : universes_) {
        if (!universe.has_pending_frame) continue;
        universe.has_pending_frame = false;
        ++stats_.universes_considered;
        std::vector<int> changed_offsets;
        for (int offset : universe.interest_offsets) {
            const uint8_t value = offset >= 0 && offset < static_cast<int>(universe.latest_frame.size()) ? universe.latest_frame[static_cast<size_t>(offset)] : 0;
            if (!universe.has_last_relevant_values || universe.last_relevant_values[static_cast<size_t>(offset)] != value) {
                changed_offsets.push_back(offset);
                universe.last_relevant_values[static_cast<size_t>(offset)] = value;
            }
        }
        universe.has_last_relevant_values = true;
        if (changed_offsets.empty()) continue;

        std::set<int> property_indices;
        std::set<int> color_target_indices;
        std::set<int> wheel_binding_indices;
        for (int offset : changed_offsets) {
            auto property_it = universe.property_indices_by_offset.find(offset);
            if (property_it != universe.property_indices_by_offset.end()) property_indices.insert(property_it->second.begin(), property_it->second.end());
            auto color_it = universe.color_target_indices_by_offset.find(offset);
            if (color_it != universe.color_target_indices_by_offset.end()) color_target_indices.insert(color_it->second.begin(), color_it->second.end());
            auto wheel_it = universe.wheel_binding_indices_by_offset.find(offset);
            if (wheel_it != universe.wheel_binding_indices_by_offset.end()) wheel_binding_indices.insert(wheel_it->second.begin(), wheel_it->second.end());
        }

        std::unordered_map<int, ComponentState> pending_transform_by_fixture;
        for (int property_index : property_indices) {
            if (property_index < 0 || property_index >= static_cast<int>(universe.properties.size())) continue;
            const CompiledPropertyProgram &program = universe.properties[static_cast<size_t>(property_index)];
            const EvaluationResult evaluated = evaluate_property_value(universe.latest_frame, program.property);
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

        for (int target_index : color_target_indices) {
            if (target_index < 0 || target_index >= static_cast<int>(universe.color_targets.size())) continue;
            ColorTargetRuntime &target = universe.color_targets[static_cast<size_t>(target_index)];
            bool input_changed = false;
            for (ColorInputRuntime &input : target.inputs) {
                auto program_it = source_programs_by_id_.find(input.binding.source_program_id);
                if (program_it == source_programs_by_id_.end()) continue;
                if (input.initialized && !program_uses_changed_offset(program_it->second.program, changed_offsets)) continue;
                const EvaluationResult evaluated = evaluate_source_program(universe.latest_frame, program_it->second, &diagnostics_);
                if (!evaluated.valid) continue;
                const float next_value = color_value_from_evaluation(input.binding.semantic, evaluated);
                input_changed = input_changed || !input.initialized || !nearly_equal(input.value, next_value, kDefaultEpsilon);
                input.value = next_value;
                input.initialized = true;
                ++stats_.color_inputs_evaluated;
            }
            if (!input_changed) continue;
            ++stats_.color_targets_dirty;
            CookedEmitterColor cooked = cook_emitter_color(target);
            base_color_state_by_target_[target.target.beam_render_target_id] = cooked;
            base_color_state_by_target_[target.target.beam_render_target_id].initialized = true;
            ++stats_.color_targets_cooked;
            auto dependent_wheels = universe.wheel_binding_indices_by_target.find(target.target.beam_render_target_id);
            if (dependent_wheels != universe.wheel_binding_indices_by_target.end()) wheel_binding_indices.insert(dependent_wheels->second.begin(), dependent_wheels->second.end());
        }


        for (int wheel_index : wheel_binding_indices) {
            if (wheel_index < 0 || wheel_index >= static_cast<int>(universe.wheel_bindings.size())) continue;
            const WheelBindingRuntime &wheel = universe.wheel_bindings[static_cast<size_t>(wheel_index)];
            auto program_it = source_programs_by_id_.find(wheel.binding.source_program_id);
            auto palette_it = wheel_palettes_by_id_.find(wheel.binding.wheel_renderer_id);
            if (program_it == source_programs_by_id_.end() || palette_it == wheel_palettes_by_id_.end()) continue;
            const EvaluationResult evaluated = evaluate_source_program(universe.latest_frame, program_it->second, &diagnostics_);
            if (!evaluated.valid) continue;
            ++stats_.wheel_inputs_evaluated;
            const CompiledWheelPaletteSlot *slot_a = nullptr;
            const CompiledWheelPaletteSlot *slot_b = nullptr;
            float normalized_phase = 0.0f;
            float split_fraction = 0.0f;
            float boundary_angle_degrees = 0.0f;
            CookedEmitterColor cooked;
            if (wheel.binding.mode == CompiledWheelMode::Index) {
                const int32_t slot_count = static_cast<int32_t>(palette_it->second.slots.size());
                if (slot_count <= 0) continue;
                auto normalize_degrees = [](float degrees) { float wrapped = std::fmod(degrees, 360.0f); return wrapped < 0.0f ? wrapped + 360.0f : wrapped; };
                boundary_angle_degrees = normalize_degrees(evaluated.physical_value + wheel.binding.placement_offset_degrees);
                normalized_phase = boundary_angle_degrees / 360.0f;
                const float coordinate = normalized_phase * static_cast<float>(slot_count);
                const int32_t base_index = static_cast<int32_t>(std::floor(coordinate)) % slot_count;
                split_fraction = coordinate - std::floor(coordinate);
                slot_a = &palette_it->second.slots[static_cast<size_t>(base_index)];
                slot_b = &palette_it->second.slots[static_cast<size_t>((base_index + 1) % slot_count)];
                cooked = aggregate_indexed_wheel_layer(*slot_a, *slot_b, split_fraction);
            } else if (wheel.binding.mode == CompiledWheelMode::Select) {
                const CompiledWheelChannelSet *active_set = nullptr;
                for (const CompiledWheelChannelSet &set : wheel.binding.channel_sets) {
                    if (evaluated.raw_value >= set.dmx_from && evaluated.raw_value <= set.dmx_to) { active_set = &set; break; }
                }
                if (active_set == nullptr) continue;
                for (const CompiledWheelPaletteSlot &candidate : palette_it->second.slots) {
                    if (candidate.slot_index == active_set->wheel_slot_index) { slot_a = &candidate; slot_b = &candidate; break; }
                }
                if (slot_a == nullptr) continue;
                cooked = cook_wheel_slot_layer(*slot_a);
            } else {
                continue;
            }
            if (slot_a == nullptr || slot_b == nullptr) continue;
            WheelTargetState &previous = wheel_state_by_binding_[wheel.binding.binding_id];
            const bool changed = !previous.initialized || previous.mode != wheel.binding.mode || previous.slot_a != slot_a->slot_index || previous.slot_b != slot_b->slot_index || !nearly_equal(previous.normalized_phase, normalized_phase, kDefaultEpsilon) || !nearly_equal(previous.split_fraction, split_fraction, kDefaultEpsilon) || !nearly_equal(previous.srgb_red, cooked.srgb_red, kDefaultEpsilon) || !nearly_equal(previous.srgb_green, cooked.srgb_green, kDefaultEpsilon) || !nearly_equal(previous.srgb_blue, cooked.srgb_blue, kDefaultEpsilon) || !nearly_equal(previous.gain, cooked.gain, kDefaultEpsilon);
            if (!changed) { ++stats_.wheel_states_skipped; continue; }
            previous.initialized = true;
            previous.mode = wheel.binding.mode;
            previous.slot_a = slot_a->slot_index;
            previous.slot_b = slot_b->slot_index;
            previous.normalized_phase = normalized_phase;
            previous.split_fraction = split_fraction;
            previous.boundary_angle_degrees = boundary_angle_degrees;
            previous.beam_target_id = wheel.binding.beam_render_target_id;
            previous.srgb_red = cooked.srgb_red;
            previous.srgb_green = cooked.srgb_green;
            previous.srgb_blue = cooked.srgb_blue;
            previous.gain = cooked.gain;
            previous.linear_red = cooked.linear_red;
            previous.linear_green = cooked.linear_green;
            previous.linear_blue = cooked.linear_blue;
            previous.revision += 1;
            ++stats_.wheel_targets_dirty;
            ++stats_.wheel_selection_rows;
            ++stats_.fixtures_dirty;
            rows.push_back({wheel.binding.fixture_id, wheel.binding.beam_render_target_id, VisualChangeColor, {}, cooked, wheel.binding.wheel_renderer_id, slot_a->slot_index, slot_b->slot_index, normalized_phase, split_fraction, boundary_angle_degrees, wheel.binding.mode, previous.revision, true});
        }

        std::set<int32_t> dirty_color_targets;
        for (int target_index : color_target_indices) {
            if (target_index >= 0 && target_index < static_cast<int>(universe.color_targets.size())) dirty_color_targets.insert(universe.color_targets[static_cast<size_t>(target_index)].target.beam_render_target_id);
        }
        for (int wheel_index : wheel_binding_indices) {
            if (wheel_index >= 0 && wheel_index < static_cast<int>(universe.wheel_bindings.size())) dirty_color_targets.insert(universe.wheel_bindings[static_cast<size_t>(wheel_index)].binding.beam_render_target_id);
        }
        for (int32_t beam_target_id : dirty_color_targets) {
            CookedEmitterColor composed = compose_ordered_target_color(beam_target_id);
            CookedEmitterColor &previous = color_state_by_target_[beam_target_id];
            const bool changed = !previous.initialized || !nearly_equal(previous.srgb_red, composed.srgb_red, kDefaultEpsilon) || !nearly_equal(previous.srgb_green, composed.srgb_green, kDefaultEpsilon) || !nearly_equal(previous.srgb_blue, composed.srgb_blue, kDefaultEpsilon) || !nearly_equal(previous.gain, composed.gain, kDefaultEpsilon) || previous.valid != composed.valid;
            previous = composed;
            previous.initialized = true;
            if (!changed) { ++stats_.fixtures_skipped; continue; }
            int fixture_id = 0;
            for (const ColorTargetRuntime &target : universe.color_targets) if (target.target.beam_render_target_id == beam_target_id) { fixture_id = target.target.fixture_id; break; }
            if (fixture_id == 0) for (const WheelBindingRuntime &wheel : universe.wheel_bindings) if (wheel.binding.beam_render_target_id == beam_target_id) { fixture_id = wheel.binding.fixture_id; break; }
            add_visual_mask_stats(VisualChangeColor);
            ++stats_.fixtures_dirty;
            ++stats_.color_rows;
            rows.push_back({fixture_id, beam_target_id, VisualChangeColor, {}, composed});
        }
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
    frame.stats = stats_;
    return frame;
}

// Returns the immutable schema currently used by emitted sectioned frames.
const VisualFrameSchema &PeravizVisualRuntimeCore::schema() const { return schema_; }

// Returns cumulative runtime counters for debug UI and benchmarks.
const VisualFrameStats &PeravizVisualRuntimeCore::stats() const { return stats_; }

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

// Reads a compiled DMX program by assembling preordered source bytes into a raw integer value.
uint32_t PeravizVisualRuntimeCore::read_raw_value(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics) {
    if (program.program.sources.empty() || program.program.sources.size() > 4) {
        if (diagnostics != nullptr) diagnostics->push_back({"PVZ-RUNTIME-UNSUPPORTED-BYTE-COUNT", "warning", "Compiled DMX source byte count must be between one and four.", std::to_string(program.program.program_id)});
        return 0U;
    }
    uint32_t raw_value = 0;
    for (const CompiledDmxByteSource &source : program.program.sources) {
        const bool valid = source.address >= 0 && source.address < static_cast<int32_t>(frame.size());
        if (!valid && diagnostics != nullptr) diagnostics->push_back({"PVZ-RUNTIME-INVALID-BYTE", "warning", "Compiled DMX byte address is outside the submitted frame.", std::to_string(program.program.program_id)});
        const uint8_t value = valid ? frame[static_cast<size_t>(source.address)] : 0;
        raw_value = (raw_value << 8U) | value;
    }
    return raw_value;
}

// Evaluates one source program into raw, local normalized, and physical representations.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_source_program(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics) {
    const uint32_t raw_value = read_raw_value(frame, program, diagnostics);
    const double dmx_span = program.program.dmx_to > program.program.dmx_from ? static_cast<double>(program.program.dmx_to - program.program.dmx_from) : static_cast<double>(program.max_value);
    const double full_range_normalized = static_cast<double>(raw_value) * program.inverse_max_value;
    const double local = dmx_span > 0.0 ? std::clamp((static_cast<double>(raw_value) - static_cast<double>(program.program.dmx_from)) / dmx_span, 0.0, 1.0) : full_range_normalized;
    const double physical = program.program.physical_from + ((program.program.physical_to - program.program.physical_from) * local);
    return {raw_value, static_cast<float>(local), static_cast<float>(physical), program.program.program_id, true};
}

// Resolves all contributors for one property into a single deterministic value.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_property_value(const std::vector<uint8_t> &frame, const CompiledComponentProperty &property) {
    double weighted_normalized_sum = 0.0;
    double weighted_physical_sum = 0.0;
    double total_weight = 0.0;
    const InstalledSourceProgram *active_program = nullptr;
    bool has_range_selector = false;
    bool has_reference_range = false;
    uint32_t reference_from = 0;
    uint32_t reference_to = 0;
    for (const CompiledPropertyContributor &contributor : property.contributors) {
        auto program_it = source_programs_by_id_.find(contributor.source_program_id);
        if (program_it == source_programs_by_id_.end()) continue;
        const CompiledDmxSourceProgram &program = program_it->second.program;
        if (!has_reference_range) { reference_from = program.dmx_from; reference_to = program.dmx_to; has_reference_range = true; }
        else if (program.dmx_from != reference_from || program.dmx_to != reference_to) has_range_selector = true;
        const uint32_t raw_value = read_raw_value(frame, program_it->second, &diagnostics_);
        if (raw_value >= program.dmx_from && raw_value <= program.dmx_to && active_program == nullptr) active_program = &program_it->second;
    }
    if (property.contributors.size() > 1 && has_range_selector) {
        if (active_program == nullptr) return {};
        return evaluate_source_program(frame, *active_program, &diagnostics_);
    }
    EvaluationResult result;
    for (const CompiledPropertyContributor &contributor : property.contributors) {
        auto program_it = source_programs_by_id_.find(contributor.source_program_id);
        if (program_it == source_programs_by_id_.end()) continue;
        const EvaluationResult program_value = evaluate_source_program(frame, program_it->second, &diagnostics_);
        if (!program_value.valid) continue;
        if (!result.valid) { result.raw_value = program_value.raw_value; result.active_program_id = program_value.active_program_id; result.valid = true; }
        weighted_normalized_sum += static_cast<double>(program_value.normalized_value) * contributor.weight;
        weighted_physical_sum += static_cast<double>(program_value.physical_value) * contributor.weight;
        total_weight += contributor.weight;
    }
    if (total_weight == 0.0 || !result.valid) return {};
    result.normalized_value = static_cast<float>(weighted_normalized_sum / total_weight);
    result.physical_value = static_cast<float>(weighted_physical_sum / total_weight);
    return result;
}

// Evaluates one installed source program by stable program ID.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_source_program_by_id(const std::vector<uint8_t> &frame, int32_t source_program_id) {
    auto program_it = source_programs_by_id_.find(source_program_id);
    if (program_it == source_programs_by_id_.end()) return {};
    return evaluate_source_program(frame, program_it->second, &diagnostics_);
}

// Maps a semantic parameter to the render domains it can dirty.
uint32_t PeravizVisualRuntimeCore::visual_mask_for_parameter(SemanticParameter parameter) {
    switch (parameter) {
        case SemanticParameter::Dimmer: return VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology;
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

// Checks whether a source program depends on one of the current dirty DMX offsets.
bool PeravizVisualRuntimeCore::program_uses_changed_offset(const CompiledDmxSourceProgram &program, const std::vector<int> &changed_offsets) {
    for (const CompiledDmxByteSource &source : program.sources) {
        if (std::find(changed_offsets.begin(), changed_offsets.end(), source.address) != changed_offsets.end()) return true;
    }
    return false;
}

// Selects normalized or physical color input values for the supported fallback color slice.
float PeravizVisualRuntimeCore::color_value_from_evaluation(CompiledSemantic semantic, const EvaluationResult &evaluated) {
    const bool unit_physical = semantic == CompiledSemantic::ColorAddRed || semantic == CompiledSemantic::ColorAddGreen || semantic == CompiledSemantic::ColorAddBlue || semantic == CompiledSemantic::ColorAddWhite || semantic == CompiledSemantic::ColorAddAmber || semantic == CompiledSemantic::ColorAddLime || semantic == CompiledSemantic::CieX || semantic == CompiledSemantic::CieY || semantic == CompiledSemantic::CieBrightness || semantic == CompiledSemantic::Tint;
    if (unit_physical && evaluated.physical_value >= -1.0f && evaluated.physical_value <= 1.0f) return evaluated.physical_value;
    if ((semantic == CompiledSemantic::Cto || semantic == CompiledSemantic::Ctb || semantic == CompiledSemantic::Ctc) && evaluated.physical_value > 0.0f) return evaluated.physical_value;
    return std::clamp(evaluated.normalized_value, 0.0f, 1.0f);
}

// Composes one complete color target once into renderer-ready sRGB plus linear gain.
PeravizVisualRuntimeCore::CookedEmitterColor PeravizVisualRuntimeCore::cook_emitter_color(const ColorTargetRuntime &target) const {
    runtime::LinearRgb add;
    float sub_c = 0.0f, sub_m = 0.0f, sub_y = 0.0f;
    std::vector<std::pair<const CompiledFilterResource *, float>> physical_filters;
    bool has_additive = target.target.additive_source;
    bool has_cie_x = false, has_cie_y = false, has_cie_brightness = false;
    float cie_x = 0.0f, cie_y = 0.0f, cie_brightness = 0.0f;
    float cct_kelvin = 0.0f;
    float tint_value = 0.0f;
    bool has_tint = false;
    for (const ColorInputRuntime &input : target.inputs) {
        const float v = std::clamp(input.value, 0.0f, 1.0f);
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
            case CompiledSemantic::CieX: cie_x = input.value; has_cie_x = true; break;
            case CompiledSemantic::CieY: cie_y = input.value; has_cie_y = true; break;
            case CompiledSemantic::CieBrightness: cie_brightness = std::max(0.0f, input.value); has_cie_brightness = true; break;
            case CompiledSemantic::Cto:
            case CompiledSemantic::Ctb:
            case CompiledSemantic::Ctc: cct_kelvin = input.value; break;
            case CompiledSemantic::Tint: tint_value = input.value; has_tint = true; break;
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
PeravizVisualRuntimeCore::CookedEmitterColor PeravizVisualRuntimeCore::compose_ordered_target_color(int32_t beam_target_id) const {
    CookedEmitterColor base;
    auto base_it = base_color_state_by_target_.find(beam_target_id);
    if (base_it != base_color_state_by_target_.end() && base_it->second.initialized) base = base_it->second;
    runtime::LinearRgb absolute = {base.linear_red * base.gain, base.linear_green * base.gain, base.linear_blue * base.gain};
    std::vector<std::pair<int32_t, const WheelTargetState *>> layers;
    for (const auto &entry : wheel_state_by_binding_) {
        if (entry.second.initialized && entry.second.beam_target_id == beam_target_id) layers.push_back({entry.first, &entry.second});
    }
    std::sort(layers.begin(), layers.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
    for (const auto &entry : layers) {
        const WheelTargetState &layer = *entry.second;
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
        const bool previous_visible = previous.dimmer > kDefaultEpsilon;
        const bool current_visible = next_state.dimmer > kDefaultEpsilon;
        if ((installed_mask & visual_mask_for_parameter(SemanticParameter::Dimmer)) != 0U && previous_visible != current_visible) result.changed_visual_mask |= VisualChangeBeamTopology;
    }
    result.changed_visual_mask &= installed_mask;
    result.changed = result.changed_visual_mask != VisualChangeNone;
    previous = next_state;
    previous.initialized = true;
    return result;
}

} // namespace peraviz::runtime
