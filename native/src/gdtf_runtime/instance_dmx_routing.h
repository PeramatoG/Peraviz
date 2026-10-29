#pragma once
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "gdtf_runtime/gdtf_geometry_identity.h"
#include "dmx/addressing_fields.h"
#include "dmx/gdtf_xml_reader.h"
#include <functional>
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <set>

namespace peraviz::gdtf_runtime {
struct DmxGeometryRoute {
    std::string name, path, context;
    tinyxml2::XMLElement *reference = nullptr;
    int reference_depth = 0;
};

// Validates physical byte declarations before the permissive legacy offset reader sees them.
inline std::string validate_channel_addresses(tinyxml2::XMLElement *mode) {
    for (auto *channel : dmx::collect_elements_by_name(mode,"dmxchannel")) {
        const char *raw=dmx::patch_attribute(channel,"Offset","offset");
        if (!raw || dmx::trim_ascii(raw)=="None") continue;
        std::string offsets=raw;
        size_t start=0;
        std::set<int> seen;
        do {
            const auto end=offsets.find(',',start);
            int value=0;
            if (!dmx::patch_number(offsets.substr(start,end-start),value,1) || value>512 || !seen.insert(value).second)
                return "Invalid ordered DMXChannel Offset declaration.";
            if (end==std::string::npos) break;
            start=end+1;
        } while (true);
        if (seen.size()>4) return "DMXChannel source widths above 32 bits are unsupported.";
        const char *source_break=dmx::patch_attribute(channel,"DMXBreak","dmxbreak");
        int number=1;
        if (source_break && std::string(source_break)!="Overwrite" && !dmx::patch_number(source_break,number,1))
            return "Invalid DMXChannel DMXBreak declaration.";
    }
    return {};
}

// Expands only semantic routing, preserving the importer's source/reference path spelling.
inline std::string expand_instance_dmx_routes(CompiledGdtfFixtureType &fixture, tinyxml2::XMLElement *root,
                                               tinyxml2::XMLElement *mode) {
    std::unordered_map<std::string,tinyxml2::XMLElement *> roots;
    for (auto *container : dmx::collect_elements_by_name(root,"geometries"))
        for (auto *node=container->FirstChildElement(); node; node=node->NextSiblingElement()) {
            const char *name=dmx::patch_attribute(node,"Name","name");
            if (name && !roots.emplace(name,node).second) return "Ambiguous top-level geometry name.";
        }
    const char *selected=dmx::patch_attribute(mode,"Geometry","geometry");
    auto origin=roots.find(selected ? selected : "");
    // Existing parser-only definitions without a geometry tree retain their historical identities.
    if (origin==roots.end()) {
        if (!roots.empty()) return "Selected mode geometry cannot be resolved.";
        for (const auto &program : fixture.channel_programs) if (program.dmx_break<1) return "Overwrite requires a GeometryReference context.";
        return {};
    }
    std::vector<DmxGeometryRoute> routes;
    std::unordered_set<tinyxml2::XMLElement *> stack;
    std::unordered_set<std::string> paths;
    std::unordered_map<std::string,tinyxml2::XMLElement *> definitions;
    std::string issue;
    std::function<void(tinyxml2::XMLElement *,std::string,std::string,tinyxml2::XMLElement *,int)> visit;
    visit = [&](tinyxml2::XMLElement *node,std::string parent,std::string context,tinyxml2::XMLElement *reference,int depth) {
        if (!issue.empty()) return;
        const char *raw=dmx::patch_attribute(node,"Name","name");
        if (!raw || dmx::trim_ascii(raw).empty()) return; // PinPatch and other non-geometry children.
        if (!stack.insert(node).second) { issue="Cyclic geometry reference."; return; }
        const std::string name=raw;
        const auto path=append_geometry_path(parent,name);
        if (dmx::lower_ascii(node->Name())=="geometryreference") {
            const char *target=dmx::patch_attribute(node,"Geometry","geometry");
            auto found=roots.find(target ? target : "");
            if (found==roots.end()) { issue="Unresolved top-level GeometryReference target."; return; }
            visit(found->second,path,path,node,depth+1);
        } else {
            if (name.empty() || !paths.insert(path).second) { issue="Ambiguous expanded geometry identity."; return; }
            const auto known=definitions.emplace(name,node);
            if (!known.second && known.first->second!=node) { issue="Ambiguous source geometry name."; return; }
            routes.push_back({name,path,context,reference,depth});
            for (auto *child=node->FirstChildElement(); child; child=child->NextSiblingElement()) visit(child,path,context,reference,depth);
        }
        stack.erase(node);
    };
    visit(origin->second,"","",nullptr,0);
    if (!issue.empty()) return issue;
    // Table 49: children correspond to sorted numbered source breaks; Overwrite uses the final child.
    std::unordered_map<tinyxml2::XMLElement *,std::set<int>> numbered;
    std::unordered_set<tinyxml2::XMLElement *> overwritten;
    for (const auto &route : routes) if (route.reference)
        for (const auto &program : fixture.channel_programs) if (fixture.geometries[program.geometry_instance_id-1].name==route.name) {
            if (program.dmx_break==0) overwritten.insert(route.reference);
            else numbered[route.reference].insert(program.dmx_break);
        }
    // Move only routing records; immutable wheels, media leases and optical resources stay shared.
    const auto original_programs=std::move(fixture.channel_programs);
    const auto original_components=std::move(fixture.components);
    const auto original_geometries=std::move(fixture.geometries);
    const auto original_channels=std::move(fixture.dmx_channels);
    fixture.channel_programs.clear();
    fixture.components.clear();
    fixture.geometries.clear();
    fixture.dmx_channels.clear();
    struct Instance { int original_id; std::string context; };
    std::vector<Instance> instances;
    std::map<std::string,int> geometry_ids, component_ids, channel_ids;
    for (const auto &program : original_programs) {
        const auto &geometry=original_geometries[program.geometry_instance_id-1];
        bool matched=false;
        for (const auto &route : routes) if (route.name==geometry.name) {
            matched=true;
            auto copy=program;
            if (route.reference_depth>1) return "Nested GeometryReference addressing remains unsupported.";
            if (route.reference) {
                const auto children=dmx::collect_direct_children_by_name(route.reference,"break");
                const auto &breaks=numbered[route.reference];
                if (children.size()!=breaks.size()+overwritten.count(route.reference)) return "GeometryReference Break children do not match referenced channel breaks.";
                size_t index=breaks.size();
                if (program.dmx_break>0) index=static_cast<size_t>(std::distance(breaks.begin(),breaks.find(program.dmx_break)));
                auto *entry=children[index];
                const char *raw_break=dmx::patch_attribute(entry,"DMXBreak","dmxbreak");
                const char *raw_offset=dmx::patch_attribute(entry,"DMXOffset","dmxoffset");
                int target=1, offset=1;
                std::string offset_text=raw_offset ? dmx::trim_ascii(raw_offset) : "1";
                if (offset_text.rfind("1.",0)==0) offset_text=offset_text.substr(2);
                if ((raw_break && (!dmx::patch_number(raw_break,target,1) || target>255)) ||
                    (!dmx::patch_number(offset_text,offset,1) || offset>512)) return "Invalid GeometryReference Break/DMXOffset.";
                // Numbered breaks keep their identity; only Overwrite adopts the reference break.
                if (program.dmx_break==0) copy.dmx_break=target;
                else if (target!=program.dmx_break) return "Numbered reference Break must identify its corresponding source break.";
                for (auto &byte : copy.dmx_offsets_1_based) { byte+=offset-1; if (byte>512) return "Reference-adjusted Offset exceeds its break."; }
            } else if (program.dmx_break==0) return "Overwrite requires a GeometryReference context.";
            int &gid=geometry_ids[route.path];
            if (!gid) {
                gid=static_cast<int>(fixture.geometries.size()+1);
                auto instance=geometry;
                instance.id=gid;
                instance.path=route.path;
                fixture.geometries.push_back(instance);
            }
            copy.geometry_instance_id=gid;
            int &cid=component_ids[route.path+":"+std::to_string(program.component_id)];
            if (!cid) {
                cid=static_cast<int>(fixture.components.size()+1);
                auto component=original_components[program.component_id-1];
                component.component_id=cid;
                component.geometry_instance_id=gid;
                component.render_target_id=cid;
                fixture.components.push_back(component);
            }
            copy.component_id=cid;
            int &channel=channel_ids[route.context+":"+std::to_string(program.dmx_channel_id)];
            if (!channel) {
                channel=static_cast<int>(fixture.dmx_channels.size()+1);
                auto source=original_channels[program.dmx_channel_id-1];
                source.id=channel;
                source.source_program_id=0;
                source.dmx_offsets_1_based=copy.dmx_offsets_1_based;
                fixture.dmx_channels.push_back(source);
            }
            copy.dmx_channel_id=channel;
            copy.id=static_cast<int>(fixture.channel_programs.size()+1);
            if (!fixture.dmx_channels[channel-1].source_program_id)
                fixture.dmx_channels[channel-1].source_program_id=copy.id;
            fixture.channel_programs.push_back(copy);
            instances.push_back({program.id,route.context});
        }
        if (!matched) return "DMXChannel geometry is missing from the selected expanded tree.";
    }
    for (size_t i=0; i<fixture.channel_programs.size(); ++i) {
        auto &condition=fixture.channel_programs[i].mode_master;
        if (condition.target_kind==ModeMasterTargetKind::None || !condition.valid) continue;
        int target=-1;
        for (size_t j=0; j<instances.size(); ++j) if (instances[j].original_id==condition.master_program_id && instances[j].context==instances[i].context) target=static_cast<int>(j);
        if (target<0) for (size_t j=0; j<instances.size(); ++j) if (instances[j].original_id==condition.master_program_id && instances[j].context.empty()) target=static_cast<int>(j);
        if (target<0) return "ModeMaster cannot be resolved within the same instance or a common ancestor.";
        condition.master_program_id=fixture.channel_programs[target].id;
        condition.master_channel_id=fixture.channel_programs[target].dmx_channel_id;
        condition.target_id=condition.target_kind==ModeMasterTargetKind::DmxChannel ? condition.master_channel_id : condition.master_program_id;
    }
    return {};
}
}
