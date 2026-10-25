#pragma once
#include "presentation/completed_presentation_snapshot.h"
#include "runtime/peraviz_visual_runtime.h"
#include <memory>

namespace peraviz::presentation {
struct AsyncEvaluationOptions {
    uint32_t workers=0;
    bool force=false,trace=false;
};
// One native coordinator owns semantic/physical state; the main thread only leases completed snapshots.
class AsyncPresentationPipeline {
public:
    AsyncPresentationPipeline(std::shared_ptr<runtime::PeravizVisualRuntimeCore> core,
            DensePresentationState &&state,RenderGroupProjection &&projection,AsyncEvaluationOptions options={},
            runtime::NativeBatchExecutor *test_executor=nullptr);
    ~AsyncPresentationPipeline();
    static bool eligible(const runtime::PeravizVisualRuntimeCore &core,AsyncEvaluationOptions options={});
    bool submit(int universe,const uint8_t *data,int length,uint64_t received_us=0);
    bool flush_input();
    const CompletedPresentationSnapshot *try_acquire();
    void release(const CompletedPresentationSnapshot *snapshot);
    void set_trace(bool enabled);
    bool active() const;
    bool failed() const;
    void stop();
    void reclaim(DensePresentationState &state,RenderGroupProjection &projection);
    uint64_t binding_generation() const;
    int32_t schema_generation() const;
    NativePresentationSizes initial_sizes() const;
    size_t input_buffer_bytes() const;
    uint32_t worker_count() const;
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
} // namespace peraviz::presentation
