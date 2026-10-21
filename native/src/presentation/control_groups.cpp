#include "presentation/control_groups.h"
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
    std::vector<int32_t> dimmer, zoom;
    std::vector<ColorInput> color;
    bool additive = false;
    std::tuple<std::string, bool, bool, double, double, double, double, double, double, double, double, double, double> optics;
    // Orders exact setup authority and optics without hashing collisions or live values.
    bool operator<(const ControlSignature &other) const {
        return std::tie(fixture, dimmer, zoom, color, additive, optics) <
            std::tie(other.fixture, other.dimmer, other.zoom, other.color, other.additive, other.optics);
    }
};
// Uses canonical GDTF ancestry, never fixture names or geometry-name heuristics.
bool controls(const std::string &ancestor, const std::string &beam) {
    return !ancestor.empty() && (ancestor == beam || beam.rfind(ancestor + "/", 0) == 0);
}
}
// Proves open projected sharing from compiled selected-mode authorities; ambiguous
// overlap, any wheel/gobo ownership and unsupported profiles remain individual.
std::vector<PresentationControlGroup> compile_control_groups(const runtime::CompiledRuntimeScene &scene) {
    using namespace runtime;
    std::map<ControlSignature, size_t> signatures;
    std::vector<PresentationControlGroup> groups;
    for (const auto &beam : scene.beam_profiles) {
        ControlSignature s;
        s.fixture = beam.fixture_id;
        s.optics = {beam.beam_type, beam.beam_angle_explicit, beam.field_angle_explicit, beam.effective_luminous_flux_lm, beam.beam_angle_deg, beam.field_angle_deg, beam.beam_radius_m,
            beam.throw_ratio, beam.rectangle_ratio, beam.color_temperature, beam.luminous_flux,
            beam.projected_lumen_scale, beam.emission_lumen_scale};
        bool safe = beam.valid && beam.has_projected_beam && (beam.beam_type == "Wash" || beam.beam_type == "Spot");
        for (double value : {beam.beam_angle_deg, beam.field_angle_deg, beam.beam_radius_m,
                beam.throw_ratio, beam.rectangle_ratio, beam.color_temperature, beam.luminous_flux,
                beam.effective_luminous_flux_lm, beam.projected_lumen_scale, beam.emission_lumen_scale})
            if (!std::isfinite(value)) safe = false;
        // Wheel palettes and projector materials need a later, richer compatibility contract.
        for (const auto &b : scene.wheel_bindings) if (b.fixture_id == beam.fixture_id) safe = false;
        for (const auto &b : scene.gobo_bindings) if (b.fixture_id == beam.fixture_id) safe = false;
        for (const auto &b : scene.gobo_motion_bindings) if (b.fixture_id == beam.fixture_id) safe = false;
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
        // Preserve contributor/input order because native composition order is authoritative.
        if (safe) {
            const auto found = signatures.find(s);
            if (found != signatures.end()) { groups[found->second].physical_ids.push_back(beam.render_target_id); continue; }
            signatures.emplace(s, groups.size());
        }
        groups.push_back({int32_t(groups.size() + 1), {beam.render_target_id}});
    }
    return groups;
}
} // namespace peraviz::presentation
