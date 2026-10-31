#pragma once
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "runtime/visual_runtime_types.h"
#include "scene_model.h"
#include "dmx/gdtf_xml_reader.h"
#include "gdtf_runtime/shutter_contract.h"
#include <algorithm>
#include <charconv>
#include <unordered_map>
#include <unordered_set>

namespace peraviz::gdtf_runtime {
// Reads optional standard defaults independently; malformed supplied text never becomes a default.
inline double shutter_physical(tinyxml2::XMLElement *node,const char *name,double fallback,bool &valid) {
    const char *raw=node->Attribute(name);
    if (!raw) raw=node->Attribute(dmx::lower_ascii(name).c_str());
    if (!raw) return fallback;
    const auto text=dmx::trim_ascii(raw);
    const char *first=text.data(),*last=first+text.size();
    if (first!=last && *first=='+') ++first;
    double value=fallback;
    const auto parsed=std::from_chars(first,last,value,std::chars_format::general);
    if (parsed.ec!=std::errc() || parsed.ptr!=last || !std::isfinite(value)) { valid=false; return fallback; }
    return value;
}
// Uses default 0/1 and the next strictly greater start, including conditional functions with equal starts.
inline bool shutter_function_range(tinyxml2::XMLElement *fn,const std::vector<tinyxml2::XMLElement *> &functions,
        size_t bytes,uint32_t &from,uint32_t &to) {
    const char *raw=fn->Attribute("DMXFrom");
    if (!raw) raw=fn->Attribute("dmxfrom");
    if (!parse_and_convert_gdtf_dmx_value(raw?raw:"0/1",uint8_t(bytes),from)) return false;
    to=bytes==4?UINT32_MAX:uint32_t((uint64_t(1)<<(bytes*8))-1);
    for (auto *other:functions) {
        uint32_t next=0; const char *start=other->Attribute("DMXFrom");
        if (!start) start=other->Attribute("dmxfrom");
        if (!parse_and_convert_gdtf_dmx_value(start?start:"0/1",uint8_t(bytes),next)) return false;
        const auto conditional=[](tinyxml2::XMLElement *node) { const char *master=node->Attribute("ModeMaster"); if (!master) master=node->Attribute("modemaster"); return master && !dmx::trim_ascii(master).empty(); };
        if (other!=fn && next==from && !conditional(fn) && !conditional(other)) return false;
        if (next>from) to=std::min(to,next-1);
    }
    // Retain the existing bounded nonstandard DMXTo compatibility, never beyond the normative boundary.
    const char *end=fn->Attribute("DMXTo");
    if (!end) end=fn->Attribute("dmxto");
    uint32_t explicit_to=to;
    if (end && (!parse_and_convert_gdtf_dmx_value(end,uint8_t(bytes),explicit_to) || explicit_to<from || explicit_to>to)) return false;
    to=explicit_to; return true;
}
// Retains ordered sets intersected with their parent. Missing DMXFrom means 0/1, not parent start.
inline std::vector<ParsedWheelChannelSet> parse_shutter_sets(tinyxml2::XMLElement *fn,size_t bytes,uint32_t from,uint32_t to,double physical_from,double physical_to,bool &valid) {
    std::vector<ParsedWheelChannelSet> declared,sets;
    for (auto *node : dmx::collect_direct_children_by_name(fn,"channelset")) {
        const char *raw=node->Attribute("DMXFrom"); uint32_t value=0;
        if (!raw) raw=node->Attribute("dmxfrom");
        if (!parse_and_convert_gdtf_dmx_value(raw?raw:"0/1",uint8_t(bytes),value) || value>to) { valid=false; continue; }
        ParsedWheelChannelSet set; set.declared_dmx_from=value; set.effective_dmx_to=to;
        set.name=node->Attribute("Name")?node->Attribute("Name"):"";
        set.physical_from=shutter_physical(node,"PhysicalFrom",physical_from,valid);
        set.physical_to=shutter_physical(node,"PhysicalTo",physical_to,valid);
        declared.push_back(set);
    }
    std::stable_sort(declared.begin(),declared.end(),[](const auto &a,const auto &b){return a.declared_dmx_from<b.declared_dmx_from;});
    for (size_t i=0;i<declared.size();++i) {
        auto set=declared[i];
        if (i+1<declared.size()) {
            if (set.declared_dmx_from==declared[i+1].declared_dmx_from) { valid=false; continue; }
            set.effective_dmx_to=declared[i+1].declared_dmx_from-1;
        }
        if (set.effective_dmx_to<from) continue;
        set.declared_dmx_from=std::max(from,set.declared_dmx_from);
        sets.push_back(set);
    }
    // Named sets do not remove the parent's valid unnamed prefix or rescale its physical mapping.
    if (!sets.empty() && sets.front().declared_dmx_from>from) {
        ParsedWheelChannelSet prefix; prefix.declared_dmx_from=from; prefix.effective_dmx_to=sets.front().declared_dmx_from-1;
        prefix.physical_from=physical_from;
        prefix.physical_to=to>from?physical_from+(physical_to-physical_from)*double(prefix.effective_dmx_to-from)/double(to-from):physical_from;
        sets.insert(sets.begin(),prefix);
    }
    return valid?sets:std::vector<ParsedWheelChannelSet>{};
}
struct ShutterModeChoice { ShutterWave wave; uint32_t from=0,to=UINT32_MAX; std::string name; int32_t mode_id=0; };
// Keeps channel-wide mode selection dynamic: one frequency source, disjoint typed master-function guards.
inline std::vector<ShutterModeChoice> shutter_modes(const ChannelProgram &program,const CompiledGdtfFixtureType &fixture,ShutterWave wave) {
    if (wave!=ShutterWave::Frequency) return {{wave}};
    std::vector<ShutterModeChoice> modes;
    for (const auto &master:fixture.channel_programs) {
        const bool function=program.mode_master.target_kind==ModeMasterTargetKind::ChannelFunction;
        if (!(function?master.id==program.mode_master.master_program_id:master.dmx_channel_id==program.mode_master.master_channel_id) || master.attribute_name.rfind("StrobeMode",0)!=0) continue;
        const auto declared=shutter_attribute(master.attribute_name).wave;
        if (!shutter_periodic(declared) && declared!=ShutterWave::Unsupported) continue;
        const uint32_t from=std::max(program.mode_master.from,master.dmx_from),to=std::min(program.mode_master.to,master.dmx_to);
        // A channel-wide reference does not install each candidate function's own activation graph.
        // Keep such conditional candidates explicit until their additional dependencies can be routed natively.
        const auto selected=!function && master.mode_master.target_kind!=ModeMasterTargetKind::None?ShutterWave::Unsupported:declared;
        if (function) modes.push_back({selected,0,UINT32_MAX,master.function_name,master.id});
        else if (from<=to) modes.push_back({selected,from,to,master.function_name,master.id});
    }
    if (modes.empty()) modes.push_back({ShutterWave::Unsupported});
    return modes;
}
// Appends only exact native shutter programs and optically owned physical Beam targets.
template<class MakeSources>
void append_shutter_targets(runtime::CompiledRuntimeScene &scene,const SceneModel::FixturePatch &patch,
        const CompiledGdtfFixtureType &fixture,int32_t fixture_id,int32_t &next_id,MakeSources make_sources) {
    std::unordered_set<std::string> reported;
    std::unordered_map<int32_t,const GeometryInstance *> geometries;
    for (const auto &geometry:fixture.geometries) geometries[geometry.id]=&geometry;
    for (const auto &program:fixture.channel_programs) {
        const auto semantic=shutter_attribute(program.attribute_name);
        if (!semantic.recognized) continue;
        const bool frequency=std::any_of(fixture.channel_programs.begin(),fixture.channel_programs.end(),[&](const auto &p){return p.attribute_name=="StrobeFrequency" && (p.mode_master.target_kind==ModeMasterTargetKind::ChannelFunction?p.mode_master.master_program_id==program.id:p.mode_master.master_channel_id==program.dmx_channel_id);});
        if (program.attribute_name.rfind("StrobeMode",0)==0 && semantic.wave!=ShutterWave::Mode) {
            if ((semantic.wave==ShutterWave::Unsupported || !frequency) && reported.insert(program.attribute_name).second)
                scene.diagnostics.push_back({"PVZ-SHUTTER-MODE-UNSUPPORTED","warning","Unsupported or unpaired StrobeMode is source metadata only; no generic periodic waveform is inferred.",patch.fixture_uuid+" attribute="+program.attribute_name});
            continue; // Supported mode functions are consumed by the Frequency ModeMaster source.
        }
        if (program.attribute_name=="StrobeRate" && reported.insert("StrobeRate").second)
            scene.diagnostics.push_back({"PVZ-SHUTTER-RATE-UNSUPPORTED","warning","StrobeRate describes time between flashes, not frequency in Hz; its parameter chain is not implemented.",patch.fixture_uuid});
        const auto geometry=geometries.find(program.geometry_instance_id);
        if (geometry==geometries.end()) continue;
        const AttributeIdentity *attribute=nullptr;
        for (const auto &entry:fixture.attributes) if (entry.id==program.attribute_id) attribute=&entry;
        runtime::CompiledDmxSourceProgram source;
        source.program_id=next_id++; source.sources=make_sources(program); source.dmx_from=program.dmx_from; source.dmx_to=program.dmx_to;
        source.physical_from=program.physical_from; source.physical_to=program.physical_to;
        source.attribute_name=program.attribute_name; source.function_name=program.function_name;
        source.geometry_id=program.geometry_instance_id; source.geometry_name=geometry->second->path;
        source.parser_program_id=program.id; source.dmx_channel_id=program.dmx_channel_id; source.activation=program.mode_master;
        scene.source_programs.push_back(source);
        for (const auto &choice:shutter_modes(program,fixture,semantic.wave)) {
            // Distinct typed mode functions retain distinct activation identities even when wave/frequency match.
            const int32_t activation_id=choice.mode_id?next_id++:source.program_id;
            const auto wave=choice.wave;
            double duration=0.025,duty=1,offset=1;
            bool supported=wave!=ShutterWave::Unsupported && program.shutter_sets_valid && program.shutter_physical_valid && !program.shutter_subsets_present;
            if (attribute) {
                if (shutter_periodic(wave) && !attribute->physical_unit.empty() && attribute->physical_unit!="None" && attribute->physical_unit!="Frequency") supported=false;
                if (wave==ShutterWave::Duration && !attribute->physical_unit.empty() && attribute->physical_unit!="None" && attribute->physical_unit!="Time") supported=false;
                for (const auto &sub:attribute->subphysical_units) {
                    if (sub.type!="Duration" && sub.type!="DutyCycle" && sub.type!="TimeOffset") continue;
                    if (sub.physical_from!=sub.physical_to || !std::isfinite(sub.physical_from)) { supported=false; continue; }
                    const bool time=sub.type=="Duration";
                    if (!sub.physical_unit.empty() && sub.physical_unit!="None" && sub.physical_unit!=(time?"Time":"Percent")) supported=false;
                    if (sub.type=="Duration") duration=sub.physical_from;
                    if (sub.type=="DutyCycle") duty=sub.physical_from/100.0;
                    if (sub.type=="TimeOffset") offset=sub.physical_from/100.0;
                }
            }
            if (duration<0 || duty<0 || duty>1 || offset<0 || offset>1 || !std::isfinite(offset)) supported=false;
            auto sets=program.shutter_channel_sets;
            if (sets.empty()) { ParsedWheelChannelSet set; set.declared_dmx_from=program.dmx_from; set.effective_dmx_to=program.dmx_to; set.physical_from=program.physical_from; set.physical_to=program.physical_to; sets.push_back(set); }
            bool diagnosed=false;
            for (const auto &set:sets) {
                auto effective=supported?wave:ShutterWave::Unsupported;
                if (effective==ShutterWave::Mode) {
                    effective=shutter_label(set.name.empty()?program.function_name:set.name);
                    // An unlabelled generic mode selector is metadata, not a second shutter over its typed mode functions.
                    if (effective==ShutterWave::Unsupported && program.attribute_name=="StrobeModeShutter" &&
                        std::any_of(fixture.channel_programs.begin(),fixture.channel_programs.end(),[&](const auto &p){return p.attribute_name=="StrobeFrequency" && p.mode_master.master_channel_id==program.dmx_channel_id;})) continue;
                }
                const bool known=effective!=ShutterWave::Unsupported;
                if (!known && !diagnosed && reported.insert(program.attribute_name+":"+program.function_name).second) { scene.diagnostics.push_back({"PVZ-SHUTTER-SEMANTICS-UNSUPPORTED","warning","Shutter function lacks proven polarity/waveform/activation chain/constant SubPhysicalUnits; it is left open, not interpreted as periodic strobe.",patch.fixture_uuid+" attribute="+program.attribute_name}); diagnosed=true; }
                for (const auto &beam:scene.beam_profiles) {
                    const auto &path=geometry->second->path;
                    if (beam.fixture_id!=fixture_id || !(beam.geometry_path==path || beam.geometry_path.rfind(path+"/",0)==0)) continue;
                    runtime::CompiledShutterBinding binding;
                    binding.fixture_id=fixture_id; binding.beam_target_id=beam.render_target_id; binding.shutter_index=semantic.index;
                    binding.source_program_id=source.program_id; binding.wave=effective;
                    binding.duration=duration; binding.duty=duty; binding.offset=offset;
                    binding.status=!known?2:(wave==ShutterWave::Mode || shutter_random(wave)?1:0);
                    binding.channel_set_name=set.name; binding.gdtf_break=program.dmx_break;
                    binding.activation_function_id=activation_id;
                    binding.mode_from=choice.from; binding.mode_to=choice.to; binding.mode_function_name=choice.name;
                    binding.dmx_from=set.declared_dmx_from; binding.dmx_to=set.effective_dmx_to;
                    binding.physical_from=set.physical_from; binding.physical_to=set.physical_to;
                    scene.shutter_bindings.push_back(binding);
                }
            }
        }
    }
}
}
