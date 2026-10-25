#include "runtime/parallel_evaluation_prefetch.h"
#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>
#include <chrono>
#include <unordered_map>

namespace peraviz::runtime {
struct ParallelEvaluationPrefetch::Impl {
    using Core=PeravizVisualRuntimeCore;
    struct SourceSlot { EvaluatedSourceValue value; uint64_t generation=0; uint8_t warnings=0; };
    struct ColorSlot { std::vector<float> values; CookedEmitterColorValue cooked,final; uint64_t generation=0; bool changed=false,no_wheels=false; };
    struct Universe {
        int id=0;
        Core::UniverseState *state=nullptr;
        bool inputs_prepared=false;
        std::vector<SourceSlot> source_slots;
        std::vector<ColorSlot> color_slots;
        std::vector<std::pair<int32_t,uint32_t>> color_indices;
    };
    struct Job { Universe *universe; uint32_t index; };
    Core &core;
    NativeBatchExecutor &executor;
    std::vector<Universe> universes;
    std::unordered_map<int,size_t> lookup;
    std::vector<Job> source_jobs,color_jobs;
    uint64_t generation=0;
    bool prepared=false,observe=false;
    uint64_t observation_start=0,cooldown=0,observations=0;
    double serial_ns_per_unit=0,parallel_ns_per_unit=0;
    ParallelEvaluationMetrics metrics;
    // Binds stable scene definitions once and allocates all pure worker result ranges.
    Impl(Core &value,NativeBatchExecutor &worker):core(value),executor(worker) {
        universes.reserve(core.universes_.size());
        size_t sources=0,colors=0;
        for (auto &[id,state]:core.universes_) {
            Universe universe; universe.id=id; universe.state=&state;
            universe.source_slots.resize(state.plan.source_count()); universe.color_slots.resize(state.color_targets.size());
            for (size_t i=0;i<state.color_targets.size();++i) {
                universe.color_slots[i].values.resize(state.color_targets[i].inputs.size());
                const int32_t target=state.color_targets[i].target.beam_render_target_id;
                universe.color_slots[i].no_wheels=core.ordered_wheel_layers_.find(target)==core.ordered_wheel_layers_.end();
                universe.color_indices.push_back({target,uint32_t(i)});
            }
            std::sort(universe.color_indices.begin(),universe.color_indices.end());
            sources+=state.plan.source_count(); colors+=state.color_targets.size();
            lookup.emplace(id,universes.size()); universes.push_back(std::move(universe));
        }
        source_jobs.reserve(sources); color_jobs.reserve(colors);
    }
    // Writes only designated source slots; neither diagnostics nor authoritative plan caches are touched.
    static void evaluate_sources(void *context,size_t begin,size_t end) {
        auto &self=*static_cast<Impl *>(context);
        for (size_t i=begin;i<end;++i) {
            const auto job=self.source_jobs[i]; auto &state=*job.universe->state;
            auto &slot=job.universe->source_slots[job.index];
            slot.value=Core::evaluate_source_program(state.latest_frame,*state.source_bindings[job.index],nullptr,&slot.warnings);
            slot.generation=self.generation;
        }
    }
    // Reads completed source slots and immutable Color/resources, then writes one exclusive Color slot.
    static void evaluate_colors(void *context,size_t begin,size_t end) {
        auto &self=*static_cast<Impl *>(context);
        for (size_t i=begin;i<end;++i) {
            const auto job=self.color_jobs[i]; const auto &target=job.universe->state->color_targets[job.index];
            auto &slot=job.universe->color_slots[job.index]; slot.changed=false;
            for (size_t j=0;j<target.inputs.size();++j) {
                const auto &input=target.inputs[j]; const auto &source=job.universe->source_slots[input.source];
                float value=input.value;
                if (source.generation==self.generation) value=Core::color_value_from_evaluation(input.binding.semantic,source.value);
                slot.values[j]=value;
                slot.changed=slot.changed || !input.initialized || !Core::nearly_equal(input.value,value,0.0001f);
            }
            if (slot.changed) {
                slot.cooked=self.core.cook_emitter_color(target,slot.values.data());
                // No wheel state is read: this is the same exact final Color kernel with an immutable base override.
                if (slot.no_wheels) slot.final=self.core.compose_ordered_target_color(target.target.beam_render_target_id,&slot.cooked);
            }
            slot.generation=self.generation;
        }
    }
    // Samples retained worker scratch without attributing it to canonical physical state.
    size_t bytes() const {
        size_t count=(source_jobs.capacity()+color_jobs.capacity())*sizeof(Job);
        for (const auto &universe:universes) {
            count+=universe.source_slots.capacity()*sizeof(SourceSlot)+universe.color_slots.capacity()*sizeof(ColorSlot)+universe.color_indices.capacity()*sizeof(std::pair<int32_t,uint32_t>);
            for (const auto &slot:universe.color_slots) count+=slot.values.capacity()*sizeof(float);
        }
        return count;
    }
    // Keeps overlapping worker CPU separate from stage wall time and coordination residuals.
    void add(const NativeBatchMetrics &value) {
        metrics.tasks+=value.tasks; metrics.worker_cpu_ns+=value.worker_cpu_ns; metrics.task_wall_ns+=value.wall_ns;
        metrics.coordination_ns+=value.coordination_ns; metrics.failures+=value.failures;
        metrics.workers_used=std::max(metrics.workers_used,value.workers_used);
    }
};
// Allocates scene-bound pure scratch before any worker may borrow definitions.
ParallelEvaluationPrefetch::ParallelEvaluationPrefetch(PeravizVisualRuntimeCore &core,NativeBatchExecutor &executor):impl_(std::make_unique<Impl>(core,executor)) {}
// Releases scratch only after the scene's coordinator and worker barriers have retired.
ParallelEvaluationPrefetch::~ParallelEvaluationPrefetch() = default;
// Prepares independent source and Color phases; all canonical maps remain exclusively coordinator-owned.
void ParallelEvaluationPrefetch::prepare() {
    auto &p=*impl_;
    p.observation_start=uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
    p.observe=false; p.prepared=false; p.metrics={}; p.source_jobs.clear(); p.color_jobs.clear();
    if (++p.generation==0) {
        for (auto &universe:p.universes) {
            for (auto &slot:universe.source_slots) slot.generation=0;
            for (auto &slot:universe.color_slots) slot.generation=0;
        }
        ++p.generation;
    }
    for (auto &universe:p.universes) {
        auto &state=*universe.state;
        universe.inputs_prepared=state.has_pending_frame;
        if (!state.has_pending_frame) continue;
        auto &offsets=state.changed_offsets; offsets.clear();
        for (int offset:state.interest_offsets) {
            const auto value=offset>=0 && size_t(offset)<state.latest_frame.size()?state.latest_frame[size_t(offset)]:0;
            if (!state.has_last_relevant_values || value!=state.last_relevant_values[size_t(offset)]) {
                offsets.push_back(offset); state.last_relevant_values[size_t(offset)]=value;
            }
        }
        state.has_last_relevant_values=true;
        state.plan.begin_update(offsets);
        for (uint32_t source:state.plan.changed_sources()) if (state.plan.source(source).consumers.count) p.source_jobs.push_back({&universe,source});
        for (int consumer:state.plan.dirty_consumers()) {
            const auto &binding=state.plan.consumer(uint32_t(consumer));
            if (binding.domain==EvaluationDomain::Color) p.color_jobs.push_back({&universe,binding.index});
        }
    }
    p.metrics.work_units=p.source_jobs.size()+p.color_jobs.size()*8;
    // Small updates retain lazy serial evaluation. Large updates periodically compare full native commits.
    const bool useful=p.executor.worthwhile(p.source_jobs.size(),1024) || p.executor.worthwhile(p.color_jobs.size(),256);
    if (!useful) { p.metrics.serial_batches=1; p.metrics.retained_bytes=p.bytes(); return; }
    p.observe=!p.executor.forced();
    if (!p.executor.forced() && (!p.serial_ns_per_unit || p.cooldown || ++p.observations%64==0)) {
        p.metrics.serial_batches=1; p.metrics.serial_probes=1;
        if (p.cooldown) { --p.cooldown; p.metrics.policy_backoffs=1; }
        p.metrics.retained_bytes=p.bytes(); return;
    }
    const auto source=p.executor.run(p.source_jobs.size(),1024,Impl::evaluate_sources,&p,p.core.performance_trace_enabled_);
    p.add(source);
    const auto color=p.executor.run(p.color_jobs.size(),256,Impl::evaluate_colors,&p,p.core.performance_trace_enabled_);
    p.add(color);
    p.prepared=true; p.metrics.parallel_batches=(source.parallel || color.parallel)?1:0;
    p.metrics.serial_batches=p.metrics.parallel_batches?0:1; p.metrics.retained_bytes=p.bytes();
    if (p.core.performance_trace_enabled_) p.core.stats_.source_programs_evaluated+=p.source_jobs.size();
}
// Learns from complete native evaluation wall time, not just isolated worker kernels or overlapping CPU timers.
void ParallelEvaluationPrefetch::observe_completion() {
    auto &p=*impl_;
    if (!p.observe || !p.metrics.work_units) return;
    const auto end=uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
    const double per_unit=double(end-p.observation_start)/double(p.metrics.work_units);
    if (!p.metrics.parallel_batches) p.serial_ns_per_unit=p.serial_ns_per_unit?p.serial_ns_per_unit*0.75+per_unit*0.25:per_unit;
    else {
        p.parallel_ns_per_unit=p.parallel_ns_per_unit?p.parallel_ns_per_unit*0.75+per_unit*0.25:per_unit;
        if (p.serial_ns_per_unit && p.parallel_ns_per_unit>p.serial_ns_per_unit*1.05) p.cooldown=16;
    }
}
// Reuses the coordinator's single input/dependency-discovery pass for both worker and serial commits.
bool ParallelEvaluationPrefetch::inputs_prepared(int universe_id) const {
    const auto found=impl_->lookup.find(universe_id);
    return found!=impl_->lookup.end() && impl_->universes[found->second].inputs_prepared;
}
// Installs complete source values and deferred warnings at the original deterministic native boundary.
void ParallelEvaluationPrefetch::inject_sources(int universe_id) {
    auto &p=*impl_; if (!p.prepared) return;
    const auto found=p.lookup.find(universe_id); if (found==p.lookup.end()) return;
    auto &universe=p.universes[found->second];
    for (uint32_t source:universe.state->plan.changed_sources()) {
        const auto &slot=universe.source_slots[size_t(source)];
        if (slot.generation!=p.generation) continue;
        universe.state->plan.store(uint32_t(source),slot.value);
        universe.state->prefetched_warnings[size_t(source)]=slot.warnings;
    }
}
// Commits already evaluated input values in declaration order without repeating worker Color arithmetic.
bool ParallelEvaluationPrefetch::commit_color_inputs(int universe_id,size_t target_index,bool &changed) {
    auto &p=*impl_; if (!p.prepared) return false;
    const auto found=p.lookup.find(universe_id); if (found==p.lookup.end()) return false;
    auto &universe=p.universes[found->second]; auto &slot=universe.color_slots[target_index];
    if (slot.generation!=p.generation) return false;
    auto &target=universe.state->color_targets[target_index]; changed=slot.changed;
    for (size_t i=0;i<target.inputs.size();++i) {
        auto &input=target.inputs[i];
        if (input.initialized && !universe.state->plan.source_changed(input.source)) continue;
        auto &warning=universe.state->prefetched_warnings[input.source];
        if (warning) { p.core.emit_source_warnings(*universe.state->source_bindings[input.source],warning); warning=0; }
        input.value=slot.values[i]; input.initialized=true;
        ++p.core.stats_.color_inputs_evaluated;
        if (p.core.performance_trace_enabled_) ++p.core.stats_.source_cache_hits;
    }
    return true;
}
// Borrows only a complete result from the matching frozen input generation.
bool ParallelEvaluationPrefetch::cooked_color(int universe_id,size_t target,CookedEmitterColorValue &output) const {
    const auto &p=*impl_; if (!p.prepared) return false;
    const auto found=p.lookup.find(universe_id); if (found==p.lookup.end()) return false;
    const auto &slot=p.universes[found->second].color_slots[target];
    if (slot.generation!=p.generation || !slot.changed) return false;
    output=slot.cooked; return true;
}
// Reuses final Color only when no optical dependency exists; shared canonical targets retain last-changed declaration order.
bool ParallelEvaluationPrefetch::final_color(int universe_id,int32_t target,CookedEmitterColorValue &output) const {
    const auto &p=*impl_; if (!p.prepared) return false;
    const auto found=p.lookup.find(universe_id); if (found==p.lookup.end()) return false;
    const auto &universe=p.universes[found->second];
    const auto upper=std::upper_bound(universe.color_indices.begin(),universe.color_indices.end(),target,
        [](int32_t id,const auto &entry) { return id<entry.first; });
    auto cursor=upper;
    while (cursor!=universe.color_indices.begin()) {
        --cursor; if (cursor->first!=target) break;
        const auto &slot=universe.color_slots[cursor->second];
        if (slot.generation==p.generation && slot.changed && slot.no_wheels) { output=slot.final; return true; }
    }
    return false;
}
// Reports bounded native work and scratch independently from renderer resource mutation.
ParallelEvaluationMetrics ParallelEvaluationPrefetch::metrics() const { return impl_->metrics; }
} // namespace peraviz::runtime
