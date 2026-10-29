#pragma once
#include "presentation/control_groups.h"
#include "presentation/shutter_authority.h"
#include "scene_model.h"
#include <array>

namespace peraviz::presentation {
enum class RenderPresentationClass : int32_t { Individual = 0, Aggregated = 1, Instanced = 2 };
using EmitterVector = std::array<double, 3>;
// Centralized Peraviz realtime optical approximation, never GDTF/MVR semantics.
struct AggregationPolicy {
    static constexpr size_t minimum_members = 3;
    static constexpr double minimum_packing_density = 0.45;
    static constexpr double maximum_direction_spread_degrees = 2.0;
    static constexpr double maximum_angle_difference_degrees = 0.25;
    static constexpr double maximum_radius_ratio = 12.0;
};
struct EmitterSpatialDescriptor {
    int32_t physical_id = 0, fixture_id = 0;
    std::string anchor_geometry_key;
    std::vector<std::string> axis_lineage;
    std::vector<ShutterAuthority> shutter_authority;
    EmitterVector origin{}, direction{0, -1, 0};
    double aperture_radius = 0.0, nominal_flux = 0.0;
    bool reliable = false, approximate_color = false;
    std::string rejection_reason = "geometry_lineage";
};
// A renderer source has exact inverse physical/control membership even when pixels mix.
struct RenderEmitterGroup {
    int32_t id = 0, fixture_id = 0;
    RenderPresentationClass presentation = RenderPresentationClass::Individual;
    std::vector<int32_t> physical_ids, control_group_ids;
    std::string anchor_geometry_key;
    EmitterVector origin{}, direction{0, -1, 0};
    std::string rejection_reason;
    size_t approximate_color_members = 0;
    size_t candidate_members = 0; // Count each optical bucket once, including rejected buckets.
    double nominal_flux = 0.0, aperture_radius = 0.0;
    double beam_angle = 25.0, field_angle = 25.0, packing_density = 0.0;
};
std::vector<EmitterSpatialDescriptor> compile_emitter_spatial_descriptors(const runtime::CompiledRuntimeScene &scene, const SceneModel &model, bool indexed = true);
std::vector<RenderEmitterGroup> compile_render_emitter_groups(const runtime::CompiledRuntimeScene &scene,
        const SceneModel &model, const std::vector<PresentationControlGroup> &controls, bool indexed = true);
} // namespace peraviz::presentation
