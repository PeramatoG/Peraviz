#pragma once

#include "runtime/peraviz_visual_runtime.h"
#include "runtime/realtime_dmx_coordinator.h"
#include "presentation/async_presentation_pipeline.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class PeravizVisualRuntime : public RefCounted {
    GDCLASS(PeravizVisualRuntime, RefCounted)

protected:
    static void _bind_methods();

public:
    ~PeravizVisualRuntime();
    void clear();
    void install_compiled_scene(const Dictionary &packed_scene);
    // A deterministic clock may be injected only while the runtime has exclusive main-thread ownership.
    bool set_runtime_now_seconds_for_testing(double seconds) { if (!async_session_.expired()) return false; core_->set_runtime_now_seconds_for_testing(seconds); return true; }
    void submit_universe_frame(int universe_id, const PackedByteArray &data);
    Dictionary consume_latest_visual_frame();
    Dictionary get_visual_frame_schema() const;
    Dictionary get_stats() const;
    Dictionary get_state_sizes() const;
    void set_performance_trace_enabled(bool enabled);
    peraviz::runtime::PeravizVisualRuntimeCore &native_core();
    std::shared_ptr<peraviz::runtime::PeravizVisualRuntimeCore> native_core_handle() const;
    int32_t schema_generation() const;
    // Checks exclusive native execution ownership before a presentation session is constructed.
    bool async_available() const { return async_session_.expired(); }
    void attach_async(const std::shared_ptr<peraviz::presentation::AsyncPresentationPipeline> &session);
    void accept_completed(const peraviz::presentation::CompletedPresentationSnapshot &snapshot);
    bool retire_async(const peraviz::presentation::AsyncPresentationPipeline *expected=nullptr);
    peraviz::runtime::RealtimePumpResult pump_mailbox(peraviz::dmx::RealtimeUniverseMailbox &mailbox,bool install);
    void submit_native_frame(int universe,const uint8_t *data,int length,uint64_t received_us=0);

private:
    static Dictionary stats_to_dictionary(const peraviz::runtime::VisualFrameStats &stats);

    bool performance_trace_enabled_ = false;
    std::shared_ptr<peraviz::runtime::PeravizVisualRuntimeCore> core_=std::make_shared<peraviz::runtime::PeravizVisualRuntimeCore>();
    std::weak_ptr<peraviz::presentation::AsyncPresentationPipeline> async_session_;
    peraviz::runtime::VisualFrameSchema schema_cache_=core_->schema();
    peraviz::runtime::VisualFrameStats stats_cache_;
    peraviz::runtime::RuntimeStateSizes sizes_cache_=core_->state_sizes();
    std::vector<std::pair<uint16_t,std::vector<uint16_t>>> interests_cache_;
};

} // namespace godot
