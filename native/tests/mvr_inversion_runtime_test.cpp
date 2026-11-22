#include "runtime/compiled_runtime_scene_codec.h"
#include "runtime/peraviz_visual_runtime.h"
#include <array>
#include <cmath>
#include <iostream>
#include <map>
#include <thread>
#include <tuple>
namespace {
using namespace peraviz::runtime;
// Exercise the existing worker interface with disjoint native slots and deterministic joining.
class Executor : public NativeBatchExecutor {
  public:
    bool parallel = false;
    // Force the existing native evaluation policy only in this deterministic test.
    bool forced() const override { return parallel; }
    // Select serial or parallel execution without wall-clock thresholds.
    bool worthwhile(size_t, size_t) const override { return parallel; }
    // Execute exactly disjoint source ranges and join before coordinator consumption.
    NativeBatchMetrics run(size_t count, size_t, Function function, void *context, bool) override {
        NativeBatchMetrics metrics;
        if (parallel && count > 1) {
            std::thread worker([&] { function(context, 0, count / 2); });
            function(context, count / 2, count);
            worker.join();
            metrics.parallel = true;
            metrics.tasks = 2;
            metrics.workers_used = 2;
        } else {
            function(context, 0, count);
            metrics.tasks = 1;
            metrics.workers_used = 1;
        }
        return metrics;
    }
};
// Keep numerical failures attributed to consumer-local inversion rather than the parser.
bool check(bool ok, const char *message) {
    if (!ok)
        std::cerr << "MVR inversion: " << message << '\n';
    return ok;
}
// Read the existing qualified mechanical section, including multiple axes within a fixture.
std::map<int, float> axes(const SectionedVisualFrame &frame) {
    std::map<int, float> out;
    for (size_t d = 0; d < frame.descriptors.size(); d += 5)
        if (frame.descriptors[d] == int(VisualSectionType::GeometryTransform)) {
            for (int r = 0; r < frame.descriptors[d + 1]; ++r) {
                auto i = frame.descriptors[d + 2] + r * 4, f = frame.descriptors[d + 3] + r * 2;
                if (frame.integers[i + 1])
                    out[frame.integers[i + 1]] = frame.floats[f];
                if (frame.integers[i + 2])
                    out[frame.integers[i + 2]] = frame.floats[f + 1];
            }
        }
    return out;
}
// Assemble ordered noncontiguous bytes crossing two universes without changing their ownership.
std::array<std::array<uint8_t, 512>, 2> input(int count, uint32_t raw) {
    std::array<std::array<uint8_t, 512>, 2> frames{};
    for (int i = 0; i < count; ++i)
        frames[i % 2][10 + i * 3] = uint8_t(raw >> (8 * (count - 1 - i)));
    frames[0][100] = 64;
    frames[0][200] = 200;
    return frames;
}
// Submit native packets exactly as reception would, independently of source caching and worker policy.
SectionedVisualFrame send(PeravizVisualRuntimeCore &core,
                          const std::array<std::array<uint8_t, 512>, 2> &frames) {
    for (int u = 0; u < 2; ++u)
        core.submit_universe_frame(u, frames[u].data(), 512);
    return core.consume_latest_visual_frame();
}
// Build a fixture-local mechanical consumer sharing its raw source with another fixture and unrelated
// outputs.
CompiledRuntimeScene scene(int count, bool descending) {
    CompiledRuntimeScene result;
    result.fixtures.push_back({1, "fixture-one", "type", "mode", 0, 1});
    result.fixtures.push_back({2, "fixture-two", "type", "mode", 0, 1});
    result.fixtures[0].invert_pan = true;
    const uint32_t maximum = uint32_t((uint64_t(1) << (count * 8)) - 1);
    CompiledDmxSourceProgram pan;
    pan.program_id = 1;
    pan.semantic = CompiledSemantic::Pan;
    pan.dmx_to = maximum;
    pan.physical_from = descending ? 270 : -270;
    pan.physical_to = descending ? -270 : 270;
    for (int i = 0; i < count; ++i)
        pan.sources.push_back({i % 2, 10 + i * 3, i});
    auto tilt = pan;
    tilt.program_id = 2;
    tilt.semantic = CompiledSemantic::Tilt;
    tilt.sources = {{0, 100, 0}};
    tilt.dmx_to = 255;
    tilt.physical_from = -90;
    tilt.physical_to = 90;
    result.source_programs = {pan, tilt};
    for (auto [fixture, component, semantic, source] :
         {std::tuple{1, 101, CompiledSemantic::Pan, 1}, std::tuple{1, 102, CompiledSemantic::Tilt, 2},
          std::tuple{2, 201, CompiledSemantic::Pan, 1}, std::tuple{1, 301, CompiledSemantic::Zoom, 1},
          std::tuple{1, 401, CompiledSemantic::Dimmer, 1}}) {
        CompiledComponentProperty property;
        property.property_id = component + 1000;
        property.fixture_id = fixture;
        property.component_id = component;
        property.render_target_id = component;
        property.semantic = semantic;
        property.contributors.push_back({source, 1});
        result.properties.push_back(property);
    }
    CompiledColorTargetProgram color;
    color.color_target_id = 501;
    color.fixture_id = 1;
    color.beam_render_target_id = 501;
    color.inputs.push_back({1, CompiledSemantic::ColorAddRed, 0.0, true});
    result.color_targets.push_back(color);
    return result;
}
// Repatch ordered full-width sources without changing overlapping consumers or presentation identity.
bool patch_routes() {
    for (int count = 1; count <= 4; ++count)
        for (bool parallel : {false, true}) {
            auto compiled = scene(count, false);
            compiled.properties.clear();
            compiled.color_targets.clear();
            compiled.source_programs.resize(1);
            auto second = compiled.source_programs[0];
            second.program_id = 2;
            compiled.source_programs.push_back(second);
            for (int fixture = 1; fixture <= 2; ++fixture) {
                CompiledComponentProperty p;
                p.property_id = fixture;
                p.fixture_id = fixture;
                p.component_id = fixture * 100 + 1;
                p.semantic = CompiledSemantic::Pan;
                p.contributors.push_back({fixture, 1});
                compiled.properties.push_back(p);
            }
            PeravizVisualRuntimeCore core;
            core.install_compiled_scene(compiled);
            Executor executor;
            executor.parallel = parallel;
            core.set_native_executor(&executor);
            const uint32_t maximum = uint32_t((uint64_t(1) << (count * 8)) - 1), old_raw = maximum / 4,
                           new_raw = maximum - maximum / 4;
            auto frames = input(count, old_raw);
            for (int i = 0; i < count; ++i)
                frames[i % 2][110 + i * 3] = uint8_t(new_raw >> (8 * (count - 1 - i)));
            send(core, frames);
            const auto generation = core.schema().schema_generation;
            auto changed = compiled;
            for (auto &source : changed.source_programs[0].sources)
                source.address += 100;
            if (!check(core.replace_routes(changed), "Full-width same-topology repatch commits"))
                return false;
            core.set_native_executor(&executor);
            auto values = axes(core.consume_latest_visual_frame());
            const float expected = float(270.0 - 540.0 * double(new_raw) / maximum);
            if (!check(values.count(101) && std::abs(values[101] - expected) < 0.002 &&
                           core.schema().schema_generation == generation,
                       "Repatch replays held coarse/fine bytes with inversion and stable generation"))
                return false;
            frames = input(count, maximum);
            for (int i = 0; i < count; ++i)
                frames[i % 2][110 + i * 3] = uint8_t(new_raw >> (8 * (count - 1 - i)));
            values = axes(send(core, frames));
            if (!check(!values.count(101) && values.count(201) && std::abs(values[201] - 270) < 0.002,
                       "Only unchanged overlapping fixture consumes old-address changes"))
                return false;
            auto invalid = changed;
            invalid.source_programs.pop_back();
            if (!check(!core.replace_routes(invalid), "Topology-changing repatch rejects atomically"))
                return false;
        }
    return true;
}
// Keep wheel state and its borrowed ordered-layer cache coherent across routing-plan replacement.
bool patch_wheel() {
    auto compiled = scene(1, false);
    CompiledWheelPalette palette;
    palette.fixture_id = 1;
    palette.wheel_renderer_id = 901;
    CompiledWheelPaletteSlot open;
    open.slot_index = 1;
    auto red = open;
    red.slot_index = 2;
    red.identity = false;
    red.linear_green = red.linear_blue = 0;
    red.srgb_green = red.srgb_blue = 0;
    palette.slots = {open, red};
    compiled.wheel_palettes.push_back(palette);
    CompiledWheelTargetBinding binding;
    binding.binding_id = 902;
    binding.fixture_id = 1;
    binding.beam_render_target_id = 501;
    binding.wheel_renderer_id = 901;
    binding.source_program_id = 1;
    binding.channel_sets = {{0, 127, 1}, {128, 255, 2}};
    compiled.wheel_bindings.push_back(binding);
    PeravizVisualRuntimeCore core;
    core.install_compiled_scene(compiled);
    auto frames = input(1, 200);
    frames[0][110] = 200;
    send(core, frames);
    const auto before = core.held_domain_replay();
    compiled.source_programs[0].sources[0].address = 110;
    if (!core.replace_routes(compiled))
        return false;
    core.consume_latest_visual_frame();
    const auto after = core.held_domain_replay();
    if (!check(before.descriptors == after.descriptors && before.integers == after.integers &&
                   before.floats == after.floats,
               "Wheel selection and ordered layer cache survive held routing replacement"))
        return false;
    frames[0][110] = 0;
    send(core, frames);
    const auto changed = core.held_domain_replay();
    return check(changed.integers != after.integers, "Repatched wheel remains responsive to its new source");
}
} // namespace
// Verify every supported bit depth, byte routing, held replay, target identity and serial/parallel cache
// ownership.
bool test_mvr_inversion_runtime() {
    if (!patch_routes() || !patch_wheel())
        return false;
    auto legacy = scene(1, false);
    legacy.contract_version = 11;
    const auto old_payload = encode_compiled_runtime_scene(legacy);
    const auto old_decoded = decode_compiled_runtime_scene(old_payload.integers, old_payload.floats);
    if (!check(old_decoded.valid && !old_decoded.scene.fixtures[0].invert_pan &&
                   !old_decoded.scene.fixtures[0].invert_tilt,
               "Version 11 remains compatible and has no implicit inversion mask"))
        return false;

    for (bool parallel : {false, true})
        for (bool descending : {false, true})
            for (int count : {1, 2, 3, 4}) {
                const uint32_t maximum = uint32_t((uint64_t(1) << (count * 8)) - 1);
                for (uint32_t raw : {uint32_t(0), maximum / 2, maximum}) {
                    auto compiled = scene(count, descending);
                    auto encoded = encode_compiled_runtime_scene(compiled);
                    auto decoded = decode_compiled_runtime_scene(encoded.integers, encoded.floats);
                    if (!check(decoded.valid && decoded.scene.fixtures[0].invert_pan &&
                                   !decoded.scene.fixtures[0].invert_tilt,
                               "Packed fixture flags round-trip"))
                        return false;
                    Executor executor;
                    executor.parallel = parallel;
                    PeravizVisualRuntimeCore core;
                    core.set_native_executor(&executor);
                    core.install_compiled_scene(decoded.scene);
                    auto frame = send(core, input(count, raw));
                    auto values = axes(frame);
                    const auto &p = compiled.source_programs[0];
                    const float ordinary =
                        float(p.physical_from + (p.physical_to - p.physical_from) * double(raw) / maximum);
                    const float inverted = float(p.physical_from + (p.physical_to - p.physical_from) *
                                                                       double(maximum - raw) / maximum);
                    if (!check(values.count(101) && values.count(201) &&
                                   std::abs(values[101] - inverted) < 0.001f &&
                                   std::abs(values[201] - ordinary) < 0.001f,
                               "Only owning fixture Pan is inverted at full assembled width"))
                        return false;
                    if (!check(std::abs(values[102] - (-90 + 180 * 64.0f / 255)) < 0.001f,
                               "Pan inversion leaves Tilt unchanged"))
                        return false;
                    if (!check(core.set_fixture_inversions({1, 0, 1}), "Atomic inversion update accepted"))
                        return false;
                    const auto changed_frame = core.consume_latest_visual_frame();
                    for (size_t d = 0; d < changed_frame.descriptors.size(); d += 5)
                        if (!check(changed_frame.descriptors[d] == int(VisualSectionType::GeometryTransform),
                                   "Inversion never changes shared-source Color, Dimmer or Zoom outputs"))
                            return false;
                    values = axes(changed_frame);
                    if (!check(values.count(101) && std::abs(values[101] - ordinary) < 0.001f &&
                                   std::abs(values[102] - (-90 + 180 * 191.0f / 255)) < 0.001f,
                               "Held replay needs no external packet and inverts Tilt independently"))
                        return false;
                    auto nochange = core.consume_latest_visual_frame();
                    if (!check(nochange.descriptors.empty(), "Settled inversion creates no per-frame work"))
                        return false;
                }
            }
    auto compiled = scene(1, false);
    auto master = compiled.source_programs[1];
    master.program_id = 4;
    master.sources = {{0, 200, 0}};
    compiled.source_programs.push_back(master);
    compiled.source_programs[0].dmx_to = 127;
    compiled.source_programs[0].physical_from = 0;
    compiled.source_programs[0].physical_to = 90;
    compiled.source_programs[0].activation.target_kind =
        peraviz::gdtf_runtime::ModeMasterTargetKind::DmxChannel;
    compiled.source_programs[0].activation.master_program_id = 4;
    compiled.source_programs[0].activation.from = 128;
    compiled.source_programs[0].activation.to = 255;
    auto upper = compiled.source_programs[0];
    upper.program_id = 3;
    upper.dmx_from = 128;
    upper.dmx_to = 255;
    upper.physical_from = 90;
    upper.physical_to = 180;
    compiled.source_programs.push_back(upper);
    for (auto &p : compiled.properties)
        if (p.semantic == CompiledSemantic::Pan)
            p.contributors.push_back({3, 1});
    auto extra = compiled.properties[0];
    extra.property_id = 909;
    extra.component_id = 111;
    compiled.properties.push_back(extra);
    PeravizVisualRuntimeCore core;
    core.install_compiled_scene(compiled);
    auto frames = input(1, 0);
    auto values = axes(send(core, frames));
    if (values[101] != 180 || values[111] != 180 || values[201] != 0)
        for (const auto &[id, value] : values)
            std::cerr << id << "=" << value << " ";
    if (!check(values[101] == 180 && values[111] == 180 && values[201] == 0,
               "Range arbitration and every referenced Pan axis use consumer-local inversion"))
        return false;
    frames[0][200] = 0;
    auto blocked = axes(send(core, frames));
    if (!check(!blocked.count(101) && !blocked.count(111), "Inactive ModeMaster cannot publish inverted Pan"))
        return false;
    frames[0][200] = 200;
    frames[0][10] = 255;
    values = axes(send(core, frames));
    return check(values[101] == 0 && values[111] == 0 && values[201] == 180,
                 "Master reactivation uses unchanged master bytes and current held fixture values");
}
