#pragma once
#include "scene_model.h"
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include <cstdint>

namespace peraviz::gdtf_runtime {
// Resolves one-based GDTF break n to MVR's zero-based break identity n-1, never an offset.
inline SceneModel::FixturePatchAddress source_patch(const SceneModel::FixturePatch &patch, int gdtf_break) {
    for (const auto &entry : patch.addresses) if (entry.mvr_break==gdtf_break-1) return entry;
    if (patch.addresses.empty() && gdtf_break==1) return {0,patch.mvr_universe,patch.mvr_address,0,false};
    return {};
}

// Rejects the complete fixture when a source or dependency cannot be represented safely.
inline std::string validate_resolved_addresses(const SceneModel::FixturePatch &patch,
                                               const CompiledGdtfFixtureType &fixture, int universe_offset) {
    const int base=patch.mvr_universe>0 ? patch.mvr_universe : patch.addresses.front().universe;
    const auto representative=static_cast<int64_t>(base)+universe_offset;
    if (representative<0 || representative>32767) return "Resolved fixture universe is outside the Art-Net Port-Address range.";
    for (const auto &program : fixture.channel_programs) {
        const auto entry=source_patch(patch,program.dmx_break);
        if (entry.universe<1 || entry.address<1 || entry.address>512)
            return "Missing MVR patch for GDTF break "+std::to_string(program.dmx_break)+" (MVR break "+std::to_string(program.dmx_break-1)+").";
        const auto universe=static_cast<int64_t>(entry.universe)+universe_offset;
        if (universe<0 || universe>32767) return "Resolved universe is outside the Art-Net Port-Address range.";
        for (const int offset : program.dmx_offsets_1_based)
            if (offset<1 || static_cast<int64_t>(entry.address)+offset-2>=512) return "Patch-adjusted ordered byte source exceeds its 512-slot break.";
    }
    return {};
}
}
