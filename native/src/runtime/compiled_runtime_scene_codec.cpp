#include "runtime/compiled_runtime_scene_codec.h"

#include <limits>

namespace peraviz::runtime {
namespace {

// Appends a float and returns its stable packed index.
int32_t push_float(std::vector<float> &values, double value) {
    values.push_back(static_cast<float>(value));
    return static_cast<int32_t>(values.size() - 1);
}

// Reads one packed float index with a deterministic fallback.
double read_float(const std::vector<float> &values, int32_t index, double fallback) {
    return index >= 0 && static_cast<size_t>(index) < values.size() ? values[static_cast<size_t>(index)] : fallback;
}

class Decoder {
public:
    // Creates a bounds-checked reader over one packed setup payload.
    Decoder(const std::vector<int32_t> &packed_integers, const std::vector<float> &packed_floats)
        : integers(packed_integers), floats(packed_floats) {}

    // Reads one integer or marks the payload as truncated.
    int32_t read() {
        if (cursor >= integers.size()) {
            fail("PVZ-PACKED-SCENE-TRUNCATED: integer payload ended before the "
                 "declared records.");
            return 0;
        }
        return integers[cursor++];
    }

    // Reserves a complete record before any of its fields are consumed.
    bool require(size_t count) {
        if (!valid || count > integers.size() - cursor) {
            fail("PVZ-PACKED-SCENE-TRUNCATED: declared record exceeds the integer "
                 "payload.");
            return false;
        }
        return true;
    }

    // Records the first deterministic codec failure.
    void fail(const std::string &message) {
        if (valid) {
            valid = false;
            diagnostic = message;
        }
    }

