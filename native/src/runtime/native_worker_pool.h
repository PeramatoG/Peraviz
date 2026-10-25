#pragma once
#include "runtime/native_batch_executor.h"
#include <memory>

namespace peraviz::runtime {
// Fixed native threads, coarse static ranges, and bounded observations; no engine API access.
class NativeWorkerPool final : public NativeBatchExecutor {
public:
    explicit NativeWorkerPool(uint32_t workers=0,bool force=false);
    ~NativeWorkerPool();
    NativeWorkerPool(const NativeWorkerPool &)=delete;
    NativeWorkerPool &operator=(const NativeWorkerPool &)=delete;
    static uint32_t recommended_workers();
    bool forced() const override;
    bool worthwhile(size_t count,size_t minimum) const override;
    NativeBatchMetrics run(size_t count,size_t minimum,Function function,void *context,bool trace) override;
    uint32_t worker_count() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
} // namespace peraviz::runtime
