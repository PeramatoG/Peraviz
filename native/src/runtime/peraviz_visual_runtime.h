#pragma once

#include "runtime/visual_frame_schema.h"

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
    struct CompiledChannelProgram {
        CompiledDmxSourceProgram source_program;
        std::vector<CompiledPropertyContributor> contributors;
        SemanticParameter parameter = SemanticParameter::Unknown;
        int32_t fixture_id = 0;
        int32_t component_id = 0;
        int32_t render_target_id = 0;
        int32_t wheel_id = 0;
    };

    struct UniverseState {
        std::vector<CompiledChannelProgram> programs;
        std::vector<int> interest_offsets;
        std::vector<uint8_t> latest_frame;
        uint64_t interest_hash = 0;
        bool has_pending_frame = false;
        bool has_hash = false;
    };

    struct ComponentState {
        float pan = 0.0f;
        float tilt = 0.0f;
        float dimmer = 0.0f;
        float zoom = 0.0f;
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

    struct FixtureChangeResult {
        bool changed = false;
        uint32_t changed_visual_mask = 0;
    };

    static SemanticParameter semantic_parameter_for_compiled(CompiledSemantic semantic);
    static float read_normalized_value(const std::vector<uint8_t> &frame, const CompiledDmxSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics);
    static uint64_t compute_interest_hash(const std::vector<uint8_t> &frame, const std::vector<int> &offsets);
    static uint32_t visual_mask_for_parameter(SemanticParameter parameter);
    static void apply_semantic_value(ComponentState &state, SemanticParameter parameter, float value);
    static void cook_render_state(ComponentState &state, const FixtureRenderParams &params);
    static bool nearly_equal(float a, float b, float epsilon);
    void add_visual_mask_stats(uint32_t visual_mask);
    FixtureChangeResult merge_component_state(int fixture_id, const ComponentState &next_state);

    std::unordered_map<int, UniverseState> universes_;
    std::unordered_map<int, FixtureRenderParams> render_params_by_fixture_;
    std::vector<CompiledRuntimeDiagnostic> diagnostics_;
    std::unordered_map<int, ComponentState> component_state_by_fixture_;
    std::unordered_map<int, int32_t> component_id_by_fixture_;
    std::unordered_map<int, int32_t> render_target_id_by_fixture_;
    VisualFrameSchema schema_ = make_visual_frame_schema(1, VisualFrameSchemaCapabilities());
    int32_t next_schema_generation_ = 1;
    VisualFrameStats stats_;
};

} // namespace peraviz::runtime
