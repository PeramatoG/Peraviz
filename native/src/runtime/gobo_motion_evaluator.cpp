#include "runtime/gobo_motion_evaluator.h"

#include <algorithm>

namespace peraviz::runtime {
namespace {

// Finds a compiled source program by stable runtime ID.
const CompiledDmxSourceProgram *find_program(const std::vector<CompiledDmxSourceProgram> &programs, int32_t id) {
    for (const CompiledDmxSourceProgram &program : programs) if (program.program_id == id) return &program;
    return nullptr;
}

// Finds the current raw value for a stable source program ID.
const GoboSourceValue *find_value(const std::vector<GoboSourceValue> &values, int32_t id) {
    for (const GoboSourceValue &value : values) if (value.source_program_id == id) return &value;
    return nullptr;
}

// Evaluates one setup-validated activation cascade with a strict depth bound.
bool activation_is_active(const CompiledDmxSourceProgram &program,
                          const std::vector<CompiledDmxSourceProgram> &programs,
                          const std::vector<GoboSourceValue> &values,
                          size_t depth) {
    if (depth > programs.size()) return false;
    const GoboSourceValue *own_value = find_value(values, program.program_id);
    if (!own_value || own_value->raw_value < program.dmx_from || own_value->raw_value > program.dmx_to) return false;
    const gdtf_runtime::ModeMasterCondition &condition = program.activation;
    if (!condition.valid || condition.target_kind == gdtf_runtime::ModeMasterTargetKind::Invalid) return false;
    if (condition.target_kind == gdtf_runtime::ModeMasterTargetKind::None) return true;
    const CompiledDmxSourceProgram *master = find_program(programs, condition.master_program_id);
    const GoboSourceValue *master_value = master ? find_value(values, master->program_id) : nullptr;
    if (!master || !master_value || master_value->raw_value < condition.from || master_value->raw_value > condition.to) return false;
    return condition.target_kind != gdtf_runtime::ModeMasterTargetKind::ChannelFunction || activation_is_active(*master, programs, values, depth + 1);
}

} // namespace

// Evaluates the active exact gobo semantic and its instantaneous physical scalar.
EvaluatedGoboScalar evaluate_gobo_motion_scalar(const CompiledGoboMotionBinding &binding,
                                                const std::vector<CompiledDmxSourceProgram> &programs,
                                                const std::vector<GoboSourceValue> &values) {
    EvaluatedGoboScalar result;
    result.binding_id = binding.binding_id;
    result.semantic_kind = binding.semantic_kind;
    result.physical_unit = binding.physical_unit;
    const CompiledDmxSourceProgram *program = find_program(programs, binding.source_program_id);
    const GoboSourceValue *value = program ? find_value(values, program->program_id) : nullptr;
    if (!program || !value || !binding.scalar_evaluable || !activation_is_active(*program, programs, values, 0)) return result;
    result.raw_value = value->raw_value;
    const uint32_t span = program->dmx_to - program->dmx_from;
    result.normalized_value = span == 0 ? 0.0 : static_cast<double>(value->raw_value - program->dmx_from) / static_cast<double>(span);
    result.normalized_value = std::clamp(result.normalized_value, 0.0, 1.0);
    result.physical_value = binding.physical_from + (binding.physical_to - binding.physical_from) * result.normalized_value;
    result.active = true;
    return result;
}

} // namespace peraviz::runtime
