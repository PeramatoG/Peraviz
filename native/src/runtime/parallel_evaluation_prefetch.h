#pragma once
#include "runtime/native_batch_executor.h"
#include "runtime/visual_runtime_types.h"
#include <memory>

namespace peraviz::runtime {
class PeravizVisualRuntimeCore;
struct ParallelEvaluationMetrics {
    uint64_t tasks=0, worker_cpu_ns=0, task_wall_ns=0, coordination_ns=0, failures=0;
    uint64_t serial_batches=0, parallel_batches=0,serial_probes=0,policy_backoffs=0,work_units=0;
    uint32_t workers_used=0;
    size_t retained_bytes=0;
};
// Scene-owned pure result slots. The coordinator alone installs these into authoritative caches/maps.
class ParallelEvaluationPrefetch {
public:
    ParallelEvaluationPrefetch(PeravizVisualRuntimeCore &core,NativeBatchExecutor &executor);
    ~ParallelEvaluationPrefetch();
    void prepare();
    void observe_completion();
    bool inputs_prepared(int universe_id) const;
    void inject_sources(int universe_id);
    bool commit_color_inputs(int universe_id,size_t target,bool &changed);
    bool cooked_color(int universe_id,size_t target,CookedEmitterColorValue &output) const;
    bool final_color(int universe_id,int32_t target,CookedEmitterColorValue &output) const;
    ParallelEvaluationMetrics metrics() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
} // namespace peraviz::runtime
