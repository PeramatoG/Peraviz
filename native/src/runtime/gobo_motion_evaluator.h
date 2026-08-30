#pragma once

#include "runtime/visual_runtime_types.h"

#include <vector>

namespace peraviz::runtime {

struct GoboSourceValue {
    int32_t source_program_id = 0;
    uint32_t raw_value = 0;
};

struct EvaluatedGoboScalar {
    int32_t binding_id = 0;
    gdtf_runtime::GoboSemanticKind semantic_kind = gdtf_runtime::GoboSemanticKind::None;
    uint32_t raw_value = 0;
    double normalized_value = 0.0;
    double physical_value = 0.0;
    int32_t wheel_slot_index = 0;
    std::string physical_unit;
    bool active = false;
};

bool evaluate_gobo_source_activation(int32_t source_program_id,
                                     const std::vector<CompiledDmxSourceProgram> &programs,
                                     const std::vector<GoboSourceValue> &values,
                                     uint32_t *raw_value = nullptr);

EvaluatedGoboScalar evaluate_gobo_motion_scalar(const CompiledGoboMotionBinding &binding,
                                                const std::vector<CompiledDmxSourceProgram> &programs,
                                                const std::vector<GoboSourceValue> &values);

} // namespace peraviz::runtime
