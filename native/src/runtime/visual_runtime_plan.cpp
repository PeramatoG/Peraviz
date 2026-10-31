#include "runtime/peraviz_visual_runtime.h"
#include <algorithm>
#include <map>
#include <set>

namespace peraviz::runtime {
namespace {
// Encodes exact scalar-definition content without conflating patch addresses or floating point revisions.
template<class T> void append_key(std::string &key, const T &value) {
    key.append(reinterpret_cast<const char *>(&value),sizeof(value));
}
// Preserves string field boundaries in the scene-local immutable-definition key.
void append_text(std::string &key, const std::string &value) {
    append_key(key,value.size()); key+=value;
}
}
// Interns exact selected-mode scalar definitions while retaining instance-owned addresses and IDs.
void PeravizVisualRuntimeCore::install_source_mappings(const CompiledRuntimeScene &scene) {
    std::unordered_map<int32_t,const CompiledFixtureInstance *> fixtures;
    std::unordered_map<int32_t,int32_t> owners;
    for (const auto &fixture:scene.fixtures) fixtures.emplace(fixture.fixture_id,&fixture);
    for (const auto &property:scene.properties) for (const auto &input:property.contributors) owners.emplace(input.source_program_id,property.fixture_id);
    for (const auto &target:scene.color_targets) for (const auto &input:target.inputs) owners.emplace(input.source_program_id,target.fixture_id);
    for (const auto &binding:scene.wheel_bindings) owners.emplace(binding.source_program_id,binding.fixture_id);
    for (const auto &binding:scene.gobo_bindings) owners.emplace(binding.source_program_id,binding.fixture_id);
    for (const auto &binding:scene.gobo_motion_bindings) owners.emplace(binding.source_program_id,binding.fixture_id);
    for (const auto &binding:scene.shutter_bindings) owners.emplace(binding.source_program_id,binding.fixture_id);
    std::vector<std::pair<int32_t,int32_t>> ownership(owners.begin(),owners.end());
    for (size_t i=0;i<ownership.size();++i) {
        const auto source=source_programs_by_id_.find(ownership[i].first);
        if (source==source_programs_by_id_.end()) continue;
        const int32_t master=source->second.program.activation.master_program_id;
        if (master>0 && owners.emplace(master,ownership[i].second).second) ownership.push_back({master,ownership[i].second});
    }
    std::map<std::string,std::shared_ptr<const SourceValueMapping>> definitions;
    std::map<int32_t,std::map<int32_t,std::string>> fixture_source_content;
    for (auto &[id,installed]:source_programs_by_id_) {
        const auto &program=installed.program;
        std::string key;
        const auto owner=owners.find(id);
        const auto fixture=owner==owners.end()?fixtures.end():fixtures.find(owner->second);
        append_text(key,fixture==fixtures.end()?std::string():fixture->second->fixture_type_name);
        append_text(key,fixture==fixtures.end()?std::string():fixture->second->dmx_mode_name);
        append_key(key,program.semantic); append_key(key,program.dmx_from); append_key(key,program.dmx_to);
        append_key(key,program.physical_from); append_key(key,program.physical_to);
        append_text(key,program.attribute_name); append_text(key,program.function_name);
        append_text(key,program.geometry_name); append_text(key,program.color_space_name);
        const auto &activation=program.activation;
        append_key(key,activation.target_kind); append_key(key,activation.from); append_key(key,activation.to);
        append_key(key,activation.valid); append_key(key,activation.master_byte_count); append_text(key,activation.source_link);
        append_key(key,program.sources.size());
        for (const auto &source:program.sources) {
            const int universe=source.universe_id-program.sources.front().universe_id;
            const int address=source.address-program.sources.front().address;
            append_key(key,universe); append_key(key,address); append_key(key,source.byte_order);
        }
        if (fixture!=fixtures.end()) {
            std::string content=key;
            for (const auto &source:program.sources) {
                const int relative_universe=source.universe_id-fixture->second->universe_id;
                const int relative_address=source.address-(fixture->second->start_address-1);
                append_key(content,relative_universe); append_key(content,relative_address);
            }
            fixture_source_content[fixture->first].emplace(id,std::move(content));
        }
        auto found=definitions.find(key);
        if (found==definitions.end()) {
            auto mapping=std::make_shared<SourceValueMapping>();
            mapping->maximum=max_raw_value_for_source_count(program.sources.size());
            mapping->inverse_maximum=mapping->maximum>0?1.0/double(mapping->maximum):0.0;
            mapping->span=program.dmx_to>program.dmx_from?double(program.dmx_to-program.dmx_from):double(mapping->maximum);
            mapping->physical_from=program.physical_from; mapping->physical_to=program.physical_to;
            found=definitions.emplace(std::move(key),std::move(mapping)).first;
        }
        installed.mapping=found->second;
    }
    std::set<std::string> modes;
    for (const auto &fixture:scene.fixtures) {
        std::string key;
        append_text(key,fixture.fixture_type_name); append_text(key,fixture.dmx_mode_name);
        const auto content=fixture_source_content.find(fixture.fixture_id);
        if (content!=fixture_source_content.end()) {
            std::map<int32_t,uint32_t> ordinals;
            for (const auto &entry:content->second) ordinals.emplace(entry.first,uint32_t(ordinals.size()));
            for (const auto &entry:content->second) {
                append_text(key,entry.second);
                const int32_t master=source_programs_by_id_.at(entry.first).program.activation.master_program_id;
                const auto ordinal=ordinals.find(master);
                const int64_t master_index=ordinal==ordinals.end()?-1:int64_t(ordinal->second);
                append_key(key,master_index);
            }
        }
        modes.insert(std::move(key));
    }
    fixture_mode_definitions_=modes.size();
    mapping_definitions_=definitions.size(); // Content keys are setup scratch, never retained in playback.
}
// Compiles existing domain ownership into compact source/consumer edges and immutable activation contexts.
void PeravizVisualRuntimeCore::compile_evaluation_plans() {
    for (auto &[universe_id,universe]:universes_) {
        std::set<int32_t> required;
        for (const auto &property:universe.properties) for (const auto &input:property.property.contributors) required.insert(input.source_program_id);
        for (const auto &target:universe.color_targets) for (const auto &input:target.inputs) required.insert(input.binding.source_program_id);
        for (const auto &wheel:universe.wheel_bindings) required.insert(wheel.binding.source_program_id);
        for (const auto &binding:universe.gobo_bindings) required.insert(binding.dependency_program_ids.begin(),binding.dependency_program_ids.end());
        for (const auto &binding:universe.gobo_motion_bindings) required.insert(binding.dependency_program_ids.begin(),binding.dependency_program_ids.end());
        for (const auto &binding:universe.shutters) required.insert(binding.dependency_program_ids.begin(),binding.dependency_program_ids.end());
        // Add same-universe masters as graph nodes without expanding unsupported domain semantics.
        std::vector<int32_t> pending(required.begin(),required.end());
        for (size_t i=0;i<pending.size();++i) {
            const auto source=source_programs_by_id_.find(pending[i]);
            if (source==source_programs_by_id_.end()) continue;
            const auto master=source_programs_by_id_.find(source->second.program.activation.master_program_id);
            if (master==source_programs_by_id_.end() || master->second.program.sources.empty() || master->second.program.sources.front().universe_id!=universe_id) continue;
            if (required.insert(master->first).second) pending.push_back(master->first);
        }
        std::vector<const CompiledDmxSourceProgram *> programs;
        for (int32_t id:required) {
            const auto source=source_programs_by_id_.find(id);
            if (source==source_programs_by_id_.end()) continue;
            programs.push_back(&source->second.program); universe.source_bindings.push_back(&source->second);
        }
        universe.plan.install(programs,diagnostics_);
        for (uint32_t i=0;i<universe.properties.size();++i) {
            auto &property=universe.properties[i];
            for (const auto &input:property.property.contributors) property.sources.push_back(universe.plan.source_index(input.source_program_id));
            const auto &first=universe.source_bindings[property.sources.front()]->program;
            for (uint32_t source:property.sources) {
                const auto &definition=universe.source_bindings[source]->program;
                property.range_selector|=definition.dmx_from!=first.dmx_from || definition.dmx_to!=first.dmx_to;
            }
            const bool mechanical=property.parameter==SemanticParameter::Pan || property.parameter==SemanticParameter::Tilt;
            const int32_t target=mechanical?property.property.component_id:property.property.render_target_id;
            universe.plan.add_consumer(EvaluationDomain::Property,i,target,property.sources,false);
        }
        for (uint32_t i=0;i<universe.color_targets.size();++i) {
            auto &target=universe.color_targets[i]; std::vector<uint32_t> inputs;
            for (auto &input:target.inputs) { input.source=universe.plan.source_index(input.binding.source_program_id); inputs.push_back(input.source); }
            universe.plan.add_consumer(EvaluationDomain::Color,i,target.target.beam_render_target_id,inputs,false);
        }
        for (uint32_t i=0;i<universe.wheel_bindings.size();++i) {
            auto &wheel=universe.wheel_bindings[i]; wheel.source=universe.plan.source_index(wheel.binding.source_program_id);
            universe.plan.add_consumer(EvaluationDomain::Wheel,i,wheel.binding.beam_render_target_id,{wheel.source},false);
        }
        std::map<std::vector<int32_t>,std::shared_ptr<const GoboSourceDefinitions>> contexts;
        const auto prepare_context=[&](GoboEvaluationContext &context) {
            auto found=contexts.find(context.dependency_program_ids);
            if (found==contexts.end()) {
                auto definitions=std::make_shared<GoboSourceDefinitions>();
                for (int32_t id:context.dependency_program_ids) definitions->push_back(&source_programs_by_id_.at(id).program);
                found=contexts.emplace(context.dependency_program_ids,std::move(definitions)).first;
            }
            context.programs=found->second; context.values.resize(context.dependency_program_ids.size());
            for (int32_t id:context.dependency_program_ids) context.sources.push_back(universe.plan.source_index(id));
        };
        for (auto &context:universe.shutters) prepare_context(context);
        for (auto &context:universe.gobo_bindings) prepare_context(context);
        for (auto &context:universe.gobo_motion_bindings) prepare_context(context);
        const auto add_layers=[&](const auto &layers, const auto &bindings, EvaluationDomain domain) {
            std::vector<int64_t> keys;
            for (const auto &entry:layers) keys.push_back(entry.first);
            std::sort(keys.begin(),keys.end());
            for (int64_t key:keys) {
                std::vector<uint32_t> inputs;
                for (int binding:layers.at(key)) inputs.push_back(bindings[binding].sources.front());
                universe.plan.add_consumer(domain,0,key,inputs,true);
            }
        };
        add_layers(universe.gobo_binding_indices_by_layer,universe.gobo_bindings,EvaluationDomain::GoboSelection);
        add_layers(universe.gobo_motion_indices_by_layer,universe.gobo_motion_bindings,EvaluationDomain::GoboMotion);
        add_layers(universe.shutter_layers,universe.shutters,EvaluationDomain::Shutter);
        universe.plan.finish_install();
        universe.prefetched_warnings.resize(universe.plan.source_count(),0);
        installed_sources_+=universe.plan.source_count(); installed_colors_+=universe.color_targets.size();
        has_gobo_domains_=has_gobo_domains_ || !universe.gobo_bindings.empty() || !universe.gobo_motion_bindings.empty();
        universe.dirty_gobo_selections.reserve(universe.gobo_binding_indices_by_layer.size());
        universe.dirty_gobo_motions.reserve(universe.gobo_motion_indices_by_layer.size());
        universe.dirty_physical_wheels.reserve(universe.wheel_bindings.size());
        universe.wheel_dirty_targets.reserve(universe.wheel_binding_indices_by_physical_key.size());
        universe.dirty_color_targets.reserve(universe.color_targets.size()+universe.wheel_binding_indices_by_physical_key.size());
    }
    for (const auto &[key,state]:wheel_state_by_physical_key_) ordered_wheel_layers_[state.beam_target_id].push_back(&state);
    for (auto &[target,layers]:ordered_wheel_layers_)
        std::sort(layers.begin(),layers.end(),[](const auto *a,const auto *b) { return a->wheel_renderer_id<b->wheel_renderer_id; });
}
} // namespace peraviz::runtime