    const std::vector<int32_t> &integers;
    const std::vector<float> &floats;
    size_t cursor = 0;
    bool valid = true;
    std::string diagnostic;
};

// Validates a non-negative bounded packed record count.
bool valid_count(Decoder &decoder, int32_t count) {
    if (count < 0 || static_cast<size_t>(count) > decoder.integers.size()) {
        decoder.fail("PVZ-PACKED-SCENE-COUNT: record count is invalid.");
        return false;
    }
    return true;
}

} // namespace

// Encodes the complete native runtime setup scene using the shared versioned
// layout.
PackedCompiledRuntimeScene encode_compiled_runtime_scene(const CompiledRuntimeScene &scene) {
    PackedCompiledRuntimeScene out;
    auto &i = out.integers;
    auto &f = out.floats;
    i = {scene.contract_version,
         static_cast<int32_t>(scene.fixtures.size()),
         static_cast<int32_t>(scene.source_programs.size()),
         static_cast<int32_t>(scene.properties.size()),
         static_cast<int32_t>(scene.color_targets.size()),
         static_cast<int32_t>(scene.wheel_palettes.size()),
         static_cast<int32_t>(scene.wheel_bindings.size()),
         static_cast<int32_t>(scene.gobo_assets.size()),
         static_cast<int32_t>(scene.gobo_bindings.size()),
         static_cast<int32_t>(scene.gobo_motion_bindings.size()),
         static_cast<int32_t>(scene.diagnostics.size())};
    for (const auto &v : scene.fixtures)
        i.insert(i.end(),
                 {v.fixture_id, v.universe_id, v.start_address, 0, push_float(f, v.luminous_flux), push_float(f, v.beam_angle_default)});
    for (const auto &v : scene.source_programs) {
        i.insert(i.end(), {v.program_id, static_cast<int32_t>(v.semantic), static_cast<int32_t>(v.sources.size()),
                           static_cast<int32_t>(v.dmx_from), static_cast<int32_t>(v.dmx_to), push_float(f, v.physical_from),
                           push_float(f, v.physical_to), static_cast<int32_t>(v.activation.target_kind), v.activation.master_program_id,
                           static_cast<int32_t>(v.activation.from), static_cast<int32_t>(v.activation.to), v.activation.valid ? 1 : 0,
                           v.activation.target_id, v.activation.master_channel_id});
        for (const auto &s : v.sources)
            i.insert(i.end(), {s.universe_id, s.address, s.byte_order});
    }
    for (const auto &v : scene.properties) {
        i.insert(i.end(), {v.property_id, v.fixture_id, v.component_id, v.render_target_id, static_cast<int32_t>(v.semantic),
                           static_cast<int32_t>(v.contributors.size())});
        for (const auto &c : v.contributors)
            i.insert(i.end(), {c.source_program_id, push_float(f, c.weight), static_cast<int32_t>(c.operation)});
    }
    for (const auto &v : scene.color_targets) {
        i.insert(i.end(), {v.color_target_id, v.fixture_id, v.beam_render_target_id, v.geometry_id, v.additive_source ? 1 : 0,
                           static_cast<int32_t>(v.inputs.size())});
        for (const auto &x : v.inputs)
            i.insert(i.end(), {x.source_program_id, static_cast<int32_t>(x.semantic), push_float(f, x.default_value),
                               x.use_normalized_value ? 1 : 0, x.emitter_resource_id, x.filter_resource_id});
    }
    for (const auto &v : scene.wheel_palettes) {
        i.insert(i.end(),
                 {v.wheel_renderer_id, v.fixture_id, push_float(f, v.placement_offset_degrees), static_cast<int32_t>(v.slots.size())});
        for (const auto &s : v.slots)
            i.insert(i.end(), {s.slot_index, push_float(f, s.srgb_red), push_float(f, s.srgb_green), push_float(f, s.srgb_blue),
                               push_float(f, s.linear_red), push_float(f, s.linear_green), push_float(f, s.linear_blue),
                               push_float(f, s.gain), s.identity ? 1 : 0});
    }
    for (const auto &v : scene.wheel_bindings) {
        i.insert(i.end(), {v.binding_id, v.fixture_id, v.beam_render_target_id, v.wheel_renderer_id, v.source_program_id,
                           static_cast<int32_t>(v.mode), v.snap ? 1 : 0, push_float(f, v.placement_offset_degrees),
                           static_cast<int32_t>(v.channel_sets.size())});
        for (const auto &s : v.channel_sets)
            i.insert(i.end(), {static_cast<int32_t>(s.dmx_from), static_cast<int32_t>(s.dmx_to), s.wheel_slot_index});
    }
    for (const auto &v : scene.gobo_assets)
        i.insert(i.end(), {v.gobo_asset_id, v.wheel_id, v.slot_index, v.open_slot ? 1 : 0, v.media_valid ? 1 : 0});
    for (const auto &v : scene.gobo_bindings) {
        i.insert(i.end(), {v.binding_id, v.fixture_id, v.beam_render_target_id, v.wheel_id, v.wheel_instance_index, v.source_program_id,
                           static_cast<int32_t>(v.mode), static_cast<int32_t>(v.channel_sets.size())});
        for (const auto &s : v.channel_sets)
            i.insert(i.end(), {static_cast<int32_t>(s.dmx_from), static_cast<int32_t>(s.dmx_to), s.wheel_slot_index});
    }
    for (const auto &v : scene.gobo_motion_bindings)
        i.insert(i.end(),
                 {v.binding_id, v.fixture_id, v.beam_render_target_id, v.wheel_id, v.wheel_instance_index, v.source_program_id,
                  static_cast<int32_t>(v.semantic_kind), static_cast<int32_t>(v.controlled_scope), push_float(f, v.physical_from),
                  push_float(f, v.physical_to), v.scalar_evaluable ? 1 : 0, v.rendered ? 1 : 0, v.physical_unit == "Angle" ? 1 : 0});
    return out;
}

// Decodes and validates one supported packed runtime setup scene without
// partial installation.
CompiledRuntimeSceneDecodeResult decode_compiled_runtime_scene(const std::vector<int32_t> &integers, const std::vector<float> &floats) {
    CompiledRuntimeSceneDecodeResult result;
    Decoder d(integers, floats);
    if (!d.require(6)) {
        result.diagnostic = d.diagnostic;
        return result;
    }
    const int32_t version = d.read();
    if (version < 1 || version > kCompiledRuntimeSceneContractVersion) {
        result.diagnostic = "PVZ-PACKED-SCENE-VERSION: unsupported compiled runtime scene version.";
        return result;
    }
    result.scene.contract_version = version;
    const int32_t fixture_count = d.read(), program_count = d.read(), property_count = d.read(), color_count = d.read();
    int32_t palette_count = 0, wheel_count = 0, asset_count = 0, gobo_count = 0, motion_count = 0;
    if (version >= 2) {
        if (!d.require(2))
            goto done;
        palette_count = d.read();
        wheel_count = d.read();
    }
    if (version >= 4) {
        if (!d.require(2))
            goto done;
        asset_count = d.read();
        gobo_count = d.read();
    }
    if (version >= 7) {
        if (!d.require(1))
            goto done;
        motion_count = d.read();
    }
    if (!d.require(1))
        goto done;
    d.read();
    for (int32_t count :
         {fixture_count, program_count, property_count, color_count, palette_count, wheel_count, asset_count, gobo_count, motion_count})
        if (!valid_count(d, count))
            goto done;
    for (int n = 0; n < fixture_count && d.require(kPackedSceneFixtureIntegers); ++n) {
        CompiledFixtureInstance v;
        v.fixture_id = d.read();
        v.universe_id = d.read();
        v.start_address = d.read();
        d.read();
        v.luminous_flux = read_float(floats, d.read(), v.luminous_flux);
        v.beam_angle_default = read_float(floats, d.read(), v.beam_angle_default);
        result.scene.fixtures.push_back(v);
    }
    for (int n = 0; n < program_count && d.require(version >= 7 ? kPackedSceneV7SourceFixedIntegers : kPackedSceneV6SourceFixedIntegers);
         ++n) {
        CompiledDmxSourceProgram v;
        v.program_id = d.read();
        v.semantic = static_cast<CompiledSemantic>(d.read());
        int32_t sources = d.read();
        v.dmx_from = static_cast<uint32_t>(d.read());
        v.dmx_to = static_cast<uint32_t>(d.read());
        int32_t pf = d.read(), pt = d.read();
        if (version >= 7) {
            v.activation.target_kind = static_cast<gdtf_runtime::ModeMasterTargetKind>(d.read());
            v.activation.master_program_id = d.read();
            v.activation.from = static_cast<uint32_t>(d.read());
            v.activation.to = static_cast<uint32_t>(d.read());
            v.activation.valid = d.read() != 0;
            v.activation.target_id = d.read();
            v.activation.master_channel_id = d.read();
        } else
            d.read();
        v.physical_from = read_float(floats, pf, 0);
        v.physical_to = read_float(floats, pt, 1);
        if (!valid_count(d, sources) || !d.require(static_cast<size_t>(sources) * 3))
            goto done;
        for (int x = 0; x < sources; ++x)
            v.sources.push_back({d.read(), d.read(), d.read()});
        result.scene.source_programs.push_back(v);
    }
    for (int n = 0; n < property_count && d.require(6); ++n) {
        CompiledComponentProperty v;
        v.property_id = d.read();
        v.fixture_id = d.read();
        v.component_id = d.read();
        v.render_target_id = d.read();
        v.semantic = static_cast<CompiledSemantic>(d.read());
        int32_t count = d.read();
        if (!valid_count(d, count) || !d.require(static_cast<size_t>(count) * 3))
            goto done;
        for (int x = 0; x < count; ++x) {
            CompiledPropertyContributor c;
            c.source_program_id = d.read();
            c.weight = read_float(floats, d.read(), 1);
            c.operation = static_cast<CompiledContributorOperation>(d.read());
            v.contributors.push_back(c);
        }
        result.scene.properties.push_back(v);
    }
    for (int n = 0; n < color_count && d.require(6); ++n) {
        CompiledColorTargetProgram v;
        v.color_target_id = d.read();
        v.fixture_id = d.read();
        v.beam_render_target_id = d.read();
        v.geometry_id = d.read();
        v.additive_source = d.read() != 0;
        int32_t count = d.read(), stride = version >= 3 ? 6 : 4;
        if (!valid_count(d, count) || !d.require(static_cast<size_t>(count) * stride))
            goto done;
        for (int x = 0; x < count; ++x) {
            CompiledColorInputBinding a;
            a.source_program_id = d.read();
            a.semantic = static_cast<CompiledSemantic>(d.read());
            a.default_value = read_float(floats, d.read(), 0);
            a.use_normalized_value = d.read() != 0;
            if (version >= 3) {
                a.emitter_resource_id = d.read();
                a.filter_resource_id = d.read();
            }
            v.inputs.push_back(a);
        }
        result.scene.color_targets.push_back(v);
    }
    for (int n = 0; n < palette_count && d.require(4); ++n) {
        CompiledWheelPalette v;
        v.wheel_renderer_id = d.read();
        v.fixture_id = d.read();
        v.placement_offset_degrees = static_cast<float>(read_float(floats, d.read(), 270));
        int32_t count = d.read();
        if (!valid_count(d, count) || !d.require(static_cast<size_t>(count) * 9))
            goto done;
        for (int x = 0; x < count; ++x) {
            CompiledWheelPaletteSlot s;
            s.slot_index = d.read();
            s.srgb_red = read_float(floats, d.read(), 1);
            s.srgb_green = read_float(floats, d.read(), 1);
            s.srgb_blue = read_float(floats, d.read(), 1);
            s.linear_red = read_float(floats, d.read(), 1);
            s.linear_green = read_float(floats, d.read(), 1);
            s.linear_blue = read_float(floats, d.read(), 1);
            s.gain = read_float(floats, d.read(), 1);
            s.identity = d.read() != 0;
            v.slots.push_back(s);
        }
        result.scene.wheel_palettes.push_back(v);
    }
    for (int n = 0; n < wheel_count && d.require(9); ++n) {
        CompiledWheelTargetBinding v;
        v.binding_id = d.read();
        v.fixture_id = d.read();
        v.beam_render_target_id = d.read();
        v.wheel_renderer_id = d.read();
        v.source_program_id = d.read();
        v.mode = static_cast<CompiledWheelMode>(d.read());
        v.snap = d.read() != 0;
        v.placement_offset_degrees = read_float(floats, d.read(), 270);
        int32_t count = d.read();
        if (!valid_count(d, count) || !d.require(static_cast<size_t>(count) * 3))
            goto done;
        for (int x = 0; x < count; ++x)
            v.channel_sets.push_back({static_cast<uint32_t>(d.read()), static_cast<uint32_t>(d.read()), d.read()});
        result.scene.wheel_bindings.push_back(v);
    }
    for (int n = 0; n < asset_count && d.require(5); ++n) {
        CompiledGoboAsset v;
        v.gobo_asset_id = d.read();
        v.wheel_id = d.read();
        v.slot_index = d.read();
        v.open_slot = d.read() != 0;
        v.media_valid = d.read() != 0;
        result.scene.gobo_assets.push_back(v);
    }
    for (int n = 0; n < gobo_count && d.require(8); ++n) {
        CompiledGoboSelectionBinding v;
        v.binding_id = d.read();
        v.fixture_id = d.read();
        v.beam_render_target_id = d.read();
        v.wheel_id = d.read();
        v.wheel_instance_index = d.read();
        v.source_program_id = d.read();
        v.mode = static_cast<CompiledGoboSelectionMode>(d.read());
        int32_t count = d.read();
        if (!valid_count(d, count) || !d.require(static_cast<size_t>(count) * 3))
            goto done;
        for (int x = 0; x < count; ++x)
            v.channel_sets.push_back({static_cast<uint32_t>(d.read()), static_cast<uint32_t>(d.read()), d.read()});
        result.scene.gobo_bindings.push_back(v);
    }
    for (int n = 0; n < motion_count && d.require(kPackedSceneGoboMotionIntegers); ++n) {
        CompiledGoboMotionBinding v;
        v.binding_id = d.read();
        v.fixture_id = d.read();
        v.beam_render_target_id = d.read();
        v.wheel_id = d.read();
        v.wheel_instance_index = d.read();
        v.source_program_id = d.read();
        v.semantic_kind = static_cast<gdtf_runtime::GoboSemanticKind>(d.read());
        v.controlled_scope = static_cast<gdtf_runtime::GoboControlledScope>(d.read());
        v.physical_from = read_float(floats, d.read(), 0);
        v.physical_to = read_float(floats, d.read(), 1);
        v.scalar_evaluable = d.read() != 0;
        v.rendered = d.read() != 0;
        v.physical_unit = d.read() == 1 ? "Angle" : "None";
        result.scene.gobo_motion_bindings.push_back(v);
    }
    if (d.valid && d.cursor != integers.size())
        d.fail("PVZ-PACKED-SCENE-TRAILING: decoder cursor did not land at the "
               "payload boundary.");
done:
    result.consumed_integers = d.cursor;
    result.valid = d.valid;
    result.diagnostic = d.diagnostic;
    return result;
}

} // namespace peraviz::runtime
