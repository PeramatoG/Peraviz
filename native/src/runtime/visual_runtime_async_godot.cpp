#include "runtime/peraviz_visual_runtime_godot.h"
#include "dmx/realtime_subscription.h"

namespace godot {
// Swap a validated independent plan while the main thread exclusively owns the installed core.
bool PeravizVisualRuntime::replace_mode_plan(std::shared_ptr<peraviz::runtime::PeravizVisualRuntimeCore> next,
        const peraviz::runtime::CompiledRuntimeScene &scene, int32_t fixture_id, bool same_geometry,
        const Dictionary &payload) {
    if (!next || !async_available()) return false;
    next->set_performance_trace_enabled(performance_trace_enabled_);
    next->inherit_mode_input(*core_, fixture_id, scene, same_geometry);
    core_ = std::move(next);
    shutter_metadata_ = payload.get("shutter_trace_metadata", Array());
    schema_cache_ = core_->schema();
    interests_cache_ = core_->realtime_interest_offsets();
    stats_cache_ = core_->stats();
    sizes_cache_ = core_->state_sizes();
    return true;
}
// Refresh transport interests after an exclusive same-topology routing transaction.
bool PeravizVisualRuntime::replace_routes(const peraviz::runtime::CompiledRuntimeScene &scene) {
    if (!async_available() || !core_->replace_routes(scene)) return false;
    interests_cache_ = core_->realtime_interest_offsets();
    stats_cache_ = core_->stats(); sizes_cache_ = core_->state_sizes();
    return true;
}
// Retires native jobs before this Godot wrapper can release borrowed scene definitions.
PeravizVisualRuntime::~PeravizVisualRuntime() { retire_async(); }
// Shares native lifetime only; the coordinator never owns or calls a Godot wrapper.
std::shared_ptr<peraviz::runtime::PeravizVisualRuntimeCore> PeravizVisualRuntime::native_core_handle() const { return core_; }
// Reads immutable setup metadata without touching running evaluation state.
int32_t PeravizVisualRuntime::schema_generation() const { return schema_cache_.schema_generation; }
// Binds input submission to the active native scene session at an exclusive control boundary.
void PeravizVisualRuntime::attach_async(const std::shared_ptr<peraviz::presentation::AsyncPresentationPipeline> &session) {
    async_session_=session;
}
// Copies diagnostic counters only from the completed generation just accepted by the presentation thread.
void PeravizVisualRuntime::accept_completed(const peraviz::presentation::CompletedPresentationSnapshot &snapshot) {
    stats_cache_=snapshot.runtime_stats; sizes_cache_=snapshot.runtime_sizes;
}
// Stops publication first, then safely retires borrowed definitions at scene/setup/shutdown boundaries.
bool PeravizVisualRuntime::retire_async(const peraviz::presentation::AsyncPresentationPipeline *expected) {
    if (const auto session=async_session_.lock()) {
        if (expected && expected!=session.get()) return false;
        session->stop();
    }
    async_session_.reset(); stats_cache_=core_->stats(); sizes_cache_=core_->state_sizes(); return true;
}
// Keeps producer-owned raw input separate from coordinator-owned semantic state.
void PeravizVisualRuntime::submit_native_frame(int universe,const uint8_t *data,int length,uint64_t received_us) {
    if (const auto session=async_session_.lock()) { session->submit(universe,data,length,received_us); return; }
    core_->submit_universe_frame(universe,data,length);
}
// Drains the existing receiver mailbox without routing input through GDScript or running worker waits.
peraviz::runtime::RealtimePumpResult PeravizVisualRuntime::pump_mailbox(peraviz::dmx::RealtimeUniverseMailbox &mailbox,bool install) {
    using namespace peraviz;
    if (install) mailbox.set_subscription(dmx::RealtimeSubscription::build(interests_cache_));
    const auto frames=install?mailbox.held_states():mailbox.consume_dirty_frames();
    runtime::RealtimePumpResult result;
    result.states_submitted=int(frames.size());
    for (const auto &frame:frames) {
        submit_native_frame(frame.universe_id,frame.data.data(),frame.length,frame.last_rx_us);
        if (frame.last_rx_us && (!result.oldest_receive_us || frame.last_rx_us<result.oldest_receive_us)) result.oldest_receive_us=frame.last_rx_us;
    }
    return result;
}
} // namespace godot
