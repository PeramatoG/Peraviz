#pragma once
#include "presentation/render_group_projection.h"
#include "runtime/visual_frame_schema.h"
#include "runtime/runtime_state_sizes.h"
#include "runtime/parallel_evaluation_prefetch.h"

namespace peraviz::presentation {
struct NativePresentationSizes {
    size_t physical_outputs=0,render_rows=0,state_capacity=0,dirty_capacity=0,high_water=0,buffer_bytes=0;
};
// Immutable while leased by the presentation thread. Physical rows are final resource values, never new authority.
struct CompletedPresentationSnapshot {
    uint64_t session_generation=0,input_generation=0,binding_generation=0;
    int32_t schema_generation=0;
    double runtime_now_seconds=0;
    std::vector<PreparedOutput> physical_rows;
    std::vector<PreparedRenderRow> render_rows;
    runtime::SectionedVisualFrame domains;
    std::vector<int32_t> updated_fixtures;
    std::array<int32_t,9> lighting_summary{};
    int64_t lighting_rows=0,intermediate_bytes_avoided=0;
    size_t unresolved_rows=0,candidates=0;
    runtime::VisualFrameStats runtime_stats;
    runtime::RuntimeStateSizes runtime_sizes{};
    NativePresentationSizes sizes;
    runtime::ParallelEvaluationMetrics parallel;
    int64_t evaluation_us=0,physical_us=0,reduction_us=0,completion_latency_us=0;
    uint64_t submitted_ns=0,completed_ns=0;
    // Reports retained snapshot data buffers, excluding platform thread stacks and container control blocks.
    size_t buffer_bytes() const {
        return physical_rows.capacity()*sizeof(PreparedOutput)+render_rows.capacity()*sizeof(PreparedRenderRow)+
            (domains.descriptors.capacity()+domains.integers.capacity()+updated_fixtures.capacity())*sizeof(int32_t)+domains.floats.capacity()*sizeof(float);
    }
};
} // namespace peraviz::presentation
