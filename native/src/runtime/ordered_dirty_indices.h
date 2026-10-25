#pragma once
#include <algorithm>
#include <cstdint>
#include <vector>

namespace peraviz::runtime {
// Reusable dense-index nominations, deduplicated in O(1) and visited in stable ascending order.
class OrderedDirtyIndices {
public:
    // Sizes membership at setup, never in the live nomination loop.
    void install(size_t size) { seen_.assign(size, 0); indices_.clear(); indices_.reserve(size); }
    // Resets only touched membership bits, retaining both contiguous allocations.
    void clear() { for (int index : indices_) seen_[index]=0; indices_.clear(); sorted_=true; }
    // Nominates valid installed indices once without tree-node allocations.
    template<class Iterator> void insert(Iterator first, Iterator last) {
        for (;first!=last;++first) {
            const int index=*first;
            if (index>=0 && size_t(index)<seen_.size() && !seen_[index]) {
                seen_[index]=1; indices_.push_back(index); sorted_=false;
            }
        }
    }
    // Preserves the ordered-set evaluation order, including dependent wheel activation.
    auto begin() { if (!sorted_) { std::sort(indices_.begin(),indices_.end()); sorted_=true; } return indices_.begin(); }
    // Ends the borrowed dirty prefix; no mutation occurs during iteration.
    auto end() { return indices_.end(); }
    // Reports retained deduplication/work-list storage for diagnostic sampling.
    size_t buffer_bytes() const { return seen_.capacity()+indices_.capacity()*sizeof(int); }
private:
    bool sorted_=true;
    std::vector<uint8_t> seen_;
    std::vector<int> indices_;
};
} // namespace peraviz::runtime
