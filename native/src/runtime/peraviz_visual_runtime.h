#pragma once

#include "runtime/visual_frame_schema.h"

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace peraviz::runtime {

enum class SemanticParameter : int32_t {
    Unknown = 0,
    Pan,
    Tilt,
    Dimmer,
    Zoom,
    Cyan,
    Magenta,
    Yellow,
    GoboSelect,
    GoboIndex,
    GoboRotation,
    PrismSelect,
    PrismRotation,
    Strobe,
};

class PeravizVisualRuntimeCore {
public:
    void clear();
    void install_compiled_scene(const CompiledRuntimeScene &scene);
    void submit_universe_frame(int universe_id, const uint8_t *data, int length);
    SectionedVisualFrame consume_latest_visual_frame();
    const VisualFrameSchema &schema() const;
    const VisualFrameStats &stats() const;

private:
    struct CompiledPropertyProgram {
        CompiledComponentProperty property;
        SemanticParameter parameter = SemanticParameter::Unknown;
    };

    struct UniverseState {
        std::vector<CompiledPropertyProgram> properties;
        std::vector<int> interest_offsets;
        std::vector<uint8_t> latest_frame;
        uint64_t interest_hash = 0;
        bool has_pending_frame = false;
        bool has_hash = false;
    };

    struct EvaluationResult {
        uint32_t raw_value = 0;
        float normalized_value = 0.0f;
        float physical_value = 0.0f;
        int32_t active_program_id = 0;
        bool valid = false;
    };

    struct ComponentState {
        float pan = 0.0f;
        float tilt = 0.0f;
        float dimmer = 0.0f;
        float zoom = 0.0f;
        float zoom_normalized = 0.0f;
        bool has_zoom_physical = false;
        float cyan = 0.0f;
        float magenta = 0.0f;
        float yellow = 0.0f;
        float gobo_select = 0.0f;
        float gobo_index = 0.0f;
        float gobo_rotation = 0.0f;
        float prism_select = 0.0f;
        float prism_rotation = 0.0f;
        float strobe = 0.0f;
        float beam_energy = 0.0f;
        float spot_energy = 0.0f;
        float beam_half_angle = 12.5f;
        float beam_angle = 25.0f;
        float red = 1.0f;
        float green = 1.0f;
        float blue = 1.0f;
        float beam_intensity = 0.0f;
        float material_energy = 0.0f;
        bool initialized = false;
    };

    struct BeamPhotometricTarget {
        int32_t render_target_id = 0;
        std::string geometry_path;
        double target_luminous_flux_lm = 10000.0;
        double fixture_projected_flux_lm = 10000.0;
        double target_flux_fraction = 1.0;
    };

    struct FixtureChangeResult {
        bool changed = false;
        uint32_t changed_visual_mask = 0;
    };

    static SemanticParameter semantic_parameter_for_compiled(CompiledSemantic semantic);
    static uint32_t read_raw_value(const std::vector<uint8_t> &frame, const CompiledDmxSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics);
    static EvaluationResult evaluate_source_program(const std::vector<uint8_t> &frame, const CompiledDmxSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics);
    EvaluationResult evaluate_property_value(const std::vector<uint8_t> &frame, const CompiledComponentProperty &property);
    static uint64_t compute_interest_hash(const std::vector<uint8_t> &frame, const std::vector<int> &offsets);
    static uint32_t visual_mask_for_parameter(SemanticParameter parameter);
    static void apply_semantic_value(ComponentState &state, SemanticParameter parameter, float value);
    static void cook_render_state(ComponentState &state, const FixtureRenderParams &params);
    static ComponentState scale_state_for_beam_target(const ComponentState &state, const BeamPhotometricTarget &target);
    static bool beam_target_belongs_to_property(const BeamPhotometricTarget &target, const CompiledComponentProperty &property);
    static bool nearly_equal(float a, float b, float epsilon);
    void add_visual_mask_stats(uint32_t visual_mask);
    FixtureChangeResult merge_transform_state(int fixture_id, const ComponentState &next_state);
    FixtureChangeResult merge_property_state(int32_t property_id, const ComponentState &next_state, uint32_t installed_mask);

    std::unordered_map<int, UniverseState> universes_;
    std::unordered_map<int, FixtureRenderParams> render_params_by_fixture_;
    std::vector<CompiledRuntimeDiagnostic> diagnostics_;
    std::unordered_map<int, ComponentState> transform_state_by_fixture_;
    std::unordered_map<int32_t, ComponentState> property_state_by_property_;
    std::unordered_map<int, int32_t> pan_component_id_by_fixture_;
    std::unordered_map<int, int32_t> tilt_component_id_by_fixture_;
    std::unordered_map<int, uint32_t> installed_visual_mask_by_fixture_;
    std::unordered_map<int32_t, CompiledDmxSourceProgram> source_programs_by_id_;
    std::unordered_map<int, std::vector<BeamPhotometricTarget>> beam_targets_by_fixture_;
    std::unordered_map<int32_t, std::vector<BeamPhotometricTarget>> beam_targets_by_dimmer_property_;
    VisualFrameSchema schema_ = make_visual_frame_schema(1, VisualFrameSchemaCapabilities());
    int32_t next_schema_generation_ = 1;
    VisualFrameStats stats_;
};

} // namespace peraviz::runtime
