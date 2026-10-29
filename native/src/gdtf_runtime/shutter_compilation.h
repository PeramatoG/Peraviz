#pragma once
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "runtime/visual_runtime_types.h"
#include "scene_model.h"
#include "dmx/gdtf_xml_reader.h"
#include "gdtf_runtime/shutter_contract.h"
#include <algorithm>
#include <unordered_map>
#include <unordered_set>

namespace peraviz::gdtf_runtime {
// Retains declared ChannelSet ranges for shutter polarity and physical mappings, without wheel semantics.
inline std::vector<ParsedWheelChannelSet> parse_shutter_sets(tinyxml2::XMLElement *fn,size_t bytes,uint32_t from,uint32_t to,double physical_from,double physical_to,bool &valid) {
    std::vector<ParsedWheelChannelSet> sets;
    for (auto *node : dmx::collect_direct_children_by_name(fn,"channelset")) {
        const char *raw=node->Attribute("DMXFrom"); uint32_t value=0;
        if (!raw || !parse_and_convert_gdtf_dmx_value(raw,uint8_t(bytes),value) || value<from || value>to) { valid=false; continue; }
        ParsedWheelChannelSet set; set.declared_dmx_from=value; set.effective_dmx_to=to;
        set.name=node->Attribute("Name")?node->Attribute("Name"):"";
        set.physical_from=physical_from; set.physical_to=physical_to;
        node->QueryDoubleAttribute("PhysicalFrom",&set.physical_from); node->QueryDoubleAttribute("PhysicalTo",&set.physical_to);
        if (!std::isfinite(set.physical_from) || !std::isfinite(set.physical_to)) valid=false;
        sets.push_back(set);
    }
    std::stable_sort(sets.begin(),sets.end(),[](const auto &a,const auto &b){return a.declared_dmx_from<b.declared_dmx_from;});
    for (size_t i=0;i+1<sets.size();++i) {
        if (sets[i].declared_dmx_from==sets[i+1].declared_dmx_from) valid=false;
        sets[i].effective_dmx_to=sets[i+1].declared_dmx_from?sets[i+1].declared_dmx_from-1:0;
    }
    return sets;
}
// Appends only exact native shutter programs and optically owned physical Beam targets.
template<class MakeSources>
void append_shutter_targets(runtime::CompiledRuntimeScene &scene,const SceneModel::FixturePatch &patch,
        const CompiledGdtfFixtureType &fixture,int32_t fixture_id,int32_t &next_id,MakeSources make_sources) {
    std::unordered_set<std::string> reported;
    const bool frequency=std::any_of(fixture.channel_programs.begin(),fixture.channel_programs.end(),[](const auto &p){return p.attribute_name=="StrobeFrequency";});
    std::unordered_map<int32_t,const GeometryInstance *> geometries;
    for (const auto &geometry:fixture.geometries) geometries[geometry.id]=&geometry;
    for (const auto &program:fixture.channel_programs) {
        const auto semantic=shutter_attribute(program.attribute_name);
        if (!semantic.recognized) continue;
        if (program.attribute_name.rfind("StrobeMode",0)==0 && semantic.wave!=ShutterWave::Mode) {
            if ((semantic.wave==ShutterWave::Unsupported || !frequency) && reported.insert(program.attribute_name).second)
                scene.diagnostics.push_back({"PVZ-SHUTTER-MODE-UNSUPPORTED","warning","Unsupported or unpaired StrobeMode is source metadata only; no generic periodic waveform is inferred.",patch.fixture_uuid+" attribute="+program.attribute_name});
            continue; // Supported mode functions are consumed by the Frequency ModeMaster source.
        }
        const auto geometry=geometries.find(program.geometry_instance_id);
        if (geometry==geometries.end()) continue;
        const AttributeIdentity *attribute=nullptr;
        for (const auto &entry:fixture.attributes) if (entry.id==program.attribute_id) attribute=&entry;
        auto wave=semantic.wave;
        if (wave==ShutterWave::Frequency) {
            wave=ShutterWave::Unsupported;
            for (const auto &master:fixture.channel_programs) if ((program.mode_master.target_kind==ModeMasterTargetKind::ChannelFunction ? master.id==program.mode_master.master_program_id : master.dmx_channel_id==program.mode_master.master_channel_id) &&
                    master.attribute_name.rfind("StrobeMode",0)==0) {
                const auto declared=shutter_attribute(master.attribute_name).wave;
                if (declared>=ShutterWave::Strobe && declared<=ShutterWave::PulseClose &&
                    (program.mode_master.target_kind==ModeMasterTargetKind::ChannelFunction ||
                     (program.mode_master.from>=master.dmx_from && program.mode_master.to<=master.dmx_to))) wave=declared;
            }
        }
        double duration=0.025,duty=1,offset=1;
        bool supported=wave!=ShutterWave::Unsupported && program.shutter_sets_valid && !program.shutter_subsets_present;
        if ((wave>=ShutterWave::Strobe && wave<=ShutterWave::PulseClose) || wave==ShutterWave::Duration) supported &= program.physical_range_declared;
        if (attribute) {
            if (wave>=ShutterWave::Strobe && wave<=ShutterWave::PulseClose && !attribute->physical_unit.empty() && attribute->physical_unit!="None" && attribute->physical_unit!="Frequency") supported=false;
            if (wave==ShutterWave::Duration && !attribute->physical_unit.empty() && attribute->physical_unit!="None" && attribute->physical_unit!="Time") supported=false;
            for (const auto &sub:attribute->subphysical_units) {
                if (sub.type!="Duration" && sub.type!="DutyCycle" && sub.type!="TimeOffset") continue;
                if (sub.physical_from!=sub.physical_to || !std::isfinite(sub.physical_from)) { supported=false; continue; }
                const bool time=sub.type=="Duration";
                if (!sub.physical_unit.empty() && sub.physical_unit!=(time?"Time":"Percent")) supported=false;
                if (sub.type=="Duration") duration=sub.physical_from;
                if (sub.type=="DutyCycle") duty=sub.physical_from/100.0;
                if (sub.type=="TimeOffset") offset=sub.physical_from/100.0;
            }
        }
        if (duration<0 || duty<0 || duty>1 || !std::isfinite(offset)) supported=false;
        runtime::CompiledDmxSourceProgram source;
        source.program_id=next_id++; source.sources=make_sources(program); source.dmx_from=program.dmx_from; source.dmx_to=program.dmx_to;
        source.physical_from=program.physical_from; source.physical_to=program.physical_to;
        source.attribute_name=program.attribute_name; source.function_name=program.function_name;
        source.geometry_id=program.geometry_instance_id; source.geometry_name=geometry->second->path;
        source.parser_program_id=program.id; source.dmx_channel_id=program.dmx_channel_id; source.activation=program.mode_master;
        scene.source_programs.push_back(source);
        auto sets=program.shutter_channel_sets;
        if (sets.empty()) { ParsedWheelChannelSet set; set.declared_dmx_from=program.dmx_from; set.effective_dmx_to=program.dmx_to; set.physical_from=program.physical_from; set.physical_to=program.physical_to; sets.push_back(set); }
        bool diagnosed=false;
        for (const auto &set:sets) {
            auto effective=supported?wave:ShutterWave::Unsupported;
            if (effective==ShutterWave::Mode) effective=shutter_label(set.name.empty()?program.function_name:set.name);
            const bool known=effective!=ShutterWave::Unsupported;
            if (!known && !diagnosed && reported.insert(program.attribute_name+":"+program.function_name).second) { scene.diagnostics.push_back({"PVZ-SHUTTER-SEMANTICS-UNSUPPORTED","warning","Shutter function lacks proven polarity/waveform/constant SubPhysicalUnits; it is left open, not interpreted as periodic strobe.",patch.fixture_uuid+" attribute="+program.attribute_name}); diagnosed=true; }
            for (const auto &beam:scene.beam_profiles) {
                const auto &path=geometry->second->path;
                if (beam.fixture_id!=fixture_id || !(beam.geometry_path==path || beam.geometry_path.rfind(path+"/",0)==0)) continue;
                runtime::CompiledShutterBinding binding;
                binding.fixture_id=fixture_id; binding.beam_target_id=beam.render_target_id; binding.shutter_index=semantic.index;
                binding.source_program_id=source.program_id; binding.wave=effective;
                binding.duration=duration; binding.duty=duty; binding.offset=offset;
                binding.status=!known?2:(wave==ShutterWave::Mode?1:0);
                binding.dmx_from=set.declared_dmx_from; binding.dmx_to=set.effective_dmx_to;
                binding.physical_from=set.physical_from; binding.physical_to=set.physical_to;
                scene.shutter_bindings.push_back(binding);
            }
        }
    }
}
}
