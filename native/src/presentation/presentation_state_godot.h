#pragma once
#include "presentation/direct_presentation_pipeline.h"
#include "runtime/peraviz_visual_runtime_godot.h"
#include "presentation/presentation_material_bindings.h"
#include "presentation/native_beam_bindings.h"
#include "presentation/native_lens_batches.h"
#include "presentation/shutter_playback.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {
class PeravizPresentationState : public RefCounted {
    GDCLASS(PeravizPresentationState, RefCounted)
protected:
    static void _bind_methods();
public:
    ~PeravizPresentationState();
    int64_t install(const PackedInt32Array &ids, const PackedFloat32Array &scales, const PackedInt32Array &routes);
    bool install_groups(const PackedInt32Array &representatives);
    bool install_render_rows(const PackedInt32Array &membership, const PackedInt32Array &classes);
    bool install_materials(const Array &rids, const PackedInt32Array &owners, const PackedFloat32Array &scales, const PackedInt32Array &routes);
    bool install_footprints(int64_t generation, const Array &rids, const Array &instances, const PackedInt32Array &owners, const PackedFloat32Array &scales, const PackedInt32Array &routes);
    void clear_footprints();
    void set_footprint_visible(int32_t index, bool visible);
    void set_footprints_enabled(bool enabled);
    PackedFloat32Array footprint_values(const RID &rid) const;
    int64_t set_materials_enabled(bool enabled);
    PackedFloat32Array physical_values(int32_t index) const;
    PackedFloat32Array material_values(const RID &rid) const;
    bool install_beams(int64_t generation,const PackedInt64Array &objects,const PackedFloat64Array &thresholds);
    void clear_beams();
    bool install_lenses(int64_t generation,const Array &rids,const Array &owners,const Array &buffers,const Array &scales);
    void clear_lenses();
    void set_lens_visible(int32_t batch,int32_t instance,bool visible);
    void flush_lenses();
    int64_t set_lens_emission_gain(double gain);
    PackedFloat32Array lens_buffer(int32_t batch) const;
    void set_beam_policy(bool enabled,double multiplier);
    Dictionary replay_presentation_gains(bool shafts,bool surfaces,double surface_gain,bool trace);
    bool install_shutter_resources(int64_t generation,const PackedInt64Array &beams,const PackedFloat64Array &thresholds,const Array &group_materials,const PackedInt64Array &lights,const PackedInt32Array &owners);
    void set_shutter_policy(bool enabled,double beam_gain,double surface_gain);
    int64_t advance_shutters(int64_t generation,double test_now=-1);
    PackedFloat32Array shutter_values() const;
    // Reads the cached successful beam mutation, not a derived physical/semantic estimate.
    float shutter_beam_energy(int32_t row) const { return shutter_beams_.energy(uint32_t(row)); }
    PackedInt32Array shutter_authority_ids(int32_t index=1) const;
    void clear();
    void invalidate_renderer();
    Dictionary compose(int64_t generation, const PackedInt32Array &descriptors, const PackedInt32Array &integers,
            const PackedFloat32Array &values, bool trace);
    Dictionary consume_runtime(const Ref<PeravizVisualRuntime> &runtime, int64_t generation, int32_t schema_generation, bool trace, bool poll_only=false);
    Dictionary get_sizes() const;
private:
    void apply_beams(const std::vector<peraviz::presentation::PreparedRenderRow> &rows,bool trace,Dictionary &result);
    // Main-thread displayed render rows, independent of an in-flight physical snapshot.
    std::vector<peraviz::presentation::PreparedRenderRow> held_renderer_, gain_rows_;
    std::vector<bool> held_renderer_valid_;
    NativeBeamBindings beams_, shutter_beams_;
    peraviz::presentation::ShutterPlayback shutters_;
    std::vector<std::vector<uint64_t>> shutter_lights_;
    std::vector<peraviz::presentation::PreparedRenderRow> shutter_rows_;
    std::vector<int32_t> shutter_row_slots_,shutter_fallback_;
    std::vector<std::vector<uint32_t>> shutter_owners_by_row_;
    bool shutter_enabled_=true;
    double shutter_surface_gain_=1,shutter_beam_gain_=1;
    uint64_t shutter_beam_writes_=0,shutter_material_writes_=0,shutter_ticks_=0,shutter_us_=0,shutter_lens_submissions_=0;
    void ingest_shutters(const peraviz::runtime::SectionedVisualFrame &frame);

    NativeLensBatches lenses_;
    PackedInt32Array script_rows_;
    void retire_async(bool replay_domains=true);
    Dictionary poll_async(const Ref<PeravizVisualRuntime> &runtime,int64_t generation,int32_t schema_generation,bool trace);
    std::shared_ptr<peraviz::presentation::AsyncPresentationPipeline> async_;
    Ref<PeravizVisualRuntime> async_runtime_;
    std::vector<peraviz::presentation::RenderValues> displayed_physical_;
    peraviz::presentation::NativePresentationSizes async_sizes_;
    peraviz::runtime::SectionedVisualFrame deferred_domains_;
    bool async_disabled_=false,async_forced_=false,resume_pending_=false;
    size_t async_snapshot_bytes_=0,async_worker_bytes_=0;
    void begin_snapshot(bool trace);
    Dictionary publish(int64_t generation, bool trace, int64_t physical_us, int64_t projection_us);
    peraviz::presentation::DirectPresentationPipeline pipeline_;
    peraviz::presentation::DensePresentationState state_;
    peraviz::presentation::RenderGroupProjection projection_;
    PresentationMaterialBindings materials_;
    PresentationMaterialBindings footprints_;
    std::vector<int32_t> fixture_ids_;
    bool diagnostic_skip_lens_writes_=false, lens_writes_suppressed_=false;
    // Exactly renderer-row-sized borrowed buffers; no physical/group duplicate payloads.
    PackedInt32Array indices_masks_;
    PackedFloat32Array values_;
};
} // namespace godot
