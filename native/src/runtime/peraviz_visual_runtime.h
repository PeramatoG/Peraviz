#pragma once

#include "runtime/visual_frame_schema.h"
#include "runtime/visual_runtime_types.h"

#include <array>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace peraviz::runtime {

enum class SemanticParameter : int32_t {
    Unknown = 0,
    Pan,
    Tilt,
    Dimmer,
    Zoom,
    ColorAddRed,
    ColorAddGreen,
    ColorAddBlue,
    ColorAddWhite,
    ColorAddAmber,
    ColorAddLime,
    ColorSubCyan,
    ColorSubMagenta,
    ColorSubYellow,
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

    struct InstalledSourceProgram {
        CompiledDmxSourceProgram program;
        uint32_t max_value = 255;
        double inverse_max_value = 1.0 / 255.0;
    };

    struct ColorInputRuntime {
        CompiledColorInputBinding binding;
        float value = 0.0f;
        bool initialized = false;
    };

    struct ColorTargetRuntime {
        CompiledColorTargetProgram target;
        std::vector<ColorInputRuntime> inputs;
    };

    struct WheelBindingRuntime {
        CompiledWheelTargetBinding binding;
    };

    struct WheelTargetState {
        int32_t beam_target_id = 0;
        int32_t slot_a = 0;
        int32_t slot_b = 0;
        float srgb_red = 1.0f;
        float srgb_green = 1.0f;
        float srgb_blue = 1.0f;
        float gain = 1.0f;
        double linear_red = 1.0;
        double linear_green = 1.0;
        double linear_blue = 1.0;
        float normalized_phase = 0.0f;
        float split_fraction = 0.0f;
        float boundary_angle_degrees = 0.0f;
        CompiledWheelMode mode = CompiledWheelMode::Select;
        int32_t revision = 0;
        bool initialized = false;
    };

    struct UniverseState {
        std::vector<CompiledPropertyProgram> properties;
        std::vector<ColorTargetRuntime> color_targets;
        std::unordered_map<int, std::vector<int>> property_indices_by_offset;
        std::unordered_map<int, std::vector<int>> color_target_indices_by_offset;
        std::vector<WheelBindingRuntime> wheel_bindings;
        std::unordered_map<int, std::vector<int>> wheel_binding_indices_by_offset;
        std::unordered_map<int32_t, std::vector<int>> wheel_binding_indices_by_target;
        std::vector<int> interest_offsets;
        std::array<uint8_t, 512> last_relevant_values{};
        std::vector<uint8_t> latest_frame;
        bool has_pending_frame = false;
        bool has_last_relevant_values = false;
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
        float beam_energy = 0.0f;
        float spot_energy = 0.0f;
        float beam_half_angle = 12.5f;
        float beam_angle = 25.0f;
        float beam_intensity = 0.0f;
        float material_energy = 0.0f;
        bool initialized = false;
    };

    struct CookedEmitterColor {
        float srgb_red = 1.0f;
        float srgb_green = 1.0f;
        float srgb_blue = 1.0f;
        float gain = 1.0f;
        double linear_red = 1.0;
        double linear_green = 1.0;
        double linear_blue = 1.0;
        bool valid = true;
        bool initialized = false;
    };

    struct FixtureChangeResult {
        bool changed = false;
        uint32_t changed_visual_mask = 0;
    };

    static SemanticParameter semantic_parameter_for_compiled(CompiledSemantic semantic);
    static bool is_color_semantic(CompiledSemantic semantic);
    static uint32_t max_raw_value_for_source_count(size_t source_count);
    static uint32_t read_raw_value(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics);
    static EvaluationResult evaluate_source_program(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics);
    EvaluationResult evaluate_property_value(const std::vector<uint8_t> &frame, const CompiledComponentProperty &property);
    EvaluationResult evaluate_source_program_by_id(const std::vector<uint8_t> &frame, int32_t source_program_id);
    static uint32_t visual_mask_for_parameter(SemanticParameter parameter);
    static void apply_semantic_value(ComponentState &state, SemanticParameter parameter, float value);
    static void cook_render_state(ComponentState &state, const FixtureRenderParams &params);
    static bool nearly_equal(float a, float b, float epsilon);
    static bool program_uses_changed_offset(const CompiledDmxSourceProgram &program, const std::vector<int> &changed_offsets);
    static float color_value_from_evaluation(CompiledSemantic semantic, const EvaluationResult &evaluated);
    CookedEmitterColor cook_emitter_color(const ColorTargetRuntime &target) const;
    CookedEmitterColor compose_ordered_target_color(int32_t beam_target_id) const;
    CookedEmitterColor cook_wheel_slot_layer(const CompiledWheelPaletteSlot &slot) const;
    CookedEmitterColor aggregate_indexed_wheel_layer(const CompiledWheelPaletteSlot &slot_a, const CompiledWheelPaletteSlot &slot_b, float split_fraction) const;
    void add_visual_mask_stats(uint32_t visual_mask);
    FixtureChangeResult merge_transform_state(int fixture_id, const ComponentState &next_state);
    FixtureChangeResult merge_property_state(int32_t property_id, const ComponentState &next_state, uint32_t installed_mask);

    std::unordered_map<int, UniverseState> universes_;
    std::unordered_map<int, FixtureRenderParams> render_params_by_fixture_;
    std::vector<CompiledRuntimeDiagnostic> diagnostics_;
    std::unordered_map<int, ComponentState> transform_state_by_fixture_;
    std::unordered_map<int32_t, ComponentState> property_state_by_property_;
    std::unordered_map<int32_t, CookedEmitterColor> base_color_state_by_target_;
    std::unordered_map<int32_t, CookedEmitterColor> color_state_by_target_;
    std::unordered_map<int32_t, CompiledWheelPalette> wheel_palettes_by_id_;
    std::unordered_map<int32_t, WheelTargetState> wheel_state_by_binding_;
    std::unordered_map<int, int32_t> pan_component_id_by_fixture_;
    std::unordered_map<int, int32_t> tilt_component_id_by_fixture_;
    std::unordered_map<int, uint32_t> installed_visual_mask_by_fixture_;
    std::unordered_map<int32_t, InstalledSourceProgram> source_programs_by_id_;
    std::unordered_map<int32_t, CompiledEmitterResource> emitter_resources_by_id_;
    std::unordered_map<int32_t, CompiledFilterResource> filter_resources_by_id_;
    VisualFrameSchema schema_ = make_visual_frame_schema(1, VisualFrameSchemaCapabilities());
    int32_t next_schema_generation_ = 1;
    VisualFrameStats stats_;
};

} // namespace peraviz::runtime
