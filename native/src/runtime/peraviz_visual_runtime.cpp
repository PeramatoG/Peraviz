#include "runtime/peraviz_visual_runtime.h"

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

} // namespace

// Clears bindings, cached frames, fixture state, and runtime counters.
void PeravizVisualRuntimeCore::clear() {
    universes_.clear();
    render_params_by_fixture_.clear();
    transform_state_by_fixture_.clear();
    property_state_by_property_.clear();
    pan_component_id_by_fixture_.clear();
    tilt_component_id_by_fixture_.clear();
    installed_visual_mask_by_fixture_.clear();
    source_programs_by_id_.clear();
    stats_ = VisualFrameStats();
    schema_ = make_visual_frame_schema(++next_schema_generation_, VisualFrameSchemaCapabilities());
}

// Installs parser-owned compiled scene programs as the only runtime setup authority.
void PeravizVisualRuntimeCore::install_compiled_scene(const CompiledRuntimeScene &scene) {
    universes_.clear();
    render_params_by_fixture_.clear();
    transform_state_by_fixture_.clear();
    property_state_by_property_.clear();
    pan_component_id_by_fixture_.clear();
    tilt_component_id_by_fixture_.clear();
    installed_visual_mask_by_fixture_.clear();
    source_programs_by_id_.clear();
    diagnostics_ = scene.diagnostics;
    VisualFrameSchemaCapabilities capabilities;
    if (scene.fixtures.empty()) {
        diagnostics_.push_back({"PVZ-RUNTIME-EMPTY-SCENE", "error", "Compiled runtime scene contains no fixture instances.", "CompiledRuntimeScene"});
    }
    for (const CompiledDmxSourceProgram &program : scene.source_programs) {
        if (program.program_id <= 0 || source_programs_by_id_.find(program.program_id) != source_programs_by_id_.end()) {
            diagnostics_.push_back({"PVZ-RUNTIME-DUPLICATE-PROGRAM", "error", "Compiled source program ID is invalid or duplicated.", std::to_string(program.program_id)});
            continue;
        }
        source_programs_by_id_[program.program_id] = program;
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
            const CompiledDmxSourceProgram &program = program_it->second;
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
        if (!valid_property || property_universe < 0) {
            continue;
        }
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
            const CompiledDmxSourceProgram &program = source_programs_by_id_[contributor.source_program_id];
            for (const CompiledDmxByteSource &source : program.sources) {
                universe.interest_offsets.push_back(source.address);
            }
        }
        ++installed_properties;
    }
    if (installed_properties == 0) {
        diagnostics_.push_back({"PVZ-RUNTIME-NO-PROPERTIES", "error", "Compiled runtime scene installed zero supported Dimmer/Pan/Tilt/Zoom properties.", "CompiledRuntimeScene"});
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
    if (universe.has_pending_frame) {
        ++stats_.packets_coalesced;
    }
    const int clamped_length = std::clamp(length, 0, 512);
    universe.latest_frame.assign(data, data + clamped_length);
    universe.has_pending_frame = true;
}

