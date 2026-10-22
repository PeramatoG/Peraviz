#pragma once
#include "runtime/peraviz_visual_runtime.h"
#include "presentation/render_group_projection.h"
#include <chrono>

namespace peraviz::presentation {
// Single serial calculation transaction. Owns scratch only, never physical state.
// Future native tasks must join before returning this complete borrowed snapshot.
class DirectPresentationPipeline {
public:
    // Rejects stale bindings before consuming the latest-state mailbox.
    bool consume(runtime::PeravizVisualRuntimeCore &runtime, DensePresentationState &state,
            RenderGroupProjection &projection, uint64_t generation, int32_t schema_generation, bool trace) {
        if (generation != state.generation() || schema_generation != runtime.schema().schema_generation ||
                projection.member_count() != state.bindings().size()) return false;
        const auto start = trace ? Clock::now() : Clock::time_point{};
        runtime.consume_latest_visual_frame(frame_);
        const auto evaluated = trace ? Clock::now() : Clock::time_point{};
        if (!state.compose_sections(generation, frame_.descriptors.data(), frame_.descriptors.size(),
                frame_.integers.data(), frame_.integers.size(), frame_.floats.data(), frame_.floats.size())) return false;
        const auto composed = trace ? Clock::now() : Clock::time_point{};
        projection.prepare(state);
        if (trace) {
            evaluation_us = elapsed(start, evaluated);
            physical_us = elapsed(evaluated, composed);
            reduction_us = elapsed(composed, Clock::now());
        }
        return true;
    }
    // Borrows independent domain sections from this transaction until the next consume.
    const runtime::SectionedVisualFrame &frame() const { return frame_; }
    // Retires scene-sized scratch on scene replacement.
    void clear() { frame_ = {}; }
    int64_t evaluation_us = 0, physical_us = 0, reduction_us = 0;
private:
    using Clock = std::chrono::steady_clock;
    // Converts optional trace clock intervals to microseconds.
    static int64_t elapsed(Clock::time_point a, Clock::time_point b) {
        return std::chrono::duration_cast<std::chrono::microseconds>(b-a).count();
    }
    runtime::SectionedVisualFrame frame_;
};
} // namespace peraviz::presentation
