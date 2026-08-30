#include "monitor_capture_budget.h"

namespace peraviz::dmx {

// Creates a fixed full-payload capture allowance for each socket drain wake.
MonitorCaptureBudget::MonitorCaptureBudget(uint32_t captures_per_drain, uint64_t minimum_interval_us)
    : limit_(captures_per_drain), remaining_(captures_per_drain), minimum_interval_us_(minimum_interval_us) {}

// Resets the bounded diagnostic allowance at the start of a socket drain.
void MonitorCaptureBudget::begin_drain() {
    remaining_ = limit_;
}

// Acquires one diagnostic capture allowance without blocking scene processing.
bool MonitorCaptureBudget::try_acquire(uint64_t now_us) {
    if (remaining_ == 0 || now_us < next_capture_us_) return false;
    --remaining_;
    next_capture_us_ = now_us + minimum_interval_us_;
    return true;
}

// Returns the immutable full-payload capture limit per drain wake.
uint32_t MonitorCaptureBudget::limit() const {
    return limit_;
}

} // namespace peraviz::dmx
