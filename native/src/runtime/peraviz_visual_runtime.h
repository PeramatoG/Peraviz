#pragma once
#include "runtime/ordered_dirty_indices.h"
#include "runtime/compiled_evaluation_plan.h"
#include "runtime/shutter_trace.h"
#include "runtime/gobo_motion_evaluator.h"
#include "runtime/parallel_evaluation_prefetch.h"

#include "runtime/visual_frame_schema.h"
#include "runtime/visual_runtime_types.h"
#include "runtime/runtime_state_sizes.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <utility>
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
    PeravizVisualRuntimeCore();
    ~PeravizVisualRuntimeCore();
    void set_native_executor(NativeBatchExecutor *executor);
    ParallelEvaluationMetrics parallel_metrics() const;
    bool async_eligible_workload() const;
    // Temporal/gobo scenes retain the existing serial transaction to preserve every observed transition.
    bool has_gobo_domains() const { return has_gobo_domains_; }
    SectionedVisualFrame held_domain_replay() const;
    struct HeldUniverse { int id=0; std::vector<uint8_t> values; };
    std::vector<HeldUniverse> held_universes() const;
    void clear();
    void install_compiled_scene(const CompiledRuntimeScene &scene);
    void submit_universe_frame(int universe_id, const uint8_t *data, int length);
    SectionedVisualFrame consume_latest_visual_frame();
    void consume_latest_visual_frame(SectionedVisualFrame &frame);
    const VisualFrameSchema &schema() const;
    const VisualFrameStats &stats() const;
    std::vector<ShutterTrace> shutter_trace(int32_t fixture,int32_t target=0) const;
    // Exposes structured native issues only to callers holding exclusive core ownership.
    const std::vector<CompiledRuntimeDiagnostic> &diagnostics() const { return diagnostics_; }
    RuntimeStateSizes state_sizes() const;
    void set_performance_trace_enabled(bool enabled);
    double runtime_now_seconds() const;
    void set_runtime_now_seconds_for_testing(double seconds);
    std::vector<std::pair<uint16_t, std::vector<uint16_t>>> realtime_interest_offsets() const;

