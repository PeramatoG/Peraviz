#pragma once
#include "presentation/dense_presentation_state.h"
#include "presentation/render_emitter_groups.h"

namespace peraviz::presentation {
struct PreparedRenderRow {
    uint32_t index = 0, mask = 0;
    RenderValues values{};
};
struct MemberContribution {
    RenderValues values{};
    double energy = 0, red = 0, green = 0, blue = 0, intensity = 0;
    bool valid = false;
};
struct RenderRowAccumulator {
    double energy = 0, red = 0, green = 0, blue = 0, intensity = 0;
    uint32_t representative = 0, mask = 0;
    RenderPresentationClass presentation = RenderPresentationClass::Individual;
    RenderValues previous{};
    bool committed = false;
};
static_assert(std::is_trivially_copyable<MemberContribution>::value, "Live contributions must remain contiguous POD");
static_assert(std::is_trivially_copyable<RenderRowAccumulator>::value, "Live accumulators must remain contiguous POD");
// Derived presentation state only; physical state and semantic IDs never move here.
class RenderGroupProjection {
public:
    bool install(const std::vector<uint32_t> &physical_to_row, const std::vector<RenderPresentationClass> &classes);
    void clear();
    void invalidate();
    void prepare(const DensePresentationState &physical);
    // Reports renderer capacity independently of physical count.
    size_t row_count() const { return rows_.size(); }
    // Reports exact retained physical membership.
    size_t member_count() const { return members_.size(); }
    // Borrows only the compact dirty renderer prefix.
    const std::vector<PreparedRenderRow> &prepared() const { return prepared_; }
    // Borrows setup-generation inverse physical-to-render membership.
    const std::vector<uint32_t> &membership() const { return physical_to_row_; }
    // Borrows an already composed physical member value for completed resource publication.
    const RenderValues &member_values(uint32_t index) const { return members_[index].values; }
    size_t buffer_bytes() const;
private:
    std::vector<uint32_t> physical_to_row_, dirty_rows_;
    std::vector<MemberContribution> members_;
    std::vector<RenderRowAccumulator> rows_;
    std::vector<PreparedRenderRow> prepared_;
};
} // namespace peraviz::presentation
