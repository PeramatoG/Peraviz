#pragma once
#include "presentation/dense_presentation_state.h"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rid.hpp>

namespace godot {
// Main-thread presentation cache only. Godot owns the MultiMesh RIDs and canonical source nodes.
class NativeLensBatches {
public:
    bool install(size_t physical_count,const Array &rids,const Array &owners,const Array &buffers,const Array &scales);
    void clear();
    void invalidate();
    void set_enabled(bool enabled);
    void set_visible(int32_t batch,int32_t instance,bool visible);
    void apply(const peraviz::presentation::DensePresentationState &physical,bool suppress,bool trace);
    void apply_completed(const std::vector<peraviz::presentation::PreparedOutput> &changes,
        const std::vector<peraviz::presentation::RenderValues> &held,bool suppress,bool trace);
    void flush(bool trace=false);
    Dictionary stats() const;
    PackedFloat32Array buffer(int32_t batch) const;
private:
    struct Slot { uint32_t owner=0; float scale=1; bool visible=true; std::array<float,12> transform{}; };
    struct Batch { RID rid; PackedFloat32Array buffer; std::vector<Slot> slots; bool dirty=true; };
    struct Route { uint32_t batch=0,slot=0; };
    void write(uint32_t index,const peraviz::presentation::RenderValues &values);
    std::vector<Batch> batches_;
    std::vector<std::vector<Route>> routes_;
    bool enabled_=true;
    int64_t bytes_=0,submissions_=0,pack_us_=0,submit_us_=0;
};
}
