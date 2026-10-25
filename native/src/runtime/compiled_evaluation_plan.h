#pragma once
#include "runtime/visual_runtime_types.h"
#include "runtime/ordered_dirty_indices.h"
#include <array>
#include <memory>
#include <unordered_map>

namespace peraviz::runtime {
// Immutable scalar mapping shared only after exact selected-mode/content comparison.
struct SourceValueMapping {
    uint32_t maximum = 255;
    double inverse_maximum = 1.0/255.0;
    double span = 255.0;
    double physical_from = 0, physical_to = 1;
};
struct EvaluatedSourceValue {
    uint32_t raw_value = 0;
    float normalized_value = 0, physical_value = 0;
    int32_t active_program_id = 0;
    bool valid = false;
};
enum class EvaluationDomain : uint8_t { Property, Color, Wheel, GoboSelection, GoboMotion };
struct EvaluationConsumer {
    EvaluationDomain domain;
    uint32_t index;
    int64_t target;
};
struct EvaluationSpan { uint32_t offset = 0, count = 0; };
struct EvaluationOffsetEntry {
    int32_t offset = 0;
    EvaluationSpan sources;
    uint32_t color_fanout = 0;
};
struct EvaluationSourceNode {
    const CompiledDmxSourceProgram *program = nullptr; // Borrowed immutable installed definition.
    int32_t master = -1;
    EvaluationSpan consumers;
    int32_t activation_slot = -1;
};
// Serial mutable workspace is instance-local. No Godot objects or physical state live here.
struct EvaluationWorkspace {
    std::vector<EvaluatedSourceValue> values;
    std::vector<uint8_t> invalid;
    std::vector<uint64_t> changed, activation_generations;
    std::vector<uint8_t> activations;
    std::vector<uint32_t> changed_sources;
    OrderedDirtyIndices consumers;
    uint64_t generation = 0;
};
// Compact source/activation/consumer graph; source decoding is fused with existing domain evaluators.
class CompiledEvaluationPlan {
public:
    void install(const std::vector<const CompiledDmxSourceProgram *> &programs,
            std::vector<CompiledRuntimeDiagnostic> &diagnostics);
    uint32_t source_index(int32_t program_id) const;
    void add_consumer(EvaluationDomain domain, uint32_t index, int64_t target,
            const std::vector<uint32_t> &sources, bool activation_dependencies);
    void finish_install();
    void begin_update(const std::vector<int> &offsets);
    // Borrows the deduplicated source invalidation prefix for pure native worker preparation.
    const std::vector<uint32_t> &changed_sources() const { return workspace_.changed_sources; }
    // Borrows deterministic consumer nominations until the next update.
    OrderedDirtyIndices &dirty_consumers() { return workspace_.consumers; }
    // Borrows the installed domain and canonical target binding.
    const EvaluationConsumer &consumer(uint32_t index) const { return consumers_[index]; }
    // Borrows a source definition and its dependency edge.
    const EvaluationSourceNode &source(uint32_t index) const { return sources_[index]; }
    bool source_changed(uint32_t index) const;
    bool needs_evaluation(uint32_t index) const;
    const EvaluatedSourceValue &value(uint32_t index) const;
    void store(uint32_t index, const EvaluatedSourceValue &value);
    bool activation_cached(uint32_t index) const;
    bool activation(uint32_t index) const;
    void store_activation(uint32_t index, bool active);
    // Counts dense source handles independently of physical output fan-out.
    size_t source_count() const { return sources_.size(); }
    // Counts existing domain programs and optical layers scheduled by this plan.
    size_t consumer_count() const { return consumers_.size(); }
    uint32_t color_offset_fanout(int offset) const;
    size_t dependency_count() const;
    size_t immutable_bytes() const;
    size_t workspace_bytes() const;
private:
    std::vector<EvaluationSourceNode> sources_;
    std::vector<EvaluationConsumer> consumers_;
    std::unordered_map<int32_t,uint32_t> source_by_id_; // Setup lookup, never playback discovery.
    std::vector<EvaluationOffsetEntry> offsets_;
    std::vector<uint32_t> offset_sources_, source_consumers_;
    std::vector<std::vector<uint32_t>> building_consumers_; // Released after compaction.
    EvaluationWorkspace workspace_;
};
} // namespace peraviz::runtime
