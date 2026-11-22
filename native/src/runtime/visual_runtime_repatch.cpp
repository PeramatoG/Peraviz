#include "runtime/peraviz_visual_runtime.h"
namespace peraviz::runtime {
// Replace only routing plans at an exclusive boundary after semantic/topology validation by the loader.
bool PeravizVisualRuntimeCore::replace_routes(const CompiledRuntimeScene &scene) {
    if (scene.fixtures.size() != render_params_by_fixture_.size() ||
        scene.source_programs.size() != source_programs_by_id_.size())
        return false;
    for (const auto &fixture : scene.fixtures)
        if (!render_params_by_fixture_.count(fixture.fixture_id))
            return false;
    for (const auto &program : scene.source_programs)
        if (!source_programs_by_id_.count(program.program_id))
            return false;
    auto held = held_universes();
    const auto schema = schema_;
    const auto epoch = runtime_epoch_;
    const auto clock = test_runtime_now_seconds_;
    auto transforms = std::move(transform_state_by_fixture_);
    auto properties = std::move(property_state_by_property_);
    auto base_colors = std::move(base_color_state_by_target_);
    auto colors = std::move(color_state_by_target_);
    auto wheels = std::move(wheel_state_by_physical_key_);
    // The cached layers borrow wheel map nodes; move them together so those references stay valid.
    auto layers = std::move(ordered_wheel_layers_);
    auto selections = std::move(gobo_selection_state_by_layer_);
    auto rotations = std::move(gobo_rotation_state_by_layer_);
    auto shutters = std::move(shutter_states_);
    auto authorities = std::move(shutter_authorities_);
    install_compiled_scene(scene);
    schema_ = schema;
    runtime_epoch_ = epoch;
    test_runtime_now_seconds_ = clock;
    transform_state_by_fixture_ = std::move(transforms);
    property_state_by_property_ = std::move(properties);
    base_color_state_by_target_ = std::move(base_colors);
    color_state_by_target_ = std::move(colors);
    wheel_state_by_physical_key_ = std::move(wheels);
    ordered_wheel_layers_ = std::move(layers);
    gobo_selection_state_by_layer_ = std::move(selections);
    gobo_rotation_state_by_layer_ = std::move(rotations);
    shutter_states_ = std::move(shutters);
    shutter_authorities_ = std::move(authorities);
    // New plans evaluate retained full frames once; unsupported/unreceived universes stay held visually.
    for (const auto &frame : held)
        submit_universe_frame(frame.id, frame.values.data(), int(frame.values.size()));
    return true;
}
} // namespace peraviz::runtime