// Consumes newest dirty universes and returns one typed sectioned visual frame.
SectionedVisualFrame PeravizVisualRuntimeCore::consume_latest_visual_frame() {
    SectionedVisualFrame frame;
    frame.schema_generation = schema_.schema_generation;
    struct PendingRow {
        int fixture_id = 0;
        int32_t property_id = 0;
        int32_t component_id = 0;
        int32_t render_target_id = 0;
        uint32_t changed_visual_mask = 0;
        ComponentState state;
    };
    std::vector<PendingRow> rows;

    for (auto &[_, universe] : universes_) {
        if (!universe.has_pending_frame) {
            continue;
        }
        universe.has_pending_frame = false;
        ++stats_.universes_considered;
        const uint64_t interest_hash = compute_interest_hash(universe.latest_frame, universe.interest_offsets);
        if (universe.has_hash && universe.interest_hash == interest_hash) {
            continue;
        }
        universe.has_hash = true;
        universe.interest_hash = interest_hash;

        std::unordered_map<int, ComponentState> pending_transform_by_fixture;
        for (const CompiledPropertyProgram &program : universe.properties) {
            const EvaluationResult evaluated = evaluate_property_value(universe.latest_frame, program.property);
            if (!evaluated.valid) {
                continue;
            }
            const float semantic_value = program.parameter == SemanticParameter::Dimmer ? evaluated.normalized_value : evaluated.physical_value;
            if (program.parameter == SemanticParameter::Dimmer || program.parameter == SemanticParameter::Zoom) {
                ComponentState state;
                auto existing = property_state_by_property_.find(program.property.property_id);
                if (existing != property_state_by_property_.end()) {
                    state = existing->second;
                }
                apply_semantic_value(state, program.parameter, semantic_value);
                if (program.parameter == SemanticParameter::Zoom) {
                    state.zoom_normalized = evaluated.normalized_value;
                    state.has_zoom_physical = true;
                }
                const auto params_it = render_params_by_fixture_.find(program.property.fixture_id);
                cook_render_state(state, params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams());
                const FixtureChangeResult change = merge_property_state(program.property.property_id, state, visual_mask_for_parameter(program.parameter));
                if (!change.changed) {
                    ++stats_.fixtures_skipped;
                    continue;
                }
                add_visual_mask_stats(change.changed_visual_mask);
                ++stats_.fixtures_dirty;
                rows.push_back({program.property.fixture_id, program.property.property_id, program.property.component_id, program.property.render_target_id, change.changed_visual_mask, state});
                continue;
            }

            ComponentState &state = pending_transform_by_fixture[program.property.fixture_id];
            auto existing = transform_state_by_fixture_.find(program.property.fixture_id);
            if (!state.initialized && existing != transform_state_by_fixture_.end()) {
                state = existing->second;
            }
            apply_semantic_value(state, program.parameter, semantic_value);
        }

        for (auto &[fixture_id, next_state] : pending_transform_by_fixture) {
            const auto params_it = render_params_by_fixture_.find(fixture_id);
            cook_render_state(next_state, params_it != render_params_by_fixture_.end() ? params_it->second : FixtureRenderParams());
            const FixtureChangeResult change = merge_transform_state(fixture_id, next_state);
            if (!change.changed) {
                ++stats_.fixtures_skipped;
                continue;
            }
            add_visual_mask_stats(change.changed_visual_mask);
            ++stats_.fixtures_dirty;
            rows.push_back({fixture_id, 0, 0, 0, change.changed_visual_mask, next_state});
        }
    }

    auto section_count_for = [&rows](uint32_t mask) {
        return static_cast<int32_t>(std::count_if(rows.begin(), rows.end(), [mask](const PendingRow &row) { return (row.changed_visual_mask & mask) != 0U; }));
    };

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
        case CompiledSemantic::Unknown: return SemanticParameter::Unknown;
    }
    return SemanticParameter::Unknown;
}

// Reads a compiled DMX program by assembling ordered source bytes into a raw integer value.
uint32_t PeravizVisualRuntimeCore::read_raw_value(const std::vector<uint8_t> &frame, const CompiledDmxSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics) {
    if (program.sources.empty() || program.sources.size() > 4) {
        if (diagnostics != nullptr) diagnostics->push_back({"PVZ-RUNTIME-UNSUPPORTED-BYTE-COUNT", "warning", "Compiled DMX source byte count must be between one and four.", std::to_string(program.program_id)});
        return 0U;
    }
    std::vector<CompiledDmxByteSource> ordered = program.sources;
    std::sort(ordered.begin(), ordered.end(), [](const CompiledDmxByteSource &a, const CompiledDmxByteSource &b) { return a.byte_order < b.byte_order; });
    uint32_t raw_value = 0;
    for (const CompiledDmxByteSource &source : ordered) {
        const bool valid = source.address >= 0 && source.address < static_cast<int32_t>(frame.size());
        if (!valid && diagnostics != nullptr) diagnostics->push_back({"PVZ-RUNTIME-INVALID-BYTE", "warning", "Compiled DMX byte address is outside the submitted frame.", std::to_string(program.program_id)});
        const uint8_t value = valid ? frame[static_cast<size_t>(source.address)] : 0;
        raw_value = (raw_value << 8U) | value;
    }
    return raw_value;
}

// Evaluates one source program into raw, local normalized, and physical representations.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_source_program(const std::vector<uint8_t> &frame, const CompiledDmxSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics) {
    uint32_t max_value = 0;
    for (size_t index = 0; index < program.sources.size() && index < 4; ++index) {
        max_value = (max_value << 8U) | 0xffU;
    }
    const uint32_t raw_value = read_raw_value(frame, program, diagnostics);
    const double dmx_span = program.dmx_to > program.dmx_from ? static_cast<double>(program.dmx_to - program.dmx_from) : static_cast<double>(max_value);
    const double full_range_normalized = max_value > 0 ? static_cast<double>(raw_value) / static_cast<double>(max_value) : 0.0;
    const double local = dmx_span > 0.0 ? std::clamp((static_cast<double>(raw_value) - static_cast<double>(program.dmx_from)) / dmx_span, 0.0, 1.0) : full_range_normalized;
    const double physical = program.physical_from + ((program.physical_to - program.physical_from) * local);
    return {raw_value, static_cast<float>(local), static_cast<float>(physical), program.program_id, true};
}

