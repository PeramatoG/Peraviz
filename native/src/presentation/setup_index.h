#pragma once
#include "runtime/visual_runtime_types.h"
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <set>
#include <cmath>

namespace peraviz::presentation {
// Borrowed immutable setup views. Lifetime never exceeds the compiled scene generation.
struct SetupIndex {
    using Scene = runtime::CompiledRuntimeScene;
    std::set<std::pair<int32_t,int32_t>> projector_owners;
    struct PaletteProof { std::set<int32_t> slots; const char *rejection = nullptr; };
    std::unordered_map<int32_t, PaletteProof> palette_proofs;
    // Validates immutable palette slots once while preserving reference rejection order.
    static PaletteProof validate_palette(const runtime::CompiledWheelPalette &palette) {
        PaletteProof proof;
        for (const auto &slot : palette.slots) {
            if (!slot.uniform_color_presentation || !slot.media_file_name.empty()) { proof.rejection="wheel_unproven_or_patterned_slot"; break; }
            if (slot.slot_index<=0 || !proof.slots.insert(slot.slot_index).second) { proof.rejection="wheel_invalid_palette"; break; }
            for (float value : {slot.linear_red,slot.linear_green,slot.linear_blue,slot.srgb_red,slot.srgb_green,slot.srgb_blue,slot.gain})
                if (!std::isfinite(value) || value<0 || value>1) { proof.rejection="wheel_invalid_palette"; break; }
            if (proof.rejection) break;
        }
        return proof;
    }
    std::unordered_map<int32_t, std::vector<const runtime::CompiledComponentProperty *>> properties;
    std::unordered_map<int32_t, std::vector<const runtime::CompiledColorTargetProgram *>> colors;
    std::unordered_map<int32_t, const runtime::CompiledDmxSourceProgram *> sources;
    std::unordered_map<int32_t, size_t> source_counts, palette_counts;
    std::unordered_map<int32_t, const runtime::CompiledWheelPalette *> palettes;
    std::unordered_map<int32_t, std::vector<const runtime::CompiledWheelTargetBinding *>> wheels;
    // Preserves first-match behavior and records duplicates for conservative validation.
    explicit SetupIndex(const Scene &scene) {
        for (const auto &b : scene.gobo_bindings) projector_owners.emplace(std::max(0,b.fixture_id),std::max(0,b.beam_render_target_id));
        for (const auto &b : scene.gobo_motion_bindings) projector_owners.emplace(std::max(0,b.fixture_id),std::max(0,b.beam_render_target_id));
        properties.reserve(scene.fixtures.size()); colors.reserve(scene.fixtures.size());
        sources.reserve(scene.source_programs.size()); palettes.reserve(scene.wheel_palettes.size());
        for (const auto &p : scene.properties) properties[p.fixture_id].push_back(&p);
        for (const auto &c : scene.color_targets) colors[c.beam_render_target_id].push_back(&c);
        for (const auto &p : scene.source_programs) { sources.emplace(p.program_id, &p); ++source_counts[p.program_id]; }
        for (const auto &p : scene.wheel_palettes) {
            if (palettes.emplace(p.wheel_renderer_id, &p).second) palette_proofs.emplace(p.wheel_renderer_id, validate_palette(p));
            ++palette_counts[p.wheel_renderer_id];
        }
        std::vector<const runtime::CompiledWheelTargetBinding *> unresolved;
        for (const auto &b : scene.wheel_bindings) {
            if (b.fixture_id > 0) wheels[b.fixture_id].push_back(&b);
            else unresolved.push_back(&b);
        }
        if (!unresolved.empty()) {
            for (const auto &beam : scene.beam_profiles) wheels.try_emplace(beam.fixture_id);
            for (auto &[fixture, bindings] : wheels) {
                bindings.insert(bindings.end(), unresolved.begin(), unresolved.end());
                std::sort(bindings.begin(), bindings.end(), std::less<const runtime::CompiledWheelTargetBinding *>{});
            }
        }
    }
    // Unknown owners remain conservative without scanning unrelated scene bindings.
    bool projector(const runtime::CompiledBeamOpticalProfile &beam) const {
        return projector_owners.count({0,0}) || projector_owners.count({0,beam.render_target_id}) ||
            projector_owners.count({beam.fixture_id,0}) || projector_owners.count({beam.fixture_id,beam.render_target_id});
    }
    // Finds exact source identity without relying on dense or globally unique IDs.
    const runtime::CompiledDmxSourceProgram *source(int32_t id) const {
        const auto found = sources.find(id); return found == sources.end() ? nullptr : found->second;
    }
};
}
