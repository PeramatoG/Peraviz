#pragma once

#include <algorithm>
#include <array>
#include <cstdint>

namespace peraviz::dmx {

// Fixed storage, owned exclusively by the Godot/main thread, never the RX worker.
struct LatencyHistogram {
    std::array<uint64_t, 32> buckets {};
    uint64_t samples = 0;
    uint64_t maximum_us = 0;

    // Records a sample without allocating or retaining individual observations.
    void observe(uint64_t value_us) {
        size_t bucket = 0;
        while (bucket + 1 < buckets.size() && value_us > (uint64_t {1} << bucket)) ++bucket;
        ++buckets[bucket];
        ++samples;
        maximum_us = std::max(maximum_us, value_us);
    }

    // Returns a percentile's bucket upper bound, clamped to the observed maximum.
    uint64_t percentile(unsigned percent) const {
        if (samples == 0) return 0;
        const uint64_t target = (samples / 100) * percent + ((samples % 100) * percent + 99) / 100;
        uint64_t count = 0;
        for (size_t index = 0; index < buckets.size(); ++index) {
            count += buckets[index];
            if (count >= target) return std::min(uint64_t {1} << index, maximum_us);
        }
        return maximum_us;
    }
};

struct LatencyWindows {
    LatencyHistogram lifetime;
    LatencyHistogram interval;

    // Updates lifetime statistics and the opt-in reporting interval in fixed storage.
    void observe(uint64_t value_us, bool trace_enabled) {
        lifetime.observe(value_us);
        if (trace_enabled) interval.observe(value_us);
    }

    // Transfers interval ownership to a reporter without affecting lifetime statistics.
    LatencyHistogram consume_interval() {
        const LatencyHistogram result = interval;
        interval = {};
        return result;
    }
};

} // namespace peraviz::dmx
