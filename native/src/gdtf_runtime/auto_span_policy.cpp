#include "gdtf_runtime/auto_span_policy.h"
#include "gdtf_runtime/resolved_dmx_addresses.h"
#include "dmx/gdtf_xml_reader.h"
#include <algorithm>
#include <set>
#include <sstream>
#include <tuple>

namespace peraviz::gdtf_runtime {
// Parses only stable project identifiers; malformed persisted values recover to the conservative default.
AutoSpanPolicy parse_auto_span_policy(const std::string &value,bool *valid) {
    if (valid) *valid=value=="off" || value=="auto_safe" || value=="auto_overlap";
    return value=="off"?AutoSpanPolicy::Off:value=="auto_overlap"?AutoSpanPolicy::AutoOverlap:AutoSpanPolicy::AutoSafe;
}
// Serializes the Peraviz preference independently of standard source patch data.
const char *auto_span_policy_id(AutoSpanPolicy policy) {
    return policy==AutoSpanPolicy::Off?"off":policy==AutoSpanPolicy::AutoOverlap?"auto_overlap":"auto_safe";
}
// Reuses immutable selected-mode parser data across occupancy, compilation and policy-only reinstalls.
const CompiledGdtfFixtureType &cached_fixture_type(const SceneModel::FixturePatch &patch,FixtureTypeCache &cache) {
    const auto key=patch.gdtf_path+"\n"+dmx::lower_ascii(dmx::trim_ascii(patch.dmx_mode));
    auto found=cache.find(key);
    if (found==cache.end()) found=cache.emplace(key,compile_gdtf_fixture_type(patch.gdtf_path,patch.dmx_mode)).first;
    return found->second;
}
namespace {
struct Slot {
    int64_t universe; int channel;
    // Keeps actual MVR universe/slot identity, without a flattened occupancy encoding.
    bool operator<(const Slot &other) const { return std::tie(universe,channel)<std::tie(other.universe,other.channel); }
};
struct Candidate { const SceneModel::FixturePatch *patch; std::vector<Slot> continuation; };
// Formats bounded setup diagnostics with the authored patch and actual physical continuation slots.
std::string describe(const Candidate &candidate,const std::vector<std::pair<Slot,std::string>> &conflicts) {
    std::ostringstream text;
    text<<"MVR "<<candidate.patch->mvr_universe<<'.'<<candidate.patch->mvr_address;
    if (!candidate.continuation.empty()) {
        const auto &first=candidate.continuation.front(),&last=candidate.continuation.back();
        text<<"; requested continuation "<<first.universe<<'.'<<first.channel<<"–"<<last.universe<<'.'<<last.channel;
    }
    for (size_t i=0;i<std::min<size_t>(conflicts.size(),8);++i)
        text<<"; overlap "<<conflicts[i].first.universe<<'.'<<conflicts[i].first.channel<<" with "<<conflicts[i].second;
    if (conflicts.size()>8) text<<"; additional overlapping slot/occupant pairs="<<conflicts.size()-8;
    return text.str();
}
}
// Resolves all authored occupancy and all candidate proposals before making order-independent admission decisions.
AutoSpanPlan plan_auto_span(const SceneModel &scene,int universe_offset,const RuntimeRoutingOptions &options,
                           FixtureTypeCache &cache,AutoSpanEligibility eligible) {
    AutoSpanPlan out;
    std::map<Slot,std::set<std::string>> authored,proposed;
    std::vector<Candidate> candidates;
    std::set<int64_t> unknown_universes;
    bool globally_unknown=false;
    size_t omitted_details=0;
    std::map<std::string,size_t> status_counts;
    const auto diagnostic=[&](const std::string &code,const std::string &message,const std::string &subject,bool warning) {
        ++status_counts[code];
        if (out.diagnostics.size()<256) out.diagnostics.push_back({code,warning?"warning":"info",message,subject});
        else ++omitted_details;
    };
    for (const auto &patch:scene.fixture_patches) {
        auto &decision=out.fixtures[patch.fixture_uuid];
        if (patch.gdtf_path.empty() || patch.dmx_mode.empty() || !patch.dmx_import_error.empty()) {
            globally_unknown=true; continue;
        }
        const auto &type=cached_fixture_type(patch,cache);
        std::map<int,int> footprints;
        for (const auto &program:type.channel_programs) for (int offset:program.dmx_offsets_1_based)
            footprints[program.dmx_break]=std::max(footprints[program.dmx_break],offset);
        bool reliable=type.dmx_patch_supported && !footprints.empty();
        bool overflow=false;
        for (const auto &[break_id,width]:footprints) {
            const auto entry=source_patch(patch,break_id);
            if (entry.universe<1 || entry.address<1 || entry.address>512 || width<1) { reliable=false; continue; }
            overflow|=int64_t(entry.address)+width-1>512;
            for (int channel=entry.address;channel<=std::min<int64_t>(512,int64_t(entry.address)+width-1);++channel)
                authored[{entry.universe,channel}].insert(patch.fixture_uuid);
        }
        if (!reliable) {
            if (patch.addresses.empty()) {
                if (patch.mvr_universe>0) unknown_universes.insert(patch.mvr_universe); else globally_unknown=true;
            } else for (const auto &entry:patch.addresses) {
                if (entry.universe>0) unknown_universes.insert(entry.universe); else globally_unknown=true;
            }
            if (!type.dmx_patch_supported) diagnostic("PVZ-AUTO-SPAN-UNSUPPORTED","Auto Span unsupported: unresolved source semantics; existing compilation guards retained.",patch.fixture_uuid,true);
            continue;
        }
        const bool forced=options.auto_span_fixture_uuids.count(patch.fixture_uuid)>0;
        const bool supported=eligible(type) && footprints.size()==1;
        if (forced && !supported) decision.error="Auto Span requires one effective GDTF break with supported direct Color/Dimmer/Pan/Tilt/Zoom controls; disable Auto Span for this fixture override.";
        if (!overflow) {
            diagnostic("PVZ-DMX-STANDARD","Standard authored MVR routing (co-patching is permitted).",patch.fixture_uuid,false);
            continue;
        }
        if (!supported) {
            decision.strict_partial=eligible(type);
            diagnostic("PVZ-AUTO-SPAN-UNSUPPORTED","Auto Span unsupported for this selected mode; authored breaks remain strict and independently complete supported controls are retained where safe.",patch.fixture_uuid,true);
            continue;
        }
        decision.strict_partial=true;
        const auto entry=source_patch(patch,footprints.begin()->first);
        Candidate candidate{&patch,{}};
        // Preserve potential bytes in the existing native mailbox across policy-only subscription replacement.
        for (int64_t absolute=entry.address-1;absolute<int64_t(entry.address)+footprints.begin()->second-1;++absolute) {
            const int64_t physical=int64_t(entry.universe)+universe_offset+absolute/512;
            if (physical>=0 && physical<=32767) out.replay_sources.push_back({int(physical),int(absolute%512),0});
        }
        for (int64_t absolute=512;absolute<int64_t(entry.address)+footprints.begin()->second-1;++absolute)
            candidate.continuation.push_back({int64_t(entry.universe)+absolute/512,int(absolute%512+1)});
        // Off must retain complete primary controls even at the last Art-Net universe.
        if (options.policy!=AutoSpanPolicy::Off || forced) {
            decision.error=validate_resolved_addresses(patch,type,universe_offset,true);
            if (!decision.error.empty()) continue;
        }
        if (options.policy!=AutoSpanPolicy::Off || forced)
            for (const auto &slot:candidate.continuation) proposed[slot].insert(patch.fixture_uuid);
        candidates.push_back(std::move(candidate));
    }
    for (const auto &candidate:candidates) {
        const auto &id=candidate.patch->fixture_uuid;
        auto &decision=out.fixtures.at(id);
        std::vector<std::pair<Slot,std::string>> conflicts;
        bool unknown=globally_unknown;
        for (const auto &slot:candidate.continuation) {
            unknown|=unknown_universes.count(slot.universe)>0;
            const auto collect=[&](const auto &occupancy) {
                const auto found=occupancy.find(slot);
                if (found!=occupancy.end()) for (const auto &other:found->second) if (other!=id) conflicts.push_back({slot,other});
            };
            collect(authored); collect(proposed);
        }
        const auto detail=describe(candidate,conflicts);
        const bool forced=options.auto_span_fixture_uuids.count(id)>0;
        if (options.policy==AutoSpanPolicy::Off && !forced) {
            diagnostic("PVZ-DMX-STRICT-OVERFLOW","Strict overflow: omit unavailable complete controls/dependency groups; no continuation inferred. "+detail,id,true);
        } else if (options.policy==AutoSpanPolicy::AutoSafe && !forced && (unknown || !conflicts.empty())) {
            diagnostic(unknown?"PVZ-AUTO-SPAN-DENIED-UNKNOWN":"PVZ-AUTO-SPAN-DENIED-OVERLAP",
                       "Peraviz Auto Span denied; strict complete-control fallback. "+detail+(unknown?"; continuation occupancy cannot be proven free":""),id,true);
        } else {
            decision.span=true; decision.strict_partial=false;
            diagnostic(conflicts.empty()?"PVZ-AUTO-SPAN-APPLIED":"PVZ-AUTO-SPAN-OVERLAP",
                       "Peraviz inferred Auto Span applied; all co-patched fixtures independently read identical DMX bytes. "+detail+(unknown?"; other occupancy is unresolved":""),id,!conflicts.empty() || unknown);
        }
    }
    std::string summary="Routing status counts:";
    for (const auto &[code,count]:status_counts) summary+=" "+code+"="+std::to_string(count);
    if (omitted_details) summary+="; bounded per-fixture details omitted="+std::to_string(omitted_details);
    if (!status_counts.empty()) out.diagnostics.push_back({"PVZ-AUTO-SPAN-SUMMARY",omitted_details?"warning":"info",summary,"Auto Span setup"});
    return out;
}

// Prunes complete properties/color groups and transitive activation dependents; no missing byte is ever decoded.
void retain_strict_controls(runtime::CompiledRuntimeScene &scene,const std::unordered_set<int32_t> &unavailable) {
    auto invalid=unavailable;
    bool changed=true;
    while (changed) {
        changed=false;
        for (const auto &source:scene.source_programs) if (invalid.count(source.activation.master_program_id))
            changed|=invalid.insert(source.program_id).second;
    }
    const auto erase=[](auto &values,auto predicate) { values.erase(std::remove_if(values.begin(),values.end(),predicate),values.end()); };
    erase(scene.properties,[&](const auto &property) {
        return std::any_of(property.contributors.begin(),property.contributors.end(),[&](const auto &input){return invalid.count(input.source_program_id)>0;});
    });
    erase(scene.color_targets,[&](const auto &target) {
        return std::any_of(target.inputs.begin(),target.inputs.end(),[&](const auto &input){return invalid.count(input.source_program_id)>0;});
    });
    erase(scene.source_programs,[&](const auto &source){return invalid.count(source.program_id)>0;});
}
}
