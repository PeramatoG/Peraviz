#pragma once
#include <cstddef>
#include <cstdint>

namespace peraviz::runtime {
struct NativeBatchMetrics {
    uint64_t tasks=0, worker_cpu_ns=0, wall_ns=0, coordination_ns=0, failures=0;
    uint32_t workers_used=0;
    bool parallel=false, cpu_clock_supported=false;
};
// Called only by the native coordinator; callbacks own disjoint [begin,end) result ranges.
class NativeBatchExecutor {
public:
    using Function=void (*)(void *,size_t,size_t);
    virtual ~NativeBatchExecutor() = default;
    // Diagnostic/test forcing never changes numerical interpretation or ownership.
    virtual bool forced() const { return false; }
    virtual bool worthwhile(size_t count,size_t minimum) const = 0;
    virtual NativeBatchMetrics run(size_t count,size_t minimum,Function function,void *context,bool trace)=0;
};
} // namespace peraviz::runtime
