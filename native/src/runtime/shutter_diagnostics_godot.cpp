#include "runtime/shutter_diagnostics_godot.h"
#include "runtime/peraviz_visual_runtime_godot.h"
#include <unordered_map>
#include <cstdlib>
#include "gdtf_runtime/shutter_sampling.h"

namespace godot {
namespace {
// Reports exact ordered locations; MVR universe identity remains distinct from native universe-offset policy.
Array byte_routes(const peraviz::runtime::CompiledDmxSourceProgram &source,int universe_offset) {
    Array bytes;
    for (const auto &byte:source.sources) {
        Dictionary location; location["native_universe"]=byte.universe_id; location["mvr_universe"]=byte.universe_id-universe_offset;
        location["channel"]=byte.address+1; location["byte_order"]=byte.byte_order; bytes.push_back(location);
    }
    return bytes;
}
// Presents semantic names in the diagnostic report instead of requiring an enum lookup.
const char *wave_name(peraviz::gdtf_runtime::ShutterWave wave) {
    using W=peraviz::gdtf_runtime::ShutterWave;
    switch (wave) {
        case W::Open:return "Open"; case W::Closed:return "Closed"; case W::Strobe:return "Strobe";
        case W::Pulse:return "Pulse"; case W::PulseOpen:return "PulseOpen"; case W::PulseClose:return "PulseClose";
        case W::RandomStrobe:return "RandomStrobe"; case W::RandomPulse:return "RandomPulse";
        case W::RandomOpen:return "RandomPulseOpen"; case W::RandomClose:return "RandomPulseClose";
        default:return "Unsupported";
    }
}
}
// Retains names/provenance at setup only. This immutable diagnostic sidecar never drives playback semantics.
Array shutter_setup_metadata(const peraviz::runtime::CompiledRuntimeScene &scene,int universe_offset) {
    Array rows;
    const char *selected=std::getenv("PERAVIZ_SHUTTER_TRACE");
    if (!selected || !*selected) return rows;
    const char *target_text=std::getenv("PERAVIZ_SHUTTER_TRACE_TARGET");
    int64_t selected_target=target_text?std::strtoll(target_text,nullptr,10):0;
    std::unordered_map<int32_t,const peraviz::runtime::CompiledDmxSourceProgram *> sources;
    std::unordered_map<int32_t,const peraviz::runtime::CompiledFixtureInstance *> fixtures;
    for (const auto &s:scene.source_programs) sources[s.program_id]=&s;
    for (const auto &f:scene.fixtures) fixtures[f.fixture_id]=&f;
    for (const auto &b:scene.shutter_bindings) {
        const auto source=sources.find(b.source_program_id),unused=sources.end();
        const auto fixture=fixtures.find(b.fixture_id);
        if (source==unused || fixture==fixtures.end() || fixture->second->fixture_uuid!=selected || (selected_target && b.beam_target_id!=selected_target) || rows.size()>=64) continue;
        if (!selected_target) selected_target=b.beam_target_id;
        const auto &s=*source->second; const auto &f=*fixture->second;
        Dictionary row;
        row["fixture_id"]=b.fixture_id; row["target_id"]=b.beam_target_id; row["shutter_index"]=b.shutter_index;
        row["source_id"]=b.source_program_id; row["binding_activation_id"]=b.activation_function_id; row["dmx_from"]=int64_t(b.dmx_from); row["dmx_to"]=int64_t(b.dmx_to);
        row["fixture_uuid"]=String::utf8(f.fixture_uuid.c_str()); row["dmx_mode"]=String::utf8(f.dmx_mode_name.c_str());
        row["geometry_path"]=String::utf8(s.geometry_name.c_str()); row["attribute"]=String::utf8(s.attribute_name.c_str());
        row["channel_function"]=String::utf8(s.function_name.c_str()); row["channel_set"]=String::utf8(b.channel_set_name.c_str());
        row["mode_function"]=String::utf8(b.mode_function_name.c_str()); row["mode_from"]=int64_t(b.mode_from); row["mode_to"]=int64_t(b.mode_to);
        row["gdtf_break"]=b.gdtf_break; row["mvr_break"]=b.gdtf_break-1;
        row["ordered_bytes"]=byte_routes(s,universe_offset);
        const auto master=sources.find(s.activation.master_program_id);
        if (master!=sources.end()) {
            row["mode_master_bytes"]=byte_routes(*master->second,universe_offset);
            row["mode_master_resolution_bits"]=int64_t(master->second->sources.size()*8);
        }
        rows.push_back(row);
    }
    return rows;
}
// Inspects cached native state on demand; refuses worker ownership rather than racing mutable source workspaces.
Dictionary PeravizVisualRuntime::get_shutter_trace(const String &fixture_uuid,int64_t target) const {
    Dictionary result; Array output;
    if (!async_session_.expired()) { result["available"]=false; result["reason"]="Native worker owns the evaluation workspace; select serial diagnostics before requesting a trace."; return result; }
    if (shutter_metadata_.is_empty()) { result["available"]=false; result["reason"]=std::getenv("PERAVIZ_SHUTTER_TRACE")?"No compiled diagnostic route for this selection; inspect compile_diagnostics and the selected UUID/target.":"Enable PERAVIZ_SHUTTER_TRACE=<fixture UUID> before import (optional PERAVIZ_SHUTTER_TRACE_TARGET=<target ID>)."; return result; }
    int32_t fixture=0;
    for (int64_t i=0;i<shutter_metadata_.size();++i) {
        Dictionary row=shutter_metadata_[i];
        if (String(row.get("fixture_uuid",String()))==fixture_uuid && (!target || int64_t(row.get("target_id",0))==target)) { fixture=int32_t(row["fixture_id"]); break; }
    }
    const auto traces=core_->shutter_trace(fixture,int32_t(target));
    for (const auto &trace:traces) {
        Dictionary row;
        for (int64_t i=0;i<shutter_metadata_.size();++i) {
            const Dictionary candidate=shutter_metadata_[i];
            if (int32_t(candidate["target_id"])==trace.target && int32_t(candidate["source_id"])==trace.source && int64_t(candidate["dmx_from"])==trace.from && int64_t(candidate["dmx_to"])==trace.to && int64_t(candidate["mode_from"])==trace.mode_from && int64_t(candidate["mode_to"])==trace.mode_to && int32_t(candidate["binding_activation_id"])==trace.activation_function_id) { row=candidate.duplicate(); break; }
        }
        row["initialized"]=trace.initialized; row["active"]=trace.active; row["raw_dmx"]=int64_t(trace.raw); row["mode_master_raw_dmx"]=trace.master_raw; row["resolution_bits"]=trace.bytes*8;
        row["physical_from"]=trace.physical_from; row["physical_to"]=trace.physical_to; row["resolved_physical"]=trace.active?Variant(trace.physical):Variant();
        const auto &p=trace.parameters;
        row["waveform_id"]=int32_t(p.wave); row["waveform"]=wave_name(p.wave);
        row["envelope_at_trace_time"]=peraviz::gdtf_runtime::shutter_envelope(p,core_->runtime_now_seconds()); row["frequency_hz"]=p.frequency; row["duration_seconds"]=p.duration;
        row["duty_cycle"]=p.duty; row["time_offset"]=p.offset; row["activation_revision"]=p.activation; row["activation_function_id"]=p.function_id;
        row["status"]=p.status==0?"standard":p.status==1?"Peraviz approximation":"unsupported";
        if (trace.active && peraviz::gdtf_runtime::shutter_periodic(p.wave)) {
            Array sampling;
            for (const auto &sample:peraviz::gdtf_runtime::shutter_sampling(p)) {
                Dictionary item; item["fps"]=sample.fps; item["reference_events"]=sample.events; item["events_with_visible_sample"]=sample.visible_events;
                item["missed_event_windows"]=sample.events-sample.visible_events; item["event_window_seconds"]=sample.event_window_seconds; sampling.push_back(item);
            }
            row["sampling_probe"]=sampling;
            row["sampling_policy"]="Frozen parameters, uniform samples relative to activation; exact waveform retained, no temporal smoothing.";
        }
        output.push_back(row);
    }
    result["available"]=fixture>0; result["rows"]=output; result["limit"]=64;
    if (fixture && output.is_empty()) result["reason"]="Shutter route was not installed; inspect compile_diagnostics for unresolved addressing/activation.";
    return result;
}
}