// Resolves all contributors for one property into a single deterministic value.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_property_value(const std::vector<uint8_t> &frame, const CompiledComponentProperty &property) {
    double weighted_normalized_sum = 0.0;
    double weighted_physical_sum = 0.0;
    double total_weight = 0.0;
    const CompiledDmxSourceProgram *active_program = nullptr;
    bool has_range_selector = false;
    bool has_reference_range = false;
    uint32_t reference_from = 0;
    uint32_t reference_to = 0;
    for (const CompiledPropertyContributor &contributor : property.contributors) {
        if (contributor.operation != CompiledContributorOperation::WeightedAdd) {
            diagnostics_.push_back({"PVZ-RUNTIME-UNSUPPORTED-CONTRIBUTOR", "warning", "Compiled contributor operation is not supported.", std::to_string(contributor.source_program_id)});
            continue;
        }
        auto program_it = source_programs_by_id_.find(contributor.source_program_id);
        if (program_it == source_programs_by_id_.end()) {
            diagnostics_.push_back({"PVZ-RUNTIME-MISSING-PROGRAM", "warning", "Compiled contributor references a missing source program.", std::to_string(contributor.source_program_id)});
            continue;
        }
        const CompiledDmxSourceProgram &program = program_it->second;
        if (!has_reference_range) {
            reference_from = program.dmx_from;
            reference_to = program.dmx_to;
            has_reference_range = true;
        } else if (program.dmx_from != reference_from || program.dmx_to != reference_to) {
            has_range_selector = true;
        }
        const uint32_t raw_value = read_raw_value(frame, program, &diagnostics_);
        if (raw_value >= program.dmx_from && raw_value <= program.dmx_to) {
            if (active_program != nullptr) diagnostics_.push_back({"PVZ-RUNTIME-OVERLAPPING-FUNCTIONS", "warning", "Multiple ChannelFunctions matched the same raw DMX value; using the first match.", std::to_string(property.fixture_id)});
            if (active_program == nullptr) active_program = &program;
        }
    }
    if (property.contributors.size() > 1 && has_range_selector) {
        if (active_program == nullptr) {
            diagnostics_.push_back({"PVZ-RUNTIME-NO-ACTIVE-FUNCTION", "warning", "No ChannelFunction range matched the assembled raw DMX value.", std::to_string(property.fixture_id)});
            return {};
        }
        return evaluate_source_program(frame, *active_program, &diagnostics_);
    }
    EvaluationResult result;
    for (const CompiledPropertyContributor &contributor : property.contributors) {
        auto program_it = source_programs_by_id_.find(contributor.source_program_id);
        if (program_it == source_programs_by_id_.end()) {
            continue;
        }
        const double weight = contributor.weight;
        const EvaluationResult program_value = evaluate_source_program(frame, program_it->second, &diagnostics_);
        if (!program_value.valid) {
            continue;
        }
        if (!result.valid) {
            result.raw_value = program_value.raw_value;
            result.active_program_id = program_value.active_program_id;
            result.valid = true;
        }
        weighted_normalized_sum += static_cast<double>(program_value.normalized_value) * weight;
        weighted_physical_sum += static_cast<double>(program_value.physical_value) * weight;
        total_weight += weight;
    }
    if (total_weight == 0.0 || !result.valid) {
        return {};
    }
    result.normalized_value = static_cast<float>(weighted_normalized_sum / total_weight);
    result.physical_value = static_cast<float>(weighted_physical_sum / total_weight);
    return result;
}

// Computes a native hash over only patched DMX offsets for a universe.
uint64_t PeravizVisualRuntimeCore::compute_interest_hash(const std::vector<uint8_t> &frame, const std::vector<int> &offsets) {
    uint64_t hash = 1469598103934665603ULL;
    for (int offset : offsets) {
        const uint8_t value = offset >= 0 && offset < static_cast<int>(frame.size()) ? frame[static_cast<size_t>(offset)] : 0;
        hash ^= static_cast<uint64_t>(offset & 0xffff);
        hash *= 1099511628211ULL;
        hash ^= static_cast<uint64_t>(value);
        hash *= 1099511628211ULL;
    }
    return hash;
}

// Maps a semantic parameter to the render domains it can dirty.
uint32_t PeravizVisualRuntimeCore::visual_mask_for_parameter(SemanticParameter parameter) {
    switch (parameter) {
        case SemanticParameter::Dimmer: return VisualChangeDimmer | VisualChangeMaterial | VisualChangeBeamTopology;
        case SemanticParameter::Pan:
        case SemanticParameter::Tilt: return VisualChangeTransform;
        case SemanticParameter::Zoom: return VisualChangeZoom;
        case SemanticParameter::Cyan:
        case SemanticParameter::Magenta:
        case SemanticParameter::Yellow: return VisualChangeColor | VisualChangeMaterial;
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
        case SemanticParameter::Cyan: state.cyan = value; break;
        case SemanticParameter::Magenta: state.magenta = value; break;
        case SemanticParameter::Yellow: state.yellow = value; break;
        case SemanticParameter::GoboSelect: state.gobo_select = value; break;
        case SemanticParameter::GoboIndex: state.gobo_index = value; break;
        case SemanticParameter::GoboRotation: state.gobo_rotation = value; break;
        case SemanticParameter::PrismSelect: state.prism_select = value; break;
        case SemanticParameter::PrismRotation: state.prism_rotation = value; break;
        case SemanticParameter::Strobe: state.strobe = value; break;
        case SemanticParameter::Unknown: break;
    }
}

