#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>

namespace peraviz::runtime {
// Assembles source bytes and reports each invalid-input category once per installed program.
uint32_t PeravizVisualRuntimeCore::read_raw_value(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics, uint8_t *warnings) {
    if (warnings) *warnings=0;
    if (program.program.sources.empty() || program.program.sources.size() > 4) {
        if (diagnostics != nullptr && !program.diagnosed_byte_count) {
            diagnostics->push_back({"PVZ-RUNTIME-UNSUPPORTED-BYTE-COUNT", "warning", "Compiled DMX source byte count must be between one and four.", std::to_string(program.program.program_id)});
            program.diagnosed_byte_count = true;
        }
        if (warnings) *warnings|=1;
        return 0U;
    }
    uint32_t raw_value = 0;
    for (const CompiledDmxByteSource &source : program.program.sources) {
        const bool valid = source.address >= 0 && source.address < static_cast<int32_t>(frame.size());
        if (!valid && diagnostics != nullptr && !program.diagnosed_missing_byte) {
            diagnostics->push_back({"PVZ-RUNTIME-INVALID-BYTE", "warning", "Compiled DMX byte address is outside the submitted frame.", std::to_string(program.program.program_id)});
            program.diagnosed_missing_byte = true;
        }
        if (!valid && warnings) *warnings|=2;
        const uint8_t value = valid ? frame[static_cast<size_t>(source.address)] : 0;
        raw_value = (raw_value << 8U) | value;
    }
    return raw_value;
}

// Evaluates one source program into raw, local normalized, and physical representations.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_source_program(const std::vector<uint8_t> &frame, const InstalledSourceProgram &program, std::vector<CompiledRuntimeDiagnostic> *diagnostics, uint8_t *warnings) {
    const uint32_t raw_value = read_raw_value(frame, program, diagnostics, warnings);
    const double dmx_span = program.mapping->span;
    const double full_range_normalized = static_cast<double>(raw_value) * program.mapping->inverse_maximum;
    const double local = dmx_span > 0.0 ? std::clamp((static_cast<double>(raw_value) - static_cast<double>(program.program.dmx_from)) / dmx_span, 0.0, 1.0) : full_range_normalized;
    const double physical = program.mapping->physical_from + ((program.mapping->physical_to - program.mapping->physical_from) * local);
    return {raw_value, static_cast<float>(local), static_cast<float>(physical), program.program.program_id, true};
}

// Defers diagnostic ownership to the deterministic coordinator after pure worker decoding.
void PeravizVisualRuntimeCore::emit_source_warnings(const InstalledSourceProgram &program,uint8_t warnings) {
    if ((warnings&1) && !program.diagnosed_byte_count) {
        diagnostics_.push_back({"PVZ-RUNTIME-UNSUPPORTED-BYTE-COUNT","warning","Compiled DMX source byte count must be between one and four.",std::to_string(program.program.program_id)});
        program.diagnosed_byte_count=true;
    }
    if ((warnings&2) && !program.diagnosed_missing_byte) {
        diagnostics_.push_back({"PVZ-RUNTIME-INVALID-BYTE","warning","Compiled DMX byte address is outside the submitted frame.",std::to_string(program.program.program_id)});
        program.diagnosed_missing_byte=true;
    }
}
// Reuses one source result across all targets in the same submitted-universe context.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_cached_source(UniverseState &universe, uint32_t source) {
    if (universe.plan.needs_evaluation(source)) {
        const auto value=evaluate_source_program(universe.latest_frame,*universe.source_bindings[source],&diagnostics_);
        universe.plan.store(source,value); universe.prefetched_warnings[source]=0;
        if (performance_trace_enabled_) ++stats_.source_programs_evaluated;
    } else if (performance_trace_enabled_) ++stats_.source_cache_hits;
    if (universe.prefetched_warnings[source]) { emit_source_warnings(*universe.source_bindings[source],universe.prefetched_warnings[source]); universe.prefetched_warnings[source]=0; }
    return universe.plan.value(source);
}
// Preserves declaration-order range arbitration and weighted contributor arithmetic exactly.
PeravizVisualRuntimeCore::EvaluationResult PeravizVisualRuntimeCore::evaluate_property_value(UniverseState &universe, const CompiledPropertyProgram &property) {
    if (property.sources.size()>1 && property.range_selector) {
        EvaluationResult selected;
        for (uint32_t source:property.sources) {
            const auto value=evaluate_cached_source(universe,source);
            const auto &definition=universe.source_bindings[source]->program;
            if (!selected.valid && value.raw_value>=definition.dmx_from && value.raw_value<=definition.dmx_to) selected=value;
        }
        return selected;
    }
    EvaluationResult result;
    double normalized=0, physical=0, weight=0;
    for (size_t i=0;i<property.sources.size();++i) {
        const auto value=evaluate_cached_source(universe,property.sources[i]);
        if (!value.valid) continue;
        if (!result.valid) { result.raw_value=value.raw_value; result.active_program_id=value.active_program_id; result.valid=true; }
        const double contribution=property.property.contributors[i].weight;
        normalized+=double(value.normalized_value)*contribution;
        physical+=double(value.physical_value)*contribution;
        weight+=contribution;
    }
    if (weight==0 || !result.valid) return {};
    result.normalized_value=float(normalized/weight); result.physical_value=float(physical/weight);
    return result;
}
// Refreshes numeric values only; authoritative gobo activation/temporal mathematics stay unchanged.
void PeravizVisualRuntimeCore::fill_gobo_context(UniverseState &universe, GoboEvaluationContext &context) {
    for (size_t i=0;i<context.sources.size();++i) {
        const auto value=evaluate_cached_source(universe,context.sources[i]);
        context.values[i]={context.dependency_program_ids[i],value.raw_value};
    }
}
// Executes the existing cycle-safe ModeMaster evaluator once for each affected source context.
bool PeravizVisualRuntimeCore::evaluate_cached_activation(UniverseState &universe, GoboEvaluationContext &context) {
    const uint32_t source=context.sources.front();
    if (!universe.plan.activation_cached(source)) {
        fill_gobo_context(universe,context);
        const bool active=evaluate_gobo_source_activation(context.dependency_program_ids.front(),*context.programs,context.values);
        universe.plan.store_activation(source,active);
        if (performance_trace_enabled_) ++stats_.activation_programs_evaluated;
    } else if (performance_trace_enabled_) ++stats_.activation_cache_hits;
    return universe.plan.activation(source);
}
} // namespace peraviz::runtime
