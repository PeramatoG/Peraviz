#pragma once
#include "presentation/dense_presentation_state.h"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {
class RenderingServer;
// Main-thread Godot boundary: retained material RIDs never own or inspect SceneTree nodes.
class PresentationMaterialBindings {
public:
    bool install(size_t physical_count, const Array &rids, const PackedInt32Array &owners,
        const PackedFloat32Array &scales, const PackedInt32Array &routes, bool surface = false);
    bool install_surface_instances(const Array &instances);
    void set_surface_visible(int32_t index, bool allowed);
    void clear();
    size_t set_enabled(bool enabled);
    void invalidate();
    void apply(const peraviz::presentation::DensePresentationState &physical, bool suppress_writes = false);
    void apply_completed(const std::vector<peraviz::presentation::PreparedOutput> &changes,
        const std::vector<peraviz::presentation::RenderValues> &held,bool suppress_writes=false);
    PackedFloat32Array values(const RID &rid) const;
    // Reports actual material setters in the last applied batch.
    size_t writes() const { return writes_; }
    // Reports retained unique material RIDs without resource discovery.
    size_t size() const { return bindings_.size(); }
    size_t active() const;
    // Counts physical Color-domain candidates in the most recent batch.
    size_t color_outputs() const { return color_outputs_; }
    // Counts deduplicated material candidates before cached-value filtering.
    size_t affected() const { return dirty_.size(); }
    // Counts candidate RIDs whose committed RGB and energy already match.
    size_t unchanged() const { return unchanged_; }
    // Reports redundant shared-RID setters avoided in that batch.
    size_t avoided() const { return avoided_; }
private:
    struct SurfaceInstance { RID rid; bool allowed=true, visible=false, known=false; };
    void update_surface_visible(size_t index, bool force=false);
    std::vector<SurfaceInstance> surface_instances_;
    struct Binding { RID rid; uint32_t owner=0, users=0; float scale=1, red=-1, green=-1, blue=-1, energy=-1; bool dirty=false; };
    void nominate(uint32_t index,uint32_t mask);
    void write(Binding &binding,const peraviz::presentation::RenderValues &values,RenderingServer *server);
    std::vector<Binding> bindings_;
    std::vector<std::vector<uint32_t>> routes_;
    std::vector<uint32_t> dirty_;
    size_t writes_=0, avoided_=0, color_outputs_=0, unchanged_=0;
    bool enabled_=true, surface_=false;
    const StringName emission_{"emission"}, energy_{"emission_energy"};
};
}