// Cooks physical render values from component state without changing semantic ownership.
void PeravizVisualRuntimeCore::cook_render_state(ComponentState &state, const FixtureRenderParams &params) {
    constexpr double energy_scale = 0.02;
    constexpr double default_zoom_min = 4.0;
    constexpr double max_beam_angle = 90.0;
    constexpr double beam_intensity_max = 50.0;
    constexpr double cmy_epsilon = 0.0001;
    double beam_angle = std::clamp(params.beam_angle_default, 0.1, max_beam_angle);
    if (params.has_zoom) {
        if (state.has_zoom_physical) {
            beam_angle = std::clamp(static_cast<double>(state.zoom), 0.0, max_beam_angle);
        } else {
            double zoom_min = params.zoom_min_deg >= 0.0 ? params.zoom_min_deg : default_zoom_min;
            double zoom_max = params.zoom_max_deg >= 0.0 ? params.zoom_max_deg : max_beam_angle;
            beam_angle = std::clamp(zoom_min + ((zoom_max - zoom_min) * state.zoom_normalized), 0.0, max_beam_angle);
        }
    }
    state.red = state.cyan > cmy_epsilon || state.magenta > cmy_epsilon || state.yellow > cmy_epsilon ? 1.0f - state.cyan : 1.0f;
    state.green = state.cyan > cmy_epsilon || state.magenta > cmy_epsilon || state.yellow > cmy_epsilon ? 1.0f - state.magenta : 1.0f;
    state.blue = state.cyan > cmy_epsilon || state.magenta > cmy_epsilon || state.yellow > cmy_epsilon ? 1.0f - state.yellow : 1.0f;
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
    result.changed = !previous.initialized;
    if (!previous.initialized) {
        const auto mask_it = installed_visual_mask_by_fixture_.find(fixture_id);
        const uint32_t installed_mask = mask_it != installed_visual_mask_by_fixture_.end() ? mask_it->second : VisualChangeNone;
        result.changed_visual_mask = installed_mask & VisualChangeTransform;
    } else {
        if (!nearly_equal(previous.pan, next_state.pan, kDefaultEpsilon) || !nearly_equal(previous.tilt, next_state.tilt, kDefaultEpsilon)) result.changed_visual_mask |= VisualChangeTransform;
        result.changed = result.changed_visual_mask != VisualChangeNone;
    }
    result.changed_visual_mask &= VisualChangeTransform;
    result.changed = result.changed_visual_mask != VisualChangeNone;
    previous = next_state;
    previous.initialized = true;
    return result;
}

// Updates cached property state and returns target-local render domains that changed.
PeravizVisualRuntimeCore::FixtureChangeResult PeravizVisualRuntimeCore::merge_property_state(int32_t property_id, const ComponentState &next_state, uint32_t installed_mask) {
    ComponentState &previous = property_state_by_property_[property_id];
    FixtureChangeResult result;
    result.changed = !previous.initialized;
    if (!previous.initialized) {
        result.changed_visual_mask = installed_mask;
    } else {
        if (!nearly_equal(previous.dimmer, next_state.dimmer, kDefaultEpsilon)) result.changed_visual_mask |= installed_mask & visual_mask_for_parameter(SemanticParameter::Dimmer);
        if (previous.has_zoom_physical != next_state.has_zoom_physical || !nearly_equal(previous.zoom, next_state.zoom, kAngleEpsilon) || !nearly_equal(previous.zoom_normalized, next_state.zoom_normalized, kDefaultEpsilon) || !nearly_equal(previous.beam_angle, next_state.beam_angle, kAngleEpsilon)) result.changed_visual_mask |= installed_mask & visual_mask_for_parameter(SemanticParameter::Zoom);
        const bool previous_visible = previous.dimmer > kDefaultEpsilon;
        const bool current_visible = next_state.dimmer > kDefaultEpsilon;
        if ((installed_mask & visual_mask_for_parameter(SemanticParameter::Dimmer)) != 0U && previous_visible != current_visible) result.changed_visual_mask |= VisualChangeBeamTopology;
        result.changed = result.changed_visual_mask != VisualChangeNone;
    }
    result.changed_visual_mask &= installed_mask;
    result.changed = result.changed_visual_mask != VisualChangeNone;
    previous = next_state;
    previous.initialized = true;
    return result;
}

} // namespace peraviz::runtime
