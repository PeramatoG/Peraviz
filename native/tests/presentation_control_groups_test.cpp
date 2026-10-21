#include "presentation/control_groups.h"
#include "presentation/dense_presentation_state.h"
#include <cstdlib>
#include <iostream>
#include <set>

using namespace peraviz::runtime;
using namespace peraviz::presentation;
// Fails independently of build assertion configuration.
static void check(bool ok, const char *message) {
    if (!ok) { std::cerr << message << '\n'; std::exit(1); }
}
// Builds canonical physical beams with inherited controls and an independent emission-only Aura.
static CompiledRuntimeScene fixture() {
    CompiledRuntimeScene scene;
    CompiledDmxSourceProgram source;
    source.program_id = 10;
    source.parser_program_id = 2;
    source.semantic = CompiledSemantic::ColorAddRed;
    source.sources.push_back({0, 1, 0});
    scene.source_programs.push_back(source);
    CompiledComponentProperty dimmer;
    dimmer.property_id = 20;
    dimmer.fixture_id = 1;
    dimmer.render_target_id = 21;
    dimmer.semantic = CompiledSemantic::Dimmer;
    dimmer.geometry_name = "Root";
    dimmer.contributors.push_back({10, 1.0});
    scene.properties.push_back(dimmer);
    for (int i = 0; i < 51; ++i) {
        CompiledBeamOpticalProfile beam;
        beam.fixture_id = 1;
        beam.render_target_id = 100 + i;
        beam.geometry_path = "Root/Output" + std::to_string(i);
        if (i == 50) { beam.beam_type = "None"; beam.has_projected_beam = false; beam.projected_lumen_scale = 0; }
        scene.beam_profiles.push_back(beam);
        CompiledColorTargetProgram color;
        color.fixture_id = 1;
        color.color_target_id = 1000 + i;
        color.beam_render_target_id = beam.render_target_id;
        color.inputs.push_back({10, source.semantic});
        scene.color_targets.push_back(color);
    }
    return scene;
}
// Covers conservative selected-mode authority, inverse identities, held state and native coalescing.
int main() {
    const auto scene = fixture();
    auto groups = compile_control_groups(scene);
    check(groups.size() == 2 && groups[0].physical_ids.size() == 50 && groups[1].physical_ids.size() == 1,
        "50 compatible projected beams share one group; Aura remains individual");
    std::set<int32_t> ids;
    for (const auto &g : groups) ids.insert(g.physical_ids.begin(), g.physical_ids.end());
    check(ids.size() == 51 && *ids.begin() == 100 && *ids.rbegin() == 150, "Every canonical ID has exact inverse membership");
    auto changed = scene;
    changed.properties[0].geometry_name = "Root/Output0";
    auto other_dimmer = scene.properties[0];
    other_dimmer.property_id = 30;
    other_dimmer.geometry_name = "Root/Output1";
    changed.properties.push_back(other_dimmer);
    check(compile_control_groups(changed).size() == 51, "Different or uncertain Dimmer authorities stay independent");
    changed = scene;
    auto source = changed.source_programs[0];
    source.program_id = 11;
    source.sources[0].address = 2;
    changed.source_programs.push_back(source);
    changed.color_targets[0].inputs[0].source_program_id = 11;
    check(compile_control_groups(changed).size() == 3, "Different Color source bytes/program ownership split groups");
    changed.source_programs[1].sources = changed.source_programs[0].sources;
    changed.source_programs[1].activation.target_kind = peraviz::gdtf_runtime::ModeMasterTargetKind::ChannelFunction;
    changed.source_programs[1].activation.master_program_id = 99;
    changed.source_programs[1].activation.from = 128;
    check(compile_control_groups(changed).size() == 3, "Different Color ModeMaster authority stays independent even with equal bytes");
    changed = scene;
    changed.beam_profiles[0].projected_lumen_scale = 0.5;
    check(compile_control_groups(changed).size() == 3, "Different projected scales split groups");
    changed = scene;
    changed.beam_profiles[0].emission_lumen_scale = 0.5;
    check(compile_control_groups(changed).size() == 3, "Different emission scales split groups");
    changed = scene;
    changed.beam_profiles[0].beam_radius_m = 0.1;
    check(compile_control_groups(changed).size() == 3, "Different optical requirements split groups");
    changed = scene;
    CompiledGoboSelectionBinding gobo;
    gobo.fixture_id = 1;
    changed.gobo_bindings.push_back(gobo);
    check(compile_control_groups(changed).size() == 51, "Projector/gobo materials use individual fallback");
    changed = scene;
    CompiledWheelTargetBinding wheel;
    wheel.fixture_id = 1;
    changed.wheel_bindings.push_back(wheel);
    check(compile_control_groups(changed).size() == 51, "Wheel/filter ownership uses individual fallback");
    changed = scene;
    for (int i = 0; i < 50; ++i) {
        auto pixel = source;
        pixel.program_id = 100 + i;
        pixel.sources[0].address = 2 + i;
        changed.source_programs.push_back(pixel);
        changed.color_targets[i].inputs[0].source_program_id = pixel.program_id;
    }
    check(compile_control_groups(changed).size() == 51, "Independently addressed pixels never group by current values");
    DensePresentationState state;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> routes;
    std::vector<int32_t> mapping(51, 0);
    mapping[50] = -1;
    for (int i = 0; i < 51; ++i) {
        outputs.push_back({100 + i, i == 50 ? 0.0f : 1.0f});
        routes.push_back({2, 21, uint32_t(i)});
        routes.push_back({3, 1000 + i, uint32_t(i)});
    }
    check(state.install(outputs, routes) && state.install_groups(mapping), "Group projection installs without merging physical state");
    const auto gen = state.generation();
    const float dark[] = {0, 0, 0, 0, 0};
    const float color[] = {0.2f, 0.4f, 0.8f, 0.25f};
    const float bright[] = {0.5f, 20, 10, 30, 2};
    state.update_target(gen, 2, 21, 2, dark);
    for (int i = 0; i < 51; ++i) state.update_target(gen, 3, 1000+i, 4, color);
    state.prepare_snapshot();
    check(state.bindings().size() == 51 && state.prepared_groups().size() == 1, "Native dirty projection emits exactly one shared dynamic row");
    state.finish_snapshot(gen);
    for (int i = 0; i < 51; ++i) state.update_target(gen, 3, 1000+i, 4, color);
    state.update_target(gen, 2, 21, 2, bright);
    state.prepare_snapshot();
    check(state.prepared().size() == 1 && state.prepared_groups().size() == 1, "Only Aura retains a physical dynamic row");
    const auto held = state.prepared_groups()[0].values;
    check(held[Red] == color[0] && held[ColorGain] == 0.25f && held[BeamEnergy] == 5 && held[MaterialEnergy] == 0.5f,
        "Dark-to-visible restores latest RGB, gain and material energy without a new Color packet");
    for (int i = 0; i < 50; ++i) check(state.render_values(i) == held, "All native physical states remain exact and addressable");
    state.finish_snapshot(gen);
    state.clear();
    check(state.prepared_groups().empty() && !state.update(gen, 0, 2, 2, bright), "Scene reload retires old group state and generation");
    check(state.install({{999, 1}}, {}) && state.prepared_groups().empty(), "Replacement scene has no old group state");
    std::cout << "Control groups: physical topology, conservative splits, held state and native projection passed\n";
}
