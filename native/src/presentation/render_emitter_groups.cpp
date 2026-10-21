#include "presentation/render_emitter_groups.h"
#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <unordered_map>

namespace peraviz::presentation {
namespace {
using V = EmitterVector;
// Adds spatial quantities in Godot-local metres.
V add(V a, V b) { return {a[0]+b[0], a[1]+b[1], a[2]+b[2]}; }
// Scales a direction or position without changing coordinate conventions.
V mul(V v, double k) { return {v[0]*k, v[1]*k, v[2]*k}; }
// Computes the inner product used by rigidity and direction-spread checks.
double dot(V a, V b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
// Computes physical distance in metres.
double length(V v) { return std::sqrt(dot(v,v)); }
// Normalizes only finite nondegenerate optical directions.
V normalized(V v) { const double n = length(v); return n > 1e-12 ? mul(v,1/n) : V{0,0,0}; }
struct Transform { V x{1,0,0}, y{0,1,0}, z{0,0,1}, origin{}; };
// Rotates a vector through a setup basis.
V rotate(const Transform &t, V v) { return add(add(mul(t.x,v[0]),mul(t.y,v[1])),mul(t.z,v[2])); }
// Composes native, already Godot-converted local transforms.
Transform compose(const Transform &a, const Transform &b) {
    return {rotate(a,b.x),rotate(a,b.y),rotate(a,b.z),add(a.origin,rotate(a,b.origin))};
}
// Converts SceneModel transforms conservatively; uncertain rotations/scales do not aggregate.
bool rigid_transform(const SceneTransform &s, Transform &t) {
    t.origin = {s.position.x,s.position.y,s.position.z};
    if (s.has_basis) t = {{s.basis_x.x,s.basis_x.y,s.basis_x.z},{s.basis_y.x,s.basis_y.y,s.basis_y.z},
        {s.basis_z.x,s.basis_z.y,s.basis_z.z},t.origin};
    else if (s.rotation_degrees.x != 0 || s.rotation_degrees.y != 0 || s.rotation_degrees.z != 0 ||
            s.scale.x != 1 || s.scale.y != 1 || s.scale.z != 1) return false;
    for (V v : {t.x,t.y,t.z,t.origin}) for (double c : v) if (!std::isfinite(c)) return false;
    return std::abs(length(t.x)-1)<1e-4 && std::abs(length(t.y)-1)<1e-4 && std::abs(length(t.z)-1)<1e-4 &&
        std::abs(dot(t.x,t.y))<1e-4 && std::abs(dot(t.x,t.z))<1e-4 && std::abs(dot(t.y,t.z))<1e-4;
}
// Recognizes mechanical lineage from retained Axis tags or actual compiled Pan/Tilt owners.
bool mechanical(const SceneNode &node, const runtime::CompiledRuntimeScene &scene, int32_t fixture) {
    if (node.is_axis) return true;
    for (const auto &p : scene.properties) if (p.fixture_id == fixture && p.geometry_name == node.gdtf_geometry_path &&
        (p.semantic == runtime::CompiledSemantic::Pan || p.semantic == runtime::CompiledSemantic::Tilt)) return true;
    return false;
}
// Zoom authority is static topology; independent apertures are never mixed merely at equal angles.
std::vector<int32_t> zoom_authority(const runtime::CompiledRuntimeScene &scene, const runtime::CompiledBeamOpticalProfile &beam) {
    std::vector<int32_t> ids;
    for (const auto &p : scene.properties) if (p.fixture_id == beam.fixture_id && p.semantic == runtime::CompiledSemantic::Zoom &&
        (p.geometry_name == beam.geometry_path || beam.geometry_path.rfind(p.geometry_name+"/",0)==0)) ids.push_back(p.property_id);
    return ids;
}
// Tests optical family and static geometry; Color/Dimmer source identity intentionally may differ.
bool compatible(const runtime::CompiledRuntimeScene &scene, const runtime::CompiledBeamOpticalProfile &a,
        const runtime::CompiledBeamOpticalProfile &b, const EmitterSpatialDescriptor &x, const EmitterSpatialDescriptor &y) {
    return x.reliable && y.reliable && a.fixture_id == b.fixture_id && x.anchor_geometry_key == y.anchor_geometry_key &&
        x.axis_lineage == y.axis_lineage && a.beam_type == b.beam_type && a.beam_angle_explicit == b.beam_angle_explicit &&
        a.field_angle_explicit == b.field_angle_explicit && a.color_temperature == b.color_temperature &&
        std::abs(a.beam_angle_deg-b.beam_angle_deg) <= AggregationPolicy::maximum_angle_difference_degrees &&
        std::abs(a.field_angle_deg-b.field_angle_deg) <= AggregationPolicy::maximum_angle_difference_degrees &&
        zoom_authority(scene,a) == zoom_authority(scene,b) && dot(x.direction,y.direction) >= std::cos(AggregationPolicy::maximum_direction_spread_degrees*3.141592653589793/180.0);
}
}
// Resolves every Beam relative to its nearest shared mechanical boundary from actual SceneModel ancestry.
std::vector<EmitterSpatialDescriptor> compile_emitter_spatial_descriptors(const runtime::CompiledRuntimeScene &scene, const SceneModel &model) {
    std::unordered_map<std::string,const SceneNode*> by_id, by_key;
    for (const auto &node : model.nodes) { if (!node.node_id.empty()) by_id[node.node_id]=&node; if (!node.gdtf_geometry_key.empty()) by_key[node.gdtf_geometry_key]=&node; }
    std::vector<EmitterSpatialDescriptor> out;
    for (const auto &beam : scene.beam_profiles) {
        EmitterSpatialDescriptor d;
        d.physical_id=beam.render_target_id; d.fixture_id=beam.fixture_id;
        d.aperture_radius=beam.beam_radius_m; d.nominal_flux=beam.effective_luminous_flux_lm;
        const auto found=by_key.find(beam.geometry_key);
        if (found==by_key.end()) { out.push_back(d); continue; }
        std::vector<const SceneNode*> chain;
        std::set<std::string> visited;
        const SceneNode *node=found->second;
        while (node && !node->gdtf_geometry_key.empty() && node->gdtf_geometry_key.rfind(beam.fixture_uuid+"/",0)==0 && visited.insert(node->node_id).second) {
            chain.push_back(node);
            const auto parent=by_id.find(node->parent_id);
            node=parent==by_id.end()?nullptr:parent->second;
        }
        std::reverse(chain.begin(),chain.end());
        if (chain.empty() || chain.front()->gdtf_geometry_path.find('/')!=std::string::npos || chain.front()->node_id.empty()) { out.push_back(d); continue; }
        size_t anchor=0;
        for (size_t i=0;i<chain.size();++i) if (mechanical(*chain[i],scene,beam.fixture_id)) { anchor=i; d.axis_lineage.push_back(chain[i]->gdtf_geometry_key); }
        d.anchor_geometry_key=chain[anchor]->gdtf_geometry_key;
        Transform relative;
        bool rigid=true;
        for (size_t i=anchor+1;i<chain.size();++i) {
            Transform local;
            if (!rigid_transform(chain[i]->local_transform,local)) { rigid=false; break; }
            relative=compose(relative,local);
        }
        d.origin=relative.origin;
        // Main's emitter anchor is rotated -90 degrees around X: its -Z light axis is local -Y.
        d.direction=normalized(rotate(relative,{0,-1,0}));
        d.reliable=rigid && beam.valid && beam.has_projected_beam && (beam.beam_type=="Wash" || beam.beam_type=="Spot") &&
            beam.beam_radius_source=="explicit" && std::isfinite(d.aperture_radius) && d.aperture_radius>0 &&
            std::isfinite(d.nominal_flux) && d.nominal_flux>0 && !has_projector_dependency(scene,beam) && !has_wheel_dependency(scene,beam);
        out.push_back(d);
    }
    return out;
}
// Classifies compact co-directional sources once; separated cells and ambiguous geometry stay individual.
std::vector<RenderEmitterGroup> compile_render_emitter_groups(const runtime::CompiledRuntimeScene &scene,
        const SceneModel &model, const std::vector<PresentationControlGroup> &controls) {
    const auto descriptors=compile_emitter_spatial_descriptors(scene,model);
    std::unordered_map<int32_t,int32_t> control_by_id;
    for (const auto &c:controls) for (int32_t id:c.physical_ids) control_by_id[id]=c.id;
    std::vector<std::vector<size_t>> candidates;
    for (size_t i=0;i<descriptors.size();++i) {
        bool joined=false;
        if (descriptors[i].reliable) for (auto &candidate:candidates) {
            bool fits=true;
            for (size_t member:candidate) if (!compatible(scene,scene.beam_profiles[member],scene.beam_profiles[i],descriptors[member],descriptors[i])) { fits=false; break; }
            if (fits) { candidate.push_back(i); joined=true; break; }
        }
        if (!joined) candidates.push_back({i});
    }
    std::vector<RenderEmitterGroup> out;
    for (const auto &candidate:candidates) {
        RenderEmitterGroup group;
        const auto &first=descriptors[candidate.front()];
        group.fixture_id=first.fixture_id; group.anchor_geometry_key=first.anchor_geometry_key;
        group.beam_angle=scene.beam_profiles[candidate.front()].beam_angle_deg;
        group.field_angle=scene.beam_profiles[candidate.front()].field_angle_deg;
        double area=0,largest_radius=0;
        V direction{};
        for (size_t i:candidate) {
            const auto &d=descriptors[i]; group.nominal_flux+=d.nominal_flux;
            group.origin=add(group.origin,mul(d.origin,d.nominal_flux)); direction=add(direction,mul(d.direction,d.nominal_flux));
            area+=d.aperture_radius*d.aperture_radius; largest_radius=std::max(largest_radius,d.aperture_radius);
            group.physical_ids.push_back(d.physical_id);
            group.control_group_ids.push_back(control_by_id[d.physical_id]);
        }
        if (group.nominal_flux>0) group.origin=mul(group.origin,1/group.nominal_flux);
        group.direction=normalized(direction);
        double depth=0;
        for (size_t i:candidate) {
            const auto offset=add(descriptors[i].origin,mul(group.origin,-1));
            group.aperture_radius=std::max(group.aperture_radius,length(offset)+descriptors[i].aperture_radius);
            depth=std::max(depth,std::abs(dot(offset,group.direction)));
        }
        group.packing_density=group.aperture_radius>0?area/(group.aperture_radius*group.aperture_radius):0;
        const bool compact=candidate.size()>=AggregationPolicy::minimum_members && first.reliable &&
            group.packing_density>=AggregationPolicy::minimum_packing_density && group.aperture_radius<=largest_radius*AggregationPolicy::maximum_radius_ratio && depth<=largest_radius;
        if (compact) {
            group.id=int32_t(out.size()+1); group.presentation=RenderPresentationClass::Aggregated;
            std::sort(group.control_group_ids.begin(),group.control_group_ids.end());
            group.control_group_ids.erase(std::unique(group.control_group_ids.begin(),group.control_group_ids.end()),group.control_group_ids.end());
            out.push_back(std::move(group));
        } else for (size_t i:candidate) {
            RenderEmitterGroup single;
            single.id=int32_t(out.size()+1); single.fixture_id=descriptors[i].fixture_id;
            single.physical_ids={descriptors[i].physical_id}; single.control_group_ids={control_by_id[descriptors[i].physical_id]};
            out.push_back(std::move(single));
        }
    }
    return out;
}
} // namespace peraviz::presentation
