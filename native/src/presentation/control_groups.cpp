#include "presentation/control_groups.h"
#include "presentation/wheel_presentation_eligibility.h"
#include <algorithm>
#include <map>
#include <cmath>
#include <tuple>

namespace peraviz::presentation {
namespace {
using namespace runtime;
// Source identity references the complete immutable selected-mode program, including
// DMX bytes, ChannelFunction ranges, activation/ModeMaster and resource ownership.
// Target-local Color IDs deliberately never participate in this signature.
using ColorInput = std::tuple<int32_t, int32_t, double, bool, int32_t, int32_t>;
struct ControlSignature {
    int32_t fixture = 0;
    std::vector<int32_t> dimmer, zoom, approximated_effects;
    std::vector<ColorInput> color;
    std::vector<WheelControlSignature> wheels;
    bool additive = false;
    std::tuple<std::string, bool, bool, double, double, double, double, double, double, double, double, double, double> optics;
    // Orders exact setup authority and optics without hashing collisions or live values.
    bool operator<(const ControlSignature &other) const {
        return std::tie(fixture, dimmer, zoom, approximated_effects, color, wheels, additive, optics) <
            std::tie(other.fixture, other.dimmer, other.zoom, other.approximated_effects, other.color, other.wheels, other.additive, other.optics);
    }
};
// Uses canonical GDTF ancestry, never fixture names or geometry-name heuristics.
bool controls(const std::string &ancestor, const std::string &beam) {
    return !ancestor.empty() && (ancestor == beam || beam.rfind(ancestor + "/", 0) == 0);
}
}
// Proves open projected sharing from compiled selected-mode authorities; ambiguous
// overlap, patterned/projector requirements and unsupported optical profiles remain individual.
ControlGroupAnalysis analyze_control_groups(const runtime::CompiledRuntimeScene &scene) {
    using namespace runtime;
    std::map<ControlSignature, size_t> signatures;
    ControlGroupAnalysis analysis;
    auto &groups = analysis.groups;
    std::map<int32_t, ControlSignature> first_signature;
    for (const auto &beam : scene.beam_profiles) {
        ControlSignature s;
        s.fixture = beam.fixture_id;
        s.approximated_effects=beam.approximated_color_source_programs;
        s.optics = {beam.beam_type, beam.beam_angle_explicit, beam.field_angle_explicit, beam.effective_luminous_flux_lm, beam.beam_angle_deg, beam.field_angle_deg, beam.beam_radius_m,
            beam.throw_ratio, beam.rectangle_ratio, beam.color_temperature, beam.luminous_flux,
            beam.projected_lumen_scale, beam.emission_lumen_scale};
        bool safe = beam.valid && beam.has_projected_beam && (beam.beam_type == "Wash" || beam.beam_type == "Spot");
        for (double value : {beam.beam_angle_deg, beam.field_angle_deg, beam.beam_radius_m,
                beam.throw_ratio, beam.rectangle_ratio, beam.color_temperature, beam.luminous_flux,
                beam.effective_luminous_flux_lm, beam.projected_lumen_scale, beam.emission_lumen_scale})
            if (!std::isfinite(value)) safe = false;
        if (has_projector_dependency(scene, beam)) { safe = false; ++analysis.fallbacks.projector_gobo; }
        const auto wheel=analyze_wheel_presentation(scene,beam);
        s.wheels=wheel.controls;
        if (!wheel.supported()) { safe = false; ++analysis.fallbacks.wheel; }
        for (int32_t id:s.approximated_effects) {
            const auto source=std::find_if(scene.source_programs.begin(),scene.source_programs.end(),[&](const auto &p) { return p.program_id==id; });
            if (source==scene.source_programs.end() || !source->activation.valid) safe=false;
        }
        for (const auto &property : scene.properties) {
            if (property.fixture_id != beam.fixture_id || !controls(property.geometry_name, beam.geometry_path)) continue;
            if (property.semantic == CompiledSemantic::Dimmer || property.semantic == CompiledSemantic::Zoom) {
                if (property.contributors.empty()) safe = false;
                for (const auto &contributor : property.contributors) {
                    const auto program = std::find_if(scene.source_programs.begin(), scene.source_programs.end(),
                        [&](const auto &p) { return p.program_id == contributor.source_program_id; });
                    if (program == scene.source_programs.end() || !program->activation.valid) safe = false;
                }
            }
            if (property.semantic == CompiledSemantic::Dimmer) s.dimmer.push_back(property.property_id);
            if (property.semantic == CompiledSemantic::Zoom) s.zoom.push_back(property.property_id);
        }
        safe = safe && s.dimmer.size() == 1 && s.zoom.size() <= 1;
        int color_targets = 0;
        for (const auto &target : scene.color_targets) {
            if (target.fixture_id != beam.fixture_id || target.beam_render_target_id != beam.render_target_id) continue;
            ++color_targets;
            s.additive = target.additive_source;
            for (const auto &input : target.inputs) {
                const auto program = std::find_if(scene.source_programs.begin(), scene.source_programs.end(),
                    [&](const auto &p) { return p.program_id == input.source_program_id; });
                if (program == scene.source_programs.end() || !program->activation.valid) safe = false;
                s.color.emplace_back(input.source_program_id, int32_t(input.semantic), input.default_value,
                    input.use_normalized_value, input.emitter_resource_id, input.filter_resource_id);
            }
        }
        safe = safe && color_targets <= 1;
        const auto first = first_signature.find(beam.fixture_id);
        if (first == first_signature.end()) first_signature.emplace(beam.fixture_id, s);
        else {
            if (s.dimmer != first->second.dimmer) ++analysis.fallbacks.dimmer;
            if (s.color != first->second.color || s.wheels != first->second.wheels || s.approximated_effects != first->second.approximated_effects || s.additive != first->second.additive) ++analysis.fallbacks.color;
            if (s.optics != first->second.optics || s.zoom != first->second.zoom) ++analysis.fallbacks.optics;
        }
        if (!safe && !has_projector_dependency(scene, beam) && wheel.supported()) ++analysis.fallbacks.ambiguous;
        if (first != first_signature.end()) {
            // Photometric splits are distinct from optical-family splits in the startup audit.
            const auto &base = *std::find_if(scene.beam_profiles.begin(), scene.beam_profiles.end(), [&](const auto &p) { return p.fixture_id == beam.fixture_id; });
            if (base.projected_lumen_scale != beam.projected_lumen_scale || base.emission_lumen_scale != beam.emission_lumen_scale) ++analysis.fallbacks.scaling;
        }
        // Preserve contributor/input order because native composition order is authoritative.
        if (safe) {
            const auto found = signatures.find(s);
            if (found != signatures.end()) { groups[found->second].physical_ids.push_back(beam.render_target_id); continue; }
            signatures.emplace(s, groups.size());
        }
        groups.push_back({int32_t(groups.size() + 1), {beam.render_target_id}});
    }
    return analysis;
}
// Retains the focused control-group API for native consumers needing only membership.
std::vector<PresentationControlGroup> compile_control_groups(const runtime::CompiledRuntimeScene &scene) {
    return analyze_control_groups(scene).groups;
}
// Checks exact compiled Beam ownership; unresolved fixture-local ownership stays conservative.
bool has_projector_dependency(const runtime::CompiledRuntimeScene &scene, const runtime::CompiledBeamOpticalProfile &beam) {
    for (const auto &b : scene.gobo_bindings)
        if ((b.fixture_id <= 0 || b.fixture_id == beam.fixture_id) && (b.beam_render_target_id <= 0 || b.beam_render_target_id == beam.render_target_id)) return true;
    for (const auto &b : scene.gobo_motion_bindings)
        if ((b.fixture_id <= 0 || b.fixture_id == beam.fixture_id) && (b.beam_render_target_id <= 0 || b.beam_render_target_id == beam.render_target_id)) return true;
    return false;
}
} // namespace peraviz::presentation
