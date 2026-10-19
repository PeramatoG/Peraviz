#include "presentation/dense_presentation_state.h"
#include "runtime/visual_runtime_types.h"
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>

static size_t allocations = 0;
// Counts allocations to assert the warmed native snapshot path has no heap churn.
void *operator new(std::size_t size) { ++allocations; if (void *p = std::malloc(size ? size : 1)) return p; throw std::bad_alloc(); }
// Releases memory allocated by the deterministic test allocation probe.
void operator delete(void *p) noexcept { std::free(p); }
// Supports sized deallocation emitted by C++17 compilers.
void operator delete(void *p, std::size_t) noexcept { std::free(p); }

using namespace peraviz::presentation;
using namespace peraviz::runtime;
// Fails in both Debug and Release builds, independently of NDEBUG.
static void check(bool condition, const char *message) {
    if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}
// Compares expected canonical presentation scalars with float tolerance.
static bool near(float a, float b) { return std::abs(a-b) < 0.0001f; }
// Exercises generation identity, bounded independent updates, reset and canonical gain parity.
int main() {
    constexpr uint32_t count = 1095;
    std::vector<OutputBinding> outputs;
    std::vector<TargetBinding> targets;
    for (uint32_t i = 0; i < count; ++i) {
        outputs.push_back({int32_t(5000+i), 0.5f});
        targets.push_back({2, int32_t(9000+i), i});
        targets.push_back({3, int32_t(12000+i), i});
    }
    DensePresentationState state;
    check(state.install(outputs, targets), "Valid physical bindings install");
    state.set_trace_enabled(true);
    const auto gen = state.generation();
    for (uint32_t i = 0; i < count; ++i) check(state.bindings()[i].canonical_id == int32_t(5000+i), "Dense canonical identity remains stable");
    const float intensity[] = {0.5f, 10.0f, 20.0f, 30.0f, 2.0f};
    const float color[] = {0.2f, 0.4f, 0.8f, 0.25f};
    for (int repeat = 0; repeat < 12; ++repeat) {
        check(state.update(gen, 42, 2, VisualChangeDimmer, intensity), "Direct index update succeeds");
        check(state.update(gen, 42, 3, VisualChangeColor | VisualChangeMaterial, color), "Color coalesces");
    }
    check(state.dirty_indices().size() == 1 && state.dirty_indices()[0] == 42, "Repeated output appears once");
    const auto ready = state.render_values(42);
    check(near(ready[Dimmer], 0.5f) && near(ready[Red], 0.2f), "Latest values win");
    check(near(ready[BeamEnergy], 1.25f) && near(ready[SpotEnergy], 2.5f) && near(ready[MaterialEnergy], 0.5f), "Physical gain/scaling parity");
    check(near(ready[BeamIntensity], 15.0f * (0.25f + 0.75f * std::pow(0.25f, 1.0f/2.2f))), "Perceptual beam gain parity");
    const auto mask = state.effective_mask(42, ready);
    check((mask & (VisualChangeDimmer | VisualChangeColor | VisualChangeMaterial)) == (VisualChangeDimmer | VisualChangeColor | VisualChangeMaterial), "Masks combine");
    state.finish_snapshot(gen);
    check(state.dirty_indices().empty(), "Snapshot reset clears membership");
    state.update(gen, 42, 2, VisualChangeDimmer, intensity);
    check(state.effective_mask(42, state.render_values(42)) == 0, "Repeated held values skip mutation");
    state.update(gen, 42, 3, VisualChangeColor, color);
    const float newer[] = {0.9f, 0.8f, 0.7f, 0.5f};
    state.update(gen, 42, 3, VisualChangeColor, newer);
    check(near(state.render_values(42)[Red], 0.9f), "Last color wins in one snapshot");
    check(state.effective_mask(42, state.render_values(42)) & VisualChangeColor, "Later changed color retained");
    state.finish_snapshot(gen);
    const float changed_intensity[] = {0.7f, 20, 15, 20, 2.2f};
    state.update(gen, 42, 2, VisualChangeDimmer, changed_intensity);
    state.update(gen, 42, 3, VisualChangeColor, color);
    check(state.dirty_indices().size() == 1, "Already committed output still deduplicates");
    const auto combined = state.effective_mask(42, state.render_values(42));
    check((combined & (VisualChangeDimmer | VisualChangeColor)) == (VisualChangeDimmer | VisualChangeColor), "Changed-domain masks combine after initialization");
    state.finish_snapshot(gen);
    const size_t state_cap = state.state_capacity(), dirty_cap = state.dirty_capacity(), bytes = state.buffer_bytes();
    const size_t before = allocations;
    for (int iteration = 0; iteration < 400; ++iteration) {
        for (uint32_t i = 0; i < count; ++i) {
            const float dim[] = {float(i+1)/count, 3, 5, float(iteration % 40), 4};
            const float rgb[] = {float(i)/count, float(iteration % 11)/11, 1, 1};
            check(state.update_target(gen, 2, int32_t(9000+i), VisualChangeDimmer, dim), "Every independent dimmer resolves");
            check(state.update_target(gen, 3, int32_t(12000+i), VisualChangeColor, rgb), "Every independent color resolves");
        }
        check(state.dirty_indices().size() == count, "No independent output is lost or grouped");
        for (uint32_t i = 0; i < count; ++i) {
            check(state.dirty_indices()[i] == i, "Dense order remains deterministic");
            const auto v = state.render_values(i);
            check(near(v[Dimmer], float(i+1)/count) && near(v[Red], float(i)/count), "Every output remains independent");
            state.effective_mask(i, v);
        }
        state.prepare_snapshot();
        check(state.prepared().size() <= count, "Prepared render buffer remains bounded");
        state.finish_snapshot(gen);
        check(state.state_capacity() == state_cap && state.dirty_capacity() == dirty_cap && state.buffer_bytes() == bytes, "Capacities stay bounded");
    }
    check(allocations == before, "Warmed snapshots allocate no native objects");
    check(state.high_water() == count, "Dirty high-water bounded by physical count");
    const int32_t descriptors[] = {2,1,0,0,0, 3,1,3,5,0};
    const int32_t ints[] = {1,9000,VisualChangeDimmer, 1,12000,VisualChangeColor};
    const float values[] = {1,2,3,4,5, .1f,.2f,.3f,1};
    check(state.compose_sections(gen,descriptors,10,ints,6,values,9), "Batched typed section input applies");
    check(state.dirty_indices().size() == 1, "Batched semantic sections coalesce the same output");
    state.finish_snapshot(gen);
    check(!state.compose_sections(gen,descriptors,10,ints,6,values,8) && state.dirty_indices().empty(), "Malformed batch cannot partially update state");
    std::vector<OutputBinding> replacement{{5000,1}};
    check(state.install(replacement, {{2,9000,0}}), "Scene rebuild replaces bindings");
    check(state.generation() != gen && !state.update(gen,0,2,VisualChangeDimmer,intensity), "Old generation cannot mutate reused index");
    state.update(state.generation(),0,2,VisualChangeDimmer,intensity);
    state.finish_snapshot(gen);
    check(state.dirty_indices().size() == 1 && state.bindings().size() == 1, "Old generation cannot clear new dirty state");
    state.finish_snapshot(state.generation());
    DensePresentationState other;
    check(other.install(replacement, {{2,9000,0}}) && other.generation() != state.generation(), "Separate scene owners cannot reuse generation tokens");
    check(!other.update(state.generation(),0,2,VisualChangeDimmer,intensity), "Generation from another scene owner cannot mutate state");
    check(!state.install({{5000,1},{5000,1}}, {}), "Duplicate canonical identity rejected");
    check(state.bindings().size() == 1, "Invalid setup leaves active generation intact");
    const auto next_gen = state.generation();
    const float closed[] = {1,1,1,0};
    state.update(next_gen,0,2,VisualChangeDimmer,intensity);
    state.update(next_gen,0,3,VisualChangeColor,closed);
    auto off = state.render_values(0);
    check(off[BeamIntensity] == 0 && off[SpotEnergy] == 0 && off[MaterialEnergy] == 0 && off[Visible] == 0, "Closed color gain extinguishes all presentation domains");
    const float bright[] = {1,1,1,2};
    state.update(next_gen,0,3,VisualChangeColor,bright);
    auto high = state.render_values(0);
    check(high[SpotEnergy] == 40 && high[BeamIntensity] == 30, "Physical gain above one does not amplify visual beam gain");
    state.finish_snapshot(next_gen);
    state.invalidate_renderer();
    state.prepare_snapshot();
    check(state.prepared().size() == 1 && (state.prepared()[0].mask & VisualChangeBeamTopology), "Renderer replacement replays held state without semantic reset");
    state.clear();
    check(state.state_capacity() == 0 && state.dirty_capacity() == 0 && !state.update(next_gen,0,2,2,intensity), "Stop/clear retires state and buffers");
    std::cout << "Dense presentation: 1095 independent outputs, 400 snapshots, no warmed allocations\n";
}
