#include "runtime/peraviz_visual_runtime.h"

namespace peraviz::runtime {

// Samples state ownership and pending payload sizes at a diagnostic reporting boundary.
RuntimeStateSizes PeravizVisualRuntimeCore::state_sizes() const {
    size_t sources=0,consumers=0,edges=0,plan_bytes=0,workspace_bytes=0;
    size_t pending = 0;
    size_t payload_bytes = 0;
    for (const auto &[id, universe] : universes_) {
        if (universe.has_pending_frame) ++pending;
        payload_bytes += universe.latest_frame.capacity();
        sources+=universe.plan.source_count(); consumers+=universe.plan.consumer_count(); edges+=universe.plan.dependency_count();
        plan_bytes+=universe.plan.immutable_bytes(); workspace_bytes+=universe.plan.workspace_bytes();
    }
    return {{{"universes", universes_.size()},
        {"pending_universes", pending}, {"payload_capacity_bytes", payload_bytes},
        {"transforms", transform_state_by_fixture_.size()},
        {"properties", property_state_by_property_.size()},
        {"base_colors", base_color_state_by_target_.size()},
        {"colors", color_state_by_target_.size()}, {"wheels", wheel_state_by_physical_key_.size()},
        {"gobo_selections", gobo_selection_state_by_layer_.size()},
        {"gobo_rotations", gobo_rotation_state_by_layer_.size()},
        {"source_programs", source_programs_by_id_.size()},
        {"diagnostics", diagnostics_.size()},
        {"diagnostic_capacity", diagnostics_.capacity()},
        {"evaluation_sources",sources}, {"evaluation_consumers",consumers}, {"evaluation_edges",edges},
        {"evaluation_plan_bytes",plan_bytes+mapping_definitions_*sizeof(SourceValueMapping)},
        {"evaluation_workspace_bytes",workspace_bytes},
        {"evaluation_mapping_definitions",mapping_definitions_}, {"evaluation_fixture_modes",fixture_mode_definitions_}}};
}

} // namespace peraviz::runtime