private:
    friend class ParallelEvaluationPrefetch;
    std::unique_ptr<ParallelEvaluationPrefetch> prefetch_;
    size_t installed_sources_=0,installed_colors_=0;
    bool has_gobo_domains_=false;
    struct CompiledPropertyProgram {
        CompiledComponentProperty property;
        SemanticParameter parameter = SemanticParameter::Unknown;
        std::vector<uint32_t> sources;
        bool range_selector = false;
    };

    struct InstalledSourceProgram {
        CompiledDmxSourceProgram program;
        std::shared_ptr<const SourceValueMapping> mapping;
        mutable bool diagnosed_byte_count = false;
        mutable bool diagnosed_missing_byte = false;
    };

    struct ColorInputRuntime {
        CompiledColorInputBinding binding;
        float value = 0.0f;
        bool initialized = false;
        uint32_t source = 0;
    };

    struct ColorTargetRuntime {
        CompiledColorTargetProgram target;
        std::vector<ColorInputRuntime> inputs;
    };

    struct WheelBindingRuntime {
        CompiledWheelTargetBinding binding;
        uint32_t source = 0;
    };

    struct WheelTargetState {
        int32_t active_binding_id = 0;
        int32_t beam_target_id = 0;
        int32_t wheel_renderer_id = 0;
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

    struct GoboEvaluationContext {
        std::vector<int32_t> dependency_program_ids;
        std::shared_ptr<const GoboSourceDefinitions> programs;
        std::vector<uint32_t> sources;
        std::vector<GoboSourceValue> values;
    };
    struct ShutterBindingRuntime : GoboEvaluationContext { CompiledShutterBinding binding; };
    struct GoboBindingRuntime : GoboEvaluationContext { CompiledGoboSelectionBinding binding; };
    struct GoboMotionRuntime : GoboEvaluationContext { CompiledGoboMotionBinding binding; };

    struct GoboSelectionState {
        int32_t slot_index = 0;
        int32_t asset_id = 0;
        int32_t contributing_binding_id = 0;
        int32_t revision = 0;
        bool initialized = false;
    };
    struct GoboRotationState {
        double phase_degrees = 0.0;
        double angular_velocity_dps = 0.0;
        double reference_seconds = 0.0;
        double pos_degrees = 0.0;
        double pos_rotate_dps = 0.0;
        GoboRotationMode mode = GoboRotationMode::Hold;
        int32_t revision = 0;
        int32_t pos_binding_id = 0;
        int32_t pos_rotate_binding_id = 0;
        bool pos_active = false;
        bool pos_rotate_active = false;
        bool initialized = false;
    };

    struct UniverseState {
        CompiledEvaluationPlan plan;
        std::vector<InstalledSourceProgram *> source_bindings;
        std::vector<uint8_t> prefetched_warnings;
        std::vector<int> dirty_properties, dirty_colors;
        OrderedDirtyIndices dirty_wheels;
        std::vector<int64_t> dirty_gobo_selections, dirty_gobo_motions, dirty_physical_wheels;
        std::vector<int32_t> wheel_dirty_targets, dirty_color_targets;
        std::vector<int> changed_offsets;
        std::vector<CompiledPropertyProgram> properties;
        std::vector<ColorTargetRuntime> color_targets;
        std::unordered_map<int32_t, int32_t> color_fixture_by_target;
        std::vector<WheelBindingRuntime> wheel_bindings;
        std::unordered_map<int32_t, std::vector<int>> wheel_binding_indices_by_target;
        std::unordered_map<int64_t, std::vector<int>> wheel_binding_indices_by_physical_key;
        std::unordered_map<int32_t, std::vector<int64_t>> wheel_physical_keys_by_target;
        std::vector<int> interest_offsets;
        std::vector<GoboBindingRuntime> gobo_bindings;
        std::unordered_map<int64_t, std::vector<int>> gobo_binding_indices_by_layer;
        std::vector<ShutterBindingRuntime> shutters;
        std::unordered_map<int64_t,std::vector<int>> shutter_layers;
        std::vector<int64_t> dirty_shutters;
        std::vector<GoboMotionRuntime> gobo_motion_bindings;
        std::unordered_map<int64_t, std::vector<int>> gobo_motion_indices_by_layer;
        std::array<uint8_t, 512> last_relevant_values{};
        std::vector<uint8_t> latest_frame;
        bool has_pending_frame = false;
        bool has_last_relevant_values = false;
    };

    struct ShutterState { int32_t fixture_id=0,target_id=0,index=1,authority=0; };
    struct ShutterAuthorityState {
        int32_t fixture_id=0,index=1; uint32_t seed=0; bool diagnosed=false;
        std::vector<int32_t> targets;
        gdtf_runtime::ShutterParameters parameters;
    };
    std::unordered_map<int32_t,ShutterAuthorityState> shutter_authorities_;
    std::unordered_map<int64_t,ShutterState> shutter_states_;
    std::unordered_set<int32_t> shutter_unsupported_fixtures_;
    void install_shutters(const CompiledRuntimeScene &scene,VisualFrameSchemaCapabilities &capabilities);
    void evaluate_shutters(UniverseState &universe,SectionedVisualFrame &frame);
    void replay_shutters(SectionedVisualFrame &frame) const;
    using EvaluationResult = EvaluatedSourceValue;

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

    using CookedEmitterColor = CookedEmitterColorValue;

    struct FixtureChangeResult {
        bool changed = false;
        uint32_t changed_visual_mask = 0;
    };

    static SemanticParameter semantic_parameter_for_compiled(CompiledSemantic semantic);
    static bool is_color_semantic(CompiledSemantic semantic);
    static uint32_t max_raw_value_for_source_count(size_t source_count);
    static uint32_t read_raw_value(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics, uint8_t *warnings = nullptr);
    static EvaluationResult evaluate_source_program(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics, uint8_t *warnings = nullptr);
    void install_source_mappings(const CompiledRuntimeScene &scene);
    void compile_evaluation_plans();
    void emit_source_warnings(const InstalledSourceProgram &program,uint8_t warnings);
    EvaluationResult evaluate_cached_source(UniverseState &universe, uint32_t source);
    EvaluationResult evaluate_property_value(UniverseState &universe, const CompiledPropertyProgram &property);
    void fill_gobo_context(UniverseState &universe, GoboEvaluationContext &context);
    bool evaluate_cached_activation(UniverseState &universe, GoboEvaluationContext &context);
    static uint32_t visual_mask_for_parameter(SemanticParameter parameter);
    static void apply_semantic_value(ComponentState &state, SemanticParameter parameter, float value);
    static void cook_render_state(ComponentState &state, const FixtureRenderParams &params);
    static bool nearly_equal(float a, float b, float epsilon);
    static float color_value_from_evaluation(CompiledSemantic semantic, const EvaluationResult &evaluated);
    static int64_t wheel_physical_key(int32_t beam_target_id, int32_t wheel_renderer_id);
    CookedEmitterColor cook_emitter_color(const ColorTargetRuntime &target,const float *overrides=nullptr) const;
    CookedEmitterColor compose_ordered_target_color(int32_t beam_target_id,const CookedEmitterColor *base_override=nullptr) const;
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
    std::unordered_map<int64_t, WheelTargetState> wheel_state_by_physical_key_;
    std::unordered_map<int32_t, std::vector<const WheelTargetState *>> ordered_wheel_layers_;
    size_t mapping_definitions_ = 0, fixture_mode_definitions_ = 0;
    std::unordered_map<int64_t, GoboSelectionState> gobo_selection_state_by_layer_;
    std::unordered_map<int64_t, GoboRotationState> gobo_rotation_state_by_layer_;
    std::unordered_set<int64_t> diagnosed_ambiguous_gobo_selection_layers_;
    std::unordered_set<int64_t> diagnosed_ambiguous_gobo_pos_layers_;
    std::unordered_set<int64_t> diagnosed_ambiguous_gobo_posrotate_layers_;
    std::unordered_set<int64_t> diagnosed_simultaneous_gobo_posrotate_layers_;
    std::chrono::steady_clock::time_point runtime_epoch_ = std::chrono::steady_clock::now();
    double test_runtime_now_seconds_ = -1.0;
    std::unordered_map<int64_t, int32_t> gobo_asset_by_wheel_slot_;
    std::unordered_map<int, int32_t> pan_component_id_by_fixture_;
    std::unordered_map<int, int32_t> tilt_component_id_by_fixture_;
    std::unordered_map<int, uint32_t> installed_visual_mask_by_fixture_;
    std::unordered_map<int32_t, InstalledSourceProgram> source_programs_by_id_;
    std::unordered_map<int32_t, CompiledEmitterResource> emitter_resources_by_id_;
    std::unordered_map<int32_t, CompiledFilterResource> filter_resources_by_id_;
    VisualFrameSchema schema_ = make_visual_frame_schema(1, VisualFrameSchemaCapabilities());
    int32_t next_schema_generation_ = 1;
    VisualFrameStats stats_;
    bool performance_trace_enabled_ = false;
};

} // namespace peraviz::runtime
