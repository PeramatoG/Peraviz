#pragma once
#include "runtime/visual_runtime_types.h"
#include <unordered_map>
#include <unordered_set>

namespace peraviz::runtime {
// Classifies generation-owned physical intensity before the numeric codec drops geometry paths.
inline void classify_additive_intensity(CompiledRuntimeScene &scene) {
    struct DimmerOwners {
        std::unordered_set<std::string> paths;
        std::unordered_set<int32_t> targets;
    };
    std::unordered_map<int32_t, DimmerOwners> dimmers;
    for (const auto &property : scene.properties) if (property.semantic == CompiledSemantic::Dimmer) {
        auto &owners = dimmers[property.fixture_id];
        if (!property.geometry_name.empty()) owners.paths.insert(property.geometry_name);
        owners.targets.insert(property.render_target_id);
    }
    for (auto &target : scene.color_targets) {
        bool red = false, green = false, blue = false;
        for (const auto &input : target.inputs) {
            red = red || input.semantic == CompiledSemantic::ColorAddRed;
            green = green || input.semantic == CompiledSemantic::ColorAddGreen;
            blue = blue || input.semantic == CompiledSemantic::ColorAddBlue;
        }
        bool explicit_dimmer = false;
        const auto owner = dimmers.find(target.fixture_id);
        if (owner != dimmers.end()) {
            explicit_dimmer = owner->second.targets.count(target.beam_render_target_id) != 0;
            std::string path = target.geometry_name;
            while (!path.empty() && !explicit_dimmer) {
                explicit_dimmer = owner->second.paths.count(path) != 0;
                const auto separator = path.rfind('/');
                if (separator == std::string::npos) break;
                path.resize(separator);
            }
        }
        target.implicit_intensity = target.additive_source && red && green && blue && !explicit_dimmer;
    }
}
} // namespace peraviz::runtime
