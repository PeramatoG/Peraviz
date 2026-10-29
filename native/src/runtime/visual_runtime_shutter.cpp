#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>
#include <set>

namespace peraviz::runtime {
namespace {
// Encodes a physical target plus numbered shutter without conflating independent cells.
int64_t shutter_key(int32_t target,int32_t index) { return (int64_t(target)<<32)|uint32_t(index); }
// Publishes persistent parameters only; no flash generates a semantic snapshot.
void append_shutter_row(SectionedVisualFrame &frame,int fixture,int target,int index,
        const gdtf_runtime::ShutterParameters &p,double now) {
    const int io=int(frame.integers.size()),fo=int(frame.floats.size());
    frame.integers.insert(frame.integers.end(),{fixture,target,index,int(p.wave),p.revision,p.status,p.function_id,p.activation});
    frame.floats.insert(frame.floats.end(),{float(p.frequency),float(p.duration),float(p.duty),float(p.offset),
        float(p.phase),float(p.reference),float(now)});
    auto &d=frame.descriptors;
    if (d.size()>=5 && d[d.size()-5]==int32_t(VisualSectionType::ShutterState)) ++d[d.size()-4];
    else d.insert(d.end(),{int32_t(VisualSectionType::ShutterState),1,io,fo,0});
}
}
// Installs source-graph activation contexts once, refusing unresolved or cross-universe layers explicitly.
void PeravizVisualRuntimeCore::install_shutters(const CompiledRuntimeScene &scene,VisualFrameSchemaCapabilities &capabilities) {
    struct Pending { CompiledShutterBinding binding; int universe=-1; std::vector<int32_t> ids; std::vector<int> offsets; };
    std::vector<Pending> pending;
    std::unordered_map<int64_t,int> universe_by_layer;
    std::set<int64_t> invalid;
    for (const auto &binding:scene.shutter_bindings) {
        const auto key=shutter_key(binding.beam_target_id,binding.shutter_index);
        Pending entry; entry.binding=binding;
        int32_t id=binding.source_program_id;
        std::set<int32_t> visited;
        bool valid=binding.fixture_id>0 && binding.beam_target_id>0 && binding.shutter_index>0;
        while (id>0 && visited.insert(id).second) {
            const auto found=source_programs_by_id_.find(id);
            if (found==source_programs_by_id_.end() || found->second.program.sources.empty()) { valid=false; break; }
            for (const auto &byte:found->second.program.sources) {
                if (entry.universe<0) entry.universe=byte.universe_id;
                if (entry.universe!=byte.universe_id) valid=false;
                entry.offsets.push_back(byte.address);
            }
            entry.ids.push_back(id);
            const auto &condition=found->second.program.activation;
            id=condition.target_kind==gdtf_runtime::ModeMasterTargetKind::None ? 0 : condition.master_program_id;
        }
        if (id>0 || entry.universe<0) valid=false;
        const auto owner=universe_by_layer.emplace(key,entry.universe);
        if (!owner.second && owner.first->second!=entry.universe) valid=false;
        if (!valid) invalid.insert(key);
        pending.push_back(std::move(entry));
    }
    std::set<int32_t> reported;
    for (const auto &entry:pending) if (invalid.count(shutter_key(entry.binding.beam_target_id,entry.binding.shutter_index)) && reported.insert(entry.binding.fixture_id).second)
        diagnostics_.push_back({"PVZ-SHUTTER-ACTIVATION-UNRESOLVED","warning",
            "Shutter parameters/ModeMaster must resolve within one universe; unresolved layers stay open.",std::to_string(entry.binding.fixture_id)});
    for (auto &entry:pending) {
        const auto &binding=entry.binding;
        const auto key=shutter_key(binding.beam_target_id,binding.shutter_index);
        if (invalid.count(key)) continue;
        auto &universe=universes_[entry.universe];
        ShutterBindingRuntime context; context.binding=binding; context.dependency_program_ids=std::move(entry.ids);
        universe.shutter_layers[key].push_back(int(universe.shutters.size()));
        universe.shutters.push_back(std::move(context));
        universe.interest_offsets.insert(universe.interest_offsets.end(),entry.offsets.begin(),entry.offsets.end());
        shutter_states_[key]={binding.fixture_id,binding.beam_target_id,binding.shutter_index,false,{}};
        installed_visual_mask_by_fixture_[binding.fixture_id]|=VisualChangeStrobe;
        capabilities.has_shutter=true;
    }
}
// Selects effective functions through the existing source cache and cycle-safe ModeMaster evaluator.
void PeravizVisualRuntimeCore::evaluate_shutters(UniverseState &universe,SectionedVisualFrame &frame) {
    using namespace gdtf_runtime;
    if (universe.dirty_shutters.empty()) return;
    const double now=runtime_now_seconds();
    for (int64_t key:universe.dirty_shutters) {
        auto &held=shutter_states_.at(key);
        ShutterParameters next; next.seed=uint32_t(held.target_id);
        int active=0,durations=0;
        double duration=0.025;
        for (int index:universe.shutter_layers.at(key)) {
            auto &context=universe.shutters[index];
            const auto value=evaluate_cached_source(universe,context.sources.front());
            const auto &binding=context.binding;
            if (!evaluate_cached_activation(universe,context) || value.raw_value<binding.dmx_from || value.raw_value>binding.dmx_to) continue;
            if (binding.mode_from || binding.mode_to!=UINT32_MAX) {
                if (context.sources.size()<2) continue;
                const auto mode=evaluate_cached_source(universe,context.sources[1]).raw_value;
                if (mode<binding.mode_from || mode>binding.mode_to) continue;
            }
            const double local=binding.dmx_to>binding.dmx_from ? double(value.raw_value-binding.dmx_from)/double(binding.dmx_to-binding.dmx_from) : 0;
            const double physical=binding.physical_from+local*(binding.physical_to-binding.physical_from);
            if (binding.wave==ShutterWave::Duration) { duration=physical; ++durations; continue; }
            ++active; next.wave=binding.wave; next.function_id=binding.activation_function_id?binding.activation_function_id:binding.source_program_id;
            next.frequency=shutter_periodic(binding.wave)?physical:0;
            next.duration=binding.duration; next.duty=binding.duty; next.offset=binding.offset; next.status=binding.status;
        }
        if (durations) next.duration=duration;
        if (active>1 || durations>1 || !std::isfinite(float(next.frequency)) || !std::isfinite(float(next.duration)) || !std::isfinite(float(next.duty)) || !std::isfinite(float(next.offset)) || next.duration<0 ||
                (shutter_periodic(next.wave) && next.frequency<0)) {
            next.wave=ShutterWave::Unsupported; next.status=2;
            next.frequency=0; next.duration=0.025; next.duty=1; next.offset=1;
            if (!held.diagnosed && shutter_unsupported_fixtures_.insert(held.fixture_id).second) diagnostics_.push_back({"PVZ-SHUTTER-STATE-UNSUPPORTED","warning","Ambiguous/invalid shutter state remains open; no periodic approximation is inferred.",std::to_string(held.target_id)});
        }
        if (next.status==2) held.diagnosed=true;
        if (update_shutter(held.parameters,next,now)) append_shutter_row(frame,held.fixture_id,held.target_id,held.index,held.parameters,now);
    }
}
// Rehydrates persistent parameters after renderer retirement without changing activation or phase.
void PeravizVisualRuntimeCore::replay_shutters(SectionedVisualFrame &frame) const {
    const double now=runtime_now_seconds();
    for (const auto &[key,state]:shutter_states_) if (state.parameters.revision)
        append_shutter_row(frame,state.fixture_id,state.target_id,state.index,state.parameters,now);
}
// Reads only cached evaluated state for a selected fixture/output, capped at 64 rows and never per flash.
std::vector<ShutterTrace> PeravizVisualRuntimeCore::shutter_trace(int32_t fixture,int32_t target) const {
    std::vector<ShutterTrace> result;
    if (fixture<=0) return result;
    for (const auto &[id,universe]:universes_) for (const auto &context:universe.shutters) {
        const auto &b=context.binding;
        if (b.fixture_id!=fixture || (target && b.beam_target_id!=target) || result.size()>=64) continue;
        const auto source=context.sources.front(); const auto &value=universe.plan.value(source);
        const auto &program=source_programs_by_id_.at(b.source_program_id).program;
        const auto &state=shutter_states_.at(shutter_key(b.beam_target_id,b.shutter_index));
        ShutterTrace row; row.fixture=fixture; row.target=b.beam_target_id; row.index=b.shutter_index; row.source=b.source_program_id;
        row.from=b.dmx_from; row.to=b.dmx_to; row.raw=value.raw_value; row.bytes=int32_t(program.sources.size());
        row.physical_from=b.physical_from; row.physical_to=b.physical_to; row.initialized=state.parameters.revision>0 && value.valid;
        row.active=row.initialized && universe.plan.activation_cached(source) && universe.plan.activation(source) && row.raw>=row.from && row.raw<=row.to;
        row.physical=b.physical_from+(b.physical_to-b.physical_from)*(b.dmx_to>b.dmx_from?double(std::clamp(row.raw,b.dmx_from,b.dmx_to)-b.dmx_from)/double(b.dmx_to-b.dmx_from):0);
        row.mode_from=b.mode_from; row.mode_to=b.mode_to; row.activation_function_id=b.activation_function_id;
        if (context.sources.size()>1) row.master_raw=universe.plan.value(context.sources[1]).raw_value;
        if (row.mode_from || row.mode_to!=UINT32_MAX) {
            const bool guarded=context.sources.size()>1;
            const auto mode=guarded?universe.plan.value(context.sources[1]).raw_value:0;
            row.active&=guarded && mode>=row.mode_from && mode<=row.mode_to;
        }
        row.parameters=state.parameters; result.push_back(row);
    }
    return result;
}

}
