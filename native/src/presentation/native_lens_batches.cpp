#include "presentation/native_lens_batches.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <chrono>
#include <cmath>
#include <algorithm>
namespace godot {
namespace {
// All buffer submissions belong to Godot's main presentation thread.
bool main_thread() { auto *os=OS::get_singleton(); return os->get_thread_caller_id()==os->get_main_thread_id(); }
// Timing is opt-in and separates CPU packing from RenderingServer submission.
int64_t now_us() { return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
}
// Validates a complete cold binding transaction before retaining any borrowed renderer RIDs.
bool NativeLensBatches::install(size_t count,const Array &rids,const Array &owners,const Array &buffers,const Array &scales) {
    if (!main_thread() || rids.size()!=owners.size() || rids.size()!=buffers.size() || rids.size()!=scales.size()) return false;
    if (rids.is_empty()) { clear(); return true; }
    std::vector<Batch> next; std::vector<std::vector<Route>> routes(count);
    for (int64_t b=0;b<rids.size();++b) {
        if (rids[b].get_type()!=Variant::RID || owners[b].get_type()!=Variant::PACKED_INT32_ARRAY ||
            buffers[b].get_type()!=Variant::PACKED_FLOAT32_ARRAY || scales[b].get_type()!=Variant::PACKED_FLOAT32_ARRAY) return false;
        PackedInt32Array ids=owners[b]; PackedFloat32Array data=buffers[b],gain=scales[b];
        if (ids.size()<8 || ids.size()>64 || data.size()!=ids.size()*16 || gain.size()!=ids.size()) return false;
        Batch batch; batch.rid=rids[b]; batch.buffer=data;
        if (!batch.rid.is_valid()) return false;
        for (int64_t s=0;s<ids.size();++s) {
            if (ids[s]<0 || size_t(ids[s])>=count || !std::isfinite(gain[s]) || gain[s]<0) return false;
            Slot slot; slot.owner=uint32_t(ids[s]); slot.scale=gain[s];
            for (int i=0;i<16;++i) if (!std::isfinite(data[s*16+i])) return false;
            std::copy(data.ptr()+s*16,data.ptr()+s*16+12,slot.transform.begin());
            batch.slots.push_back(slot); routes[slot.owner].push_back({uint32_t(b),uint32_t(s)});
        }
        next.push_back(std::move(batch));
    }
    batches_=std::move(next); routes_=std::move(routes); bytes_=submissions_=pack_us_=submit_us_=0; return true;
}
// Revokes all native references before Godot frees batch nodes/resources.
void NativeLensBatches::clear() { decltype(batches_)().swap(batches_); decltype(routes_)().swap(routes_); bytes_=submissions_=pack_us_=submit_us_=0; }
// Forces held-state replay at explicit renderer/diagnostic boundaries.
void NativeLensBatches::invalidate() { for (auto &batch:batches_) batch.dirty=true; }
// Suppression affects only emissive presentation, matching existing physical lens materials.
void NativeLensBatches::set_enabled(bool enabled) {
    enabled_=enabled;
    if (!enabled) for (auto &batch:batches_) {
        auto *data=batch.buffer.ptrw();
        for (size_t slot=0;slot<batch.slots.size();++slot) data[slot*16+15]=0;
    }
    invalidate();
}
// Replays held per-instance energy without reallocating buffers or consulting a worker.
void NativeLensBatches::set_gain(double gain) {
    if (!main_thread() || !std::isfinite(gain)) return;
    gain_=float(std::max(gain,0.0));
    for (auto &batch:batches_) {
        auto *data=batch.buffer.ptrw();
        for (size_t slot=0;slot<batch.slots.size();++slot) {
            const float energy=enabled_?batch.slots[slot].base_energy*gain_*shutter(batch.slots[slot].owner):0.0f;
            if (data[slot*16+15]!=energy) { data[slot*16+15]=energy; batch.dirty=true; }
        }
    }
    flush();
}
// Retains visibility separately from physical values; hidden instances use a zero transform, not transparent fragments.
void NativeLensBatches::set_visible(int32_t b,int32_t s,bool visible) {
    if (!main_thread() || b<0 || size_t(b)>=batches_.size() || s<0 || size_t(s)>=batches_[b].slots.size()) return;
    auto &batch=batches_[b]; auto &slot=batch.slots[s]; if (slot.visible==visible) return;
    slot.visible=visible; auto *data=batch.buffer.ptrw()+s*16;
    for (int i=0;i<12;++i) data[i]=visible?slot.transform[i]:0.0f;
    batch.dirty=true;
}
// Routes completed physical lens RGB and energy directly into predefined instance-custom slots.
void NativeLensBatches::write(uint32_t index,const peraviz::presentation::RenderValues &v) {
    using namespace peraviz::presentation;
    if (index>=routes_.size()) return;
    for (const auto &route:routes_[index]) {
        auto &batch=batches_[route.batch]; auto *data=batch.buffer.ptrw()+route.slot*16+12;
        auto &slot=batch.slots[route.slot]; slot.base_energy=v[MaterialEnergy]*slot.scale;
        const float values[4]={v[Red],v[Green],v[Blue],enabled_?slot.base_energy*gain_*shutter(slot.owner):0.0f};
        for (int i=0;i<4;++i) if (data[i]!=values[i]) { data[i]=values[i]; batch.dirty=true; }
    }
}
// Serial reference publication uses the same buffer writer as asynchronous completed snapshots.
void NativeLensBatches::apply(const peraviz::presentation::DensePresentationState &physical,bool suppress,bool trace) {
    if (batches_.empty() || !main_thread()) return;
    const auto start=trace?now_us():0;
    if (!suppress) for (auto index:physical.dirty_indices()) write(index,physical.render_values(index));
    pack_us_=trace?now_us()-start:0; flush(trace);
}
// Workers never enter this main-thread consumer and no intermediate physical arrays cross through GDScript.
void NativeLensBatches::apply_completed(const std::vector<peraviz::presentation::PreparedOutput> &changes,
        const std::vector<peraviz::presentation::RenderValues> &held,bool suppress,bool trace) {
    if (batches_.empty() || !main_thread()) return;
    const auto start=trace?now_us():0;
    if (!suppress) for (const auto &row:changes) write(row.index,held[row.index]);
    pack_us_=trace?now_us()-start:0; flush(trace);
}
// Submits each changed bounded batch once, reusing its contiguous transform/custom buffer.
void NativeLensBatches::flush(bool trace) {
    bytes_=submissions_=submit_us_=0; if (!main_thread()) return;
    const auto start=trace?now_us():0;
    for (auto &batch:batches_) if (batch.dirty) {
        RenderingServer::get_singleton()->multimesh_set_buffer(batch.rid,batch.buffer);
        batch.dirty=false; bytes_+=batch.buffer.size()*sizeof(float); ++submissions_;
    }
    submit_us_=trace?now_us()-start:0;
}
// Cold counters distinguish actual batch resources and transfers from draw-call measurements.
Dictionary NativeLensBatches::stats() const {
    Dictionary result; size_t instances=0,bytes=0;
    for (const auto &batch:batches_) { instances+=batch.slots.size(); bytes+=batch.buffer.size()*sizeof(float)+batch.slots.capacity()*sizeof(Slot); }
    bytes+=routes_.capacity()*sizeof(std::vector<Route>);
    for (const auto &route:routes_) bytes+=route.capacity()*sizeof(Route);
    result["gpu_lens_batches"]=int64_t(batches_.size()); result["gpu_lens_instances"]=int64_t(instances);
    result["gpu_lens_buffer_bytes"]=int64_t(bytes); result["gpu_lens_transfer_bytes"]=bytes_;
    result["gpu_lens_submissions"]=submissions_; result["gpu_lens_pack_us"]=pack_us_; result["gpu_lens_submit_us"]=submit_us_; return result;
}
// Inspection returns derived GPU presentation data only, for focused equivalence checks.
PackedFloat32Array NativeLensBatches::buffer(int32_t batch) const { return batch>=0 && size_t(batch)<batches_.size()?batches_[batch].buffer:PackedFloat32Array(); }
// Updates existing instance custom alpha only, then coalesces one submission per dirty batch.
size_t NativeLensBatches::apply_shutters(const std::vector<uint32_t> &owners) {
    if (!enabled_) return 0;
    for (uint32_t owner:owners) if (owner<routes_.size()) for (const auto &route:routes_[owner]) {
        auto &batch=batches_[route.batch]; const auto &slot=batch.slots[route.slot];
        const float value=slot.base_energy*gain_*shutter(owner);
        auto *data=batch.buffer.ptrw();
        if (data[route.slot*16+15]!=value) { data[route.slot*16+15]=value; batch.dirty=true; }
    }
    flush(false);
    return size_t(submissions_);
}

}
