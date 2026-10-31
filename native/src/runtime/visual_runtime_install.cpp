#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>
#include <set>

namespace peraviz::runtime {
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
    for (const CompiledGoboAsset &asset : scene.gobo_assets) {
        const int64_t key = (static_cast<int64_t>(asset.wheel_id) << 32) | static_cast<uint32_t>(asset.slot_index);
        gobo_asset_by_wheel_slot_[key] = asset.media_valid && !asset.open_slot ? asset.gobo_asset_id : 0;
        if (!asset.open_slot && !asset.media_valid) ++stats_.missing_media_warnings;
    }
    for (const CompiledDmxSourceProgram &program : scene.source_programs) {
        if (program.program_id <= 0 || source_programs_by_id_.find(program.program_id) != source_programs_by_id_.end()) {
            diagnostics_.push_back({"PVZ-RUNTIME-DUPLICATE-PROGRAM", "error", "Compiled source program ID is invalid or duplicated.", std::to_string(program.program_id)});
            continue;
        }
        InstalledSourceProgram installed;
        installed.program = program;
        std::sort(installed.program.sources.begin(), installed.program.sources.end(), [](const CompiledDmxByteSource &a, const CompiledDmxByteSource &b) { return a.byte_order < b.byte_order; });
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
        universe.properties.push_back({property, parameter});
        for (const CompiledPropertyContributor &contributor : property.contributors) {
            const CompiledDmxSourceProgram &program = source_programs_by_id_[contributor.source_program_id].program;
            for (const CompiledDmxByteSource &source : program.sources) {
                universe.interest_offsets.push_back(source.address);
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
        universe.color_targets.push_back(runtime_target);
        universe.color_fixture_by_target.emplace(target.beam_render_target_id,target.fixture_id);
        for (const ColorInputRuntime &input : runtime_target.inputs) {
            const CompiledDmxSourceProgram &program = source_programs_by_id_[input.binding.source_program_id].program;
            for (const CompiledDmxByteSource &source : program.sources) {
                universe.interest_offsets.push_back(source.address);
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
        universe.color_fixture_by_target.emplace(binding.beam_render_target_id,binding.fixture_id);
        const int64_t physical_key = wheel_physical_key(binding.beam_render_target_id, binding.wheel_renderer_id);
        universe.wheel_binding_indices_by_target[binding.beam_render_target_id].push_back(wheel_index);
        universe.wheel_binding_indices_by_physical_key[physical_key].push_back(wheel_index);
        universe.wheel_physical_keys_by_target[binding.beam_render_target_id].push_back(physical_key);
        for (const CompiledDmxByteSource &source : program_it->second.program.sources) {
            universe.interest_offsets.push_back(source.address);
        }
        wheel_state_by_physical_key_[physical_key].beam_target_id = binding.beam_render_target_id;
        wheel_state_by_physical_key_[physical_key].wheel_renderer_id = binding.wheel_renderer_id;
        capabilities.has_wheel_selection = true;
        installed_visual_mask_by_fixture_[binding.fixture_id] |= VisualChangeColor;
        ++installed_wheel_bindings;
    }
    for (const CompiledGoboSelectionBinding &binding : scene.gobo_bindings) {
        auto program_it = source_programs_by_id_.find(binding.source_program_id);
        if (binding.binding_id <= 0 || binding.fixture_id <= 0 || binding.beam_render_target_id <= 0 || binding.wheel_id <= 0 || binding.wheel_instance_index <= 0 || program_it == source_programs_by_id_.end() || binding.channel_sets.empty() || program_it->second.program.sources.empty()) {
            diagnostics_.push_back({"PVZ-RUNTIME-INVALID-GOBO-BINDING", "warning", "Compiled seated gobo binding is incomplete or has a non-positive wheel instance.", std::to_string(binding.binding_id)});
            continue;
        }
        const int universe_id = program_it->second.program.sources.front().universe_id;
        std::vector<int> dependency_offsets;
        std::vector<int32_t> dependency_program_ids;
        int32_t program_id = binding.source_program_id;
        std::set<int32_t> visited;
        bool valid_dependencies = true;
        while (program_id > 0 && visited.insert(program_id).second) {
            auto dependency_it = source_programs_by_id_.find(program_id);
            if (dependency_it == source_programs_by_id_.end()) { valid_dependencies = false; break; }
            for (const CompiledDmxByteSource &source : dependency_it->second.program.sources) {
                if (source.universe_id != universe_id) { valid_dependencies = false; break; }
                dependency_offsets.push_back(source.address);
            }
            if (!valid_dependencies) break;
            dependency_program_ids.push_back(program_id);
            const auto &activation = dependency_it->second.program.activation;
            program_id = activation.target_kind == gdtf_runtime::ModeMasterTargetKind::None ? 0 : activation.master_program_id;
        }
        if (!valid_dependencies) {
            diagnostics_.push_back({"PVZ-RUNTIME-CROSS-UNIVERSE-GOBO-SELECTION", "warning", "Gobo selection activation dependencies are missing or span universes and cannot be evaluated.", std::to_string(binding.binding_id)});
            continue;
        }
        UniverseState &universe = universes_[universe_id];
        const int binding_index = static_cast<int>(universe.gobo_bindings.size());
        GoboBindingRuntime runtime; runtime.binding=binding; runtime.dependency_program_ids=std::move(dependency_program_ids);
        universe.gobo_bindings.push_back(std::move(runtime));
        const int64_t layer_key = (static_cast<int64_t>(binding.beam_render_target_id) << 32) | static_cast<uint32_t>(binding.wheel_instance_index);
        universe.gobo_binding_indices_by_layer[layer_key].push_back(binding_index);
        for (int offset : dependency_offsets) {
            universe.interest_offsets.push_back(offset);
        }
        capabilities.has_gobo_selection = true;
        installed_visual_mask_by_fixture_[binding.fixture_id] |= VisualChangeGobo;
    }
    for (const CompiledGoboMotionBinding &binding : scene.gobo_motion_bindings) {
        if (binding.semantic_kind != gdtf_runtime::GoboSemanticKind::Pos && binding.semantic_kind != gdtf_runtime::GoboSemanticKind::PosRotate) continue;
        auto source_it = source_programs_by_id_.find(binding.source_program_id);
        if (binding.binding_id <= 0 || binding.beam_render_target_id <= 0 || !binding.scalar_evaluable || source_it == source_programs_by_id_.end() || source_it->second.program.sources.empty()) continue;
        const int universe_id = source_it->second.program.sources.front().universe_id;
        std::vector<int> dependency_offsets;
        std::vector<int32_t> dependency_program_ids;
        int32_t program_id = binding.source_program_id;
        std::set<int32_t> visited;
        bool valid_dependencies = true;
        while (program_id > 0 && visited.insert(program_id).second) {
            auto program_it = source_programs_by_id_.find(program_id);
            if (program_it == source_programs_by_id_.end()) { valid_dependencies = false; break; }
            for (const CompiledDmxByteSource &source : program_it->second.program.sources) {
                if (source.universe_id != universe_id) { valid_dependencies = false; break; }
                dependency_offsets.push_back(source.address);
            }
            if (!valid_dependencies) break;
            dependency_program_ids.push_back(program_id);
            const auto &activation = program_it->second.program.activation;
            program_id = activation.target_kind == gdtf_runtime::ModeMasterTargetKind::None ? 0 : activation.master_program_id;
        }
        if (!valid_dependencies) { diagnostics_.push_back({"PVZ-RUNTIME-CROSS-UNIVERSE-GOBO-MOTION", "warning", "Gobo Pos activation dependencies are missing or span universes and cannot be evaluated.", std::to_string(binding.binding_id)}); continue; }
        UniverseState &universe = universes_[universe_id];
        const int index = static_cast<int>(universe.gobo_motion_bindings.size());
        GoboMotionRuntime runtime; runtime.binding=binding; runtime.dependency_program_ids=std::move(dependency_program_ids);
        universe.gobo_motion_bindings.push_back(std::move(runtime));
        const int64_t layer_key = (static_cast<int64_t>(binding.beam_render_target_id) << 32) | static_cast<uint32_t>(binding.wheel_instance_index);
        universe.gobo_motion_indices_by_layer[layer_key].push_back(index);
        for (int offset : dependency_offsets) {
            universe.interest_offsets.push_back(offset);
        }
        capabilities.has_gobo_rotation = true;
        installed_visual_mask_by_fixture_[binding.fixture_id] |= VisualChangeGoboRotation;
    }
    install_shutters(scene,capabilities);
    if (installed_properties == 0 && scene.color_targets.empty() && installed_wheel_bindings == 0 && scene.gobo_bindings.empty() && scene.gobo_motion_bindings.empty() && scene.shutter_bindings.empty()) {
        diagnostics_.push_back({"PVZ-RUNTIME-NO-PROPERTIES", "error", "Compiled runtime scene installed zero supported native properties.", "CompiledRuntimeScene"});
    }
    for (auto &[_, universe] : universes_) {
        universe.dirty_properties.reserve(universe.properties.size());
        universe.dirty_colors.reserve(universe.color_targets.size());
        universe.dirty_wheels.install(universe.wheel_bindings.size());
        universe.changed_offsets.reserve(universe.interest_offsets.size());
        std::sort(universe.interest_offsets.begin(), universe.interest_offsets.end());
        universe.interest_offsets.erase(std::unique(universe.interest_offsets.begin(), universe.interest_offsets.end()), universe.interest_offsets.end());
        for (auto &[__, indices] : universe.wheel_binding_indices_by_physical_key) {
            std::sort(indices.begin(), indices.end(), [&universe, this](int lhs, int rhs) {
                const CompiledWheelTargetBinding &a = universe.wheel_bindings[static_cast<size_t>(lhs)].binding;
                const CompiledWheelTargetBinding &b = universe.wheel_bindings[static_cast<size_t>(rhs)].binding;
                const auto pa = source_programs_by_id_.find(a.source_program_id);
                const auto pb = source_programs_by_id_.find(b.source_program_id);
                const uint32_t a_from = pa != source_programs_by_id_.end() ? pa->second.program.dmx_from : 0U;
                const uint32_t b_from = pb != source_programs_by_id_.end() ? pb->second.program.dmx_from : 0U;
                if (a_from != b_from) return a_from < b_from;
                const uint32_t a_to = pa != source_programs_by_id_.end() ? pa->second.program.dmx_to : 0U;
                const uint32_t b_to = pb != source_programs_by_id_.end() ? pb->second.program.dmx_to : 0U;
                if (a_to != b_to) return a_to < b_to;
                return a.binding_id < b.binding_id;
            });
            for (size_t index = 1; index < indices.size(); ++index) {
                const CompiledWheelTargetBinding &previous_binding = universe.wheel_bindings[static_cast<size_t>(indices[index - 1])].binding;
                const CompiledWheelTargetBinding &next_binding = universe.wheel_bindings[static_cast<size_t>(indices[index])].binding;
                const auto previous_program = source_programs_by_id_.find(previous_binding.source_program_id);
                const auto next_program = source_programs_by_id_.find(next_binding.source_program_id);
                if (previous_program != source_programs_by_id_.end() && next_program != source_programs_by_id_.end() && next_program->second.program.dmx_from <= previous_program->second.program.dmx_to) {
                    diagnostics_.push_back({"PVZ-RUNTIME-WHEEL-RANGE-OVERLAP", "warning", "Wheel control ChannelFunction ranges overlap for one physical wheel; runtime will use deterministic binding order.", std::to_string(previous_binding.beam_render_target_id) + ":" + std::to_string(previous_binding.wheel_renderer_id)});
                }
            }
        }
        for (auto &[__, keys] : universe.wheel_physical_keys_by_target) {
            std::sort(keys.begin(), keys.end());
            keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
        }
    }
    install_source_mappings(scene);
    compile_evaluation_plans();
    schema_ = make_visual_frame_schema(++next_schema_generation_, capabilities);
}

} // namespace peraviz::runtime
