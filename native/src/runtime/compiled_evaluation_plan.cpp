#include "runtime/compiled_evaluation_plan.h"
#include <algorithm>
#include <limits>

namespace peraviz::runtime {
// Binds existing source identities and validates activation edges once, without copying definitions.
void CompiledEvaluationPlan::install(const std::vector<const CompiledDmxSourceProgram *> &programs,
        std::vector<CompiledRuntimeDiagnostic> &diagnostics) {
    *this={};
    sources_.reserve(programs.size());
    for (const auto *program:programs) {
        source_by_id_.emplace(program->program_id,uint32_t(sources_.size()));
        sources_.push_back({program,-1,{}});
    }
    std::array<std::vector<uint32_t>,512> by_offset;
    for (uint32_t i=0;i<sources_.size();++i) {
        auto &node=sources_[i];
        for (const auto &byte:node.program->sources)
            if (byte.address>=0 && byte.address<512) by_offset[byte.address].push_back(i);
        const auto &condition=node.program->activation;
        if (condition.target_kind!=gdtf_runtime::ModeMasterTargetKind::None) {
            const auto master=source_by_id_.find(condition.master_program_id);
            if (master!=source_by_id_.end()) node.master=int32_t(master->second);
            else diagnostics.push_back({"PVZ-EVALUATION-MISSING-MASTER","warning","Evaluation source has no installed same-universe ModeMaster.",std::to_string(node.program->program_id)});
        }
    }
    // Each node has at most one master. Bound walks also reject malformed imported cycles.
    std::vector<uint8_t> state(sources_.size(),0);
    std::vector<uint32_t> path;
    for (uint32_t i=0;i<sources_.size();++i) {
        path.clear(); int32_t cursor=int32_t(i);
        while (cursor>=0 && state[cursor]==0) { state[cursor]=1; path.push_back(uint32_t(cursor)); cursor=sources_[cursor].master; }
        if (cursor>=0 && state[cursor]==1) diagnostics.push_back({"PVZ-EVALUATION-CYCLIC-MASTER","warning","Cyclic evaluation activation dependency remains inactive in the authoritative activation evaluator.",std::to_string(sources_[cursor].program->program_id)});
        for (uint32_t index:path) state[index]=2;
    }
    for (size_t offset=0;offset<512;++offset) {
        auto &indices=by_offset[offset];
        std::sort(indices.begin(),indices.end()); indices.erase(std::unique(indices.begin(),indices.end()),indices.end());
        if (!indices.empty()) offsets_.push_back({int32_t(offset),{uint32_t(offset_sources_.size()),uint32_t(indices.size())},0});
        offset_sources_.insert(offset_sources_.end(),indices.begin(),indices.end());
    }
    building_consumers_.resize(sources_.size());
}
// Resolves canonical source IDs only during installation.
uint32_t CompiledEvaluationPlan::source_index(int32_t program_id) const {
    const auto it=source_by_id_.find(program_id);
    return it==source_by_id_.end()?std::numeric_limits<uint32_t>::max():it->second;
}
// Compiles direct or activation-cascade dependencies into exact consumer adjacency.
void CompiledEvaluationPlan::add_consumer(EvaluationDomain domain, uint32_t index, int64_t target,
        const std::vector<uint32_t> &sources, bool activation_dependencies) {
    const uint32_t consumer=uint32_t(consumers_.size());
    consumers_.push_back({domain,index,target});
    for (uint32_t source:sources) {
        if (activation_dependencies && source<sources_.size() && sources_[source].activation_slot<0) {
            sources_[source].activation_slot=int32_t(workspace_.activations.size());
            workspace_.activations.push_back(0); workspace_.activation_generations.push_back(0);
        }
        int32_t cursor=source<sources_.size()?int32_t(source):-1;
        std::vector<int32_t> path;
        while (cursor>=0 && std::find(path.begin(),path.end(),cursor)==path.end()) {
            if (activation_dependencies) path.push_back(cursor);
            building_consumers_[cursor].push_back(consumer);
            cursor=activation_dependencies?sources_[cursor].master:-1;
        }
    }
}
// Freezes adjacency and allocates the only mutable source-result workspace.
void CompiledEvaluationPlan::finish_install() {
    for (size_t i=0;i<sources_.size();++i) {
        auto &edges=building_consumers_[i];
        std::sort(edges.begin(),edges.end()); edges.erase(std::unique(edges.begin(),edges.end()),edges.end());
        sources_[i].consumers={uint32_t(source_consumers_.size()),uint32_t(edges.size())};
        source_consumers_.insert(source_consumers_.end(),edges.begin(),edges.end());
    }
    for (auto &offset:offsets_) {
        for (uint32_t i=offset.sources.offset;i<offset.sources.offset+offset.sources.count;++i) {
            const auto edges=sources_[offset_sources_[i]].consumers;
            for (uint32_t j=edges.offset;j<edges.offset+edges.count;++j)
                offset.color_fanout+=consumers_[source_consumers_[j]].domain==EvaluationDomain::Color;
        }
    }
    decltype(building_consumers_)().swap(building_consumers_);
    decltype(source_by_id_)().swap(source_by_id_);
    workspace_.changed_sources.reserve(sources_.size());
    workspace_.values.resize(sources_.size()); workspace_.invalid.assign(sources_.size(),1);
    workspace_.changed.assign(sources_.size(),0); workspace_.consumers.install(consumers_.size());
}
// Schedules only offset-reachable consumers; cached scalar results survive unrelated updates.
void CompiledEvaluationPlan::begin_update(const std::vector<int> &offsets) {
    workspace_.consumers.clear(); workspace_.changed_sources.clear();
    if (++workspace_.generation==0) {
        std::fill(workspace_.changed.begin(),workspace_.changed.end(),0);
        std::fill(workspace_.activation_generations.begin(),workspace_.activation_generations.end(),0);
        ++workspace_.generation;
    }
    for (int offset:offsets) {
        if (offset<0 || offset>=512) continue;
        const auto found=std::lower_bound(offsets_.begin(),offsets_.end(),offset,
                [](const auto &entry,int value) { return entry.offset<value; });
        if (found==offsets_.end() || found->offset!=offset) continue;
        const auto span=found->sources;
        for (uint32_t p=span.offset;p<span.offset+span.count;++p) {
            const uint32_t source=offset_sources_[p];
            if (workspace_.changed[source]==workspace_.generation) continue;
            workspace_.changed[source]=workspace_.generation; workspace_.invalid[source]=1;
            workspace_.changed_sources.push_back(source);
            const auto edges=sources_[source].consumers;
            workspace_.consumers.insert(source_consumers_.begin()+edges.offset,source_consumers_.begin()+edges.offset+edges.count);
        }
    }
}
// Distinguishes dirty source bytes from a cache filled earlier by another consumer.
bool CompiledEvaluationPlan::source_changed(uint32_t index) const { return workspace_.changed[index]==workspace_.generation; }
// Returns whether decoding is required in this instance's current DMX context.
bool CompiledEvaluationPlan::needs_evaluation(uint32_t index) const { return workspace_.invalid[index]!=0; }
// Borrows a previously evaluated value without duplicating physical target state.
const EvaluatedSourceValue &CompiledEvaluationPlan::value(uint32_t index) const { return workspace_.values[index]; }
// Commits a complete scalar result for all consumers sharing this source handle.
void CompiledEvaluationPlan::store(uint32_t index, const EvaluatedSourceValue &value) { workspace_.values[index]=value; workspace_.invalid[index]=0; }
// Reports whether an activation cascade already completed in this relevant update.
bool CompiledEvaluationPlan::activation_cached(uint32_t index) const {
    const int32_t slot=sources_[index].activation_slot;
    return slot>=0 && workspace_.activation_generations[slot]==workspace_.generation;
}
// Borrows the authoritative activation result shared by identical source contexts.
bool CompiledEvaluationPlan::activation(uint32_t index) const { return workspace_.activations[sources_[index].activation_slot]!=0; }
// Publishes a complete activation result after all cached master values are available.
void CompiledEvaluationPlan::store_activation(uint32_t index, bool active) {
    const int32_t slot=sources_[index].activation_slot;
    workspace_.activations[slot]=active; workspace_.activation_generations[slot]=workspace_.generation;
}
// Returns precompiled color nomination fan-out without reconstructing playback lookup tables.
uint32_t CompiledEvaluationPlan::color_offset_fanout(int offset) const {
    const auto found=std::lower_bound(offsets_.begin(),offsets_.end(),offset,
            [](const auto &entry,int value) { return entry.offset<value; });
    return found!=offsets_.end() && found->offset==offset?found->color_fanout:0;
}
// Counts offset, activation and consumer edges for opt-in diagnostics.
size_t CompiledEvaluationPlan::dependency_count() const {
    size_t count=offset_sources_.size()+source_consumers_.size();
    for (const auto &source:sources_) count+=source.master>=0;
    return count;
}
// Reports retained compact adjacency buffers; setup lookup hashes have already been released.
size_t CompiledEvaluationPlan::immutable_bytes() const {
    return offsets_.capacity()*sizeof(EvaluationOffsetEntry)+sources_.capacity()*sizeof(EvaluationSourceNode)+consumers_.capacity()*sizeof(EvaluationConsumer)+
        (offset_sources_.capacity()+source_consumers_.capacity())*sizeof(uint32_t);
}
// Reports retained mutable workspace storage independently from immutable definitions.
size_t CompiledEvaluationPlan::workspace_bytes() const {
    return workspace_.values.capacity()*sizeof(EvaluatedSourceValue)+workspace_.invalid.capacity()+
        (workspace_.changed.capacity()+workspace_.activation_generations.capacity())*sizeof(uint64_t)+workspace_.activations.capacity()+workspace_.changed_sources.capacity()*sizeof(uint32_t)+workspace_.consumers.buffer_bytes();
}
} // namespace peraviz::runtime
