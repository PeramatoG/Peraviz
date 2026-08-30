#pragma once

#include <cstdint>

namespace peraviz::dmx {

class MonitorCaptureBudget {
public:
    explicit MonitorCaptureBudget(uint32_t captures_per_drain = 4, uint64_t minimum_interval_us = 1000);
    void begin_drain();
    bool try_acquire(uint64_t now_us);
    uint32_t limit() const;

private:
    uint32_t limit_ = 0;
    uint32_t remaining_ = 0;
    uint64_t minimum_interval_us_ = 0;
    uint64_t next_capture_us_ = 0;
};

} // namespace peraviz::dmx
