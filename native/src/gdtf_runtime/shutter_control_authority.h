#pragma once
#include "runtime/visual_runtime_types.h"
#include <algorithm>
#include <array>
#include <cstring>
#include <map>
#include <unordered_map>

namespace peraviz::gdtf_runtime {
using ShutterControlSignature=std::array<int64_t,15>;
// Retains exact declared scalars for proof; neither current values nor hash collisions establish sharing.
inline int64_t shutter_control_bits(double value) { int64_t bits; std::memcpy(&bits,&value,sizeof(bits)); return bits; }
// Source IDs reference effective instance-qualified bytes, function and activation graphs. Fixture scope prevents co-patch merging.
inline ShutterControlSignature shutter_control_signature(const runtime::CompiledShutterBinding &b) {
    return {b.source_program_id,b.shutter_index,int64_t(b.wave),b.status,int64_t(b.dmx_from),int64_t(b.dmx_to),
        shutter_control_bits(b.duration),shutter_control_bits(b.duty),shutter_control_bits(b.offset),shutter_control_bits(b.physical_from),shutter_control_bits(b.physical_to),
        b.fixture_id,int64_t(b.mode_from),int64_t(b.mode_to),b.activation_function_id};
}
// Uses physical identity solely for routing members, never as temporal control authority or random seed.
inline int64_t shutter_control_layer(int32_t target,int32_t index) { return (int64_t(target)<<32)|uint32_t(index); }
struct ShutterControlAuthority {
    int32_t id=0,fixture=0,index=1;
    uint32_t seed=0;
    std::vector<int32_t> targets;
};
struct ShutterControlLayout {
    std::unordered_map<int64_t,int32_t> by_layer;
    std::vector<ShutterControlAuthority> authorities;
};
// Interns complete immutable control sets once, in signature order, with an explicit collision-free generation-local ID.
inline ShutterControlLayout shutter_control_layout(const runtime::CompiledRuntimeScene &scene) {
    std::map<int64_t,std::vector<ShutterControlSignature>> layers;
    for (const auto &b:scene.shutter_bindings) layers[shutter_control_layer(b.beam_target_id,b.shutter_index)].push_back(shutter_control_signature(b));
    std::map<std::vector<ShutterControlSignature>,int32_t> interned;
    for (auto &[layer,key]:layers) { std::sort(key.begin(),key.end()); interned.emplace(key,0); }
    std::unordered_map<int32_t,const runtime::CompiledDmxSourceProgram *> sources;
    for (const auto &source:scene.source_programs) sources[source.program_id]=&source;
    ShutterControlLayout result;
    for (auto &[key,id]:interned) {
        id=int32_t(result.authorities.size()+1);
        uint64_t seed=0x53485554544552ULL;
        for (const auto &record:key) for (size_t field=0;field<record.size();++field) {
            int64_t value=record[field];
            // Seeds use transport precision so packed installation and direct native installation agree.
            if (field>=6 && field<=10) { double scalar; std::memcpy(&scalar,&value,sizeof(scalar)); value=shutter_control_bits(double(float(scalar))); }
            seed=shutter_mix(seed^uint64_t(value));
        }
        // Include effective byte routes and activation edges, not just generation-local numeric source handles.
        for (const auto &record:key) {
            int32_t source=int32_t(record[0]); std::vector<int32_t> visited;
            while (source>0 && std::find(visited.begin(),visited.end(),source)==visited.end()) {
                visited.push_back(source); const auto found=sources.find(source); if (found==sources.end()) break;
                const auto &program=*found->second;
                for (const auto &byte:program.sources) for (int32_t value:{byte.universe_id,byte.address,byte.byte_order}) seed=shutter_mix(seed^uint32_t(value));
                const auto &condition=program.activation;
                for (uint32_t value:{program.dmx_from,program.dmx_to,uint32_t(condition.target_kind),condition.from,condition.to}) seed=shutter_mix(seed^value);
                source=condition.target_kind==ModeMasterTargetKind::None?0:condition.master_program_id;
            }
        }
        result.authorities.push_back({id,int32_t(key.front()[11]),int32_t(key.front()[1]),uint32_t(seed^(seed>>32)),{}});
    }
    for (const auto &[layer,key]:layers) {
        const auto id=interned.at(key); result.by_layer.emplace(layer,id);
        result.authorities[id-1].targets.push_back(int32_t(layer>>32));
    }
    return result;
}
}
