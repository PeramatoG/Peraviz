#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "dmx/artnet_receiver.h"
#include "runtime/realtime_dmx_coordinator.h"

#include <memory>
#include <array>

namespace godot {

class PeravizVisualRuntime;

class PeravizDmxReceiver : public RefCounted {
    GDCLASS(PeravizDmxReceiver, RefCounted)

protected:
    static void _bind_methods();

public:
    PeravizDmxReceiver();
    ~PeravizDmxReceiver() override;

    bool start(const String &bind_ip = "0.0.0.0", int port = 6454);
    void stop();
    bool is_running() const;
    String get_last_error() const;

    PackedInt32Array get_active_universes(int active_window_ms = 2000) const;
    Dictionary get_stats() const;
    PackedByteArray get_universe_data(int universe_id) const;
    Dictionary get_universe_metadata(int universe_id) const;
    bool configure_visual_runtime(Ref<PeravizVisualRuntime> runtime);
    int pump_visual_runtime(Ref<PeravizVisualRuntime> runtime);
    void set_monitor_capture_enabled(bool enabled);
    void record_godot_apply_completion();

private:
    static uint64_t now_microseconds();

    std::unique_ptr<peraviz::dmx::ArtNetReceiver> receiver_;
    uint64_t scene_states_consumed_ = 0;
    int rehydrated_states_pending_ = 0;
    peraviz::runtime::RealtimeDmxCoordinator coordinator_;
    std::array<uint64_t, 32> rx_to_native_buckets_ {};
    std::array<uint64_t, 32> native_to_apply_buckets_ {};
    uint64_t rx_to_native_max_us_ = 0;
    uint64_t native_to_apply_max_us_ = 0;
    uint64_t last_native_pump_us_ = 0;

    static void observe_latency(std::array<uint64_t, 32> &buckets, uint64_t value_us, uint64_t &maximum_us);
    static uint64_t latency_percentile(const std::array<uint64_t, 32> &buckets, double percentile);
};

} // namespace godot
