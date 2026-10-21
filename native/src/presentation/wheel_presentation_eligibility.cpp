#include "presentation/wheel_presentation_eligibility.h"
#include "presentation/setup_index.h"
#include <algorithm>
#include <cmath>
#include <set>
#include <map>

namespace peraviz::presentation {
// Proves that the current Color-wheel presentation is resolved uniform transmission.
// Unsupported temporal/FX modes keep their declared approximation, independently of shaft resolution.
// CompiledWheelTargetBinding is emitted only by the compiler's Color-family branch;
// gobo selection/motion has separate typed bindings and a separate presentation veto.
WheelPresentationEligibility analyze_wheel_presentation(const runtime::CompiledRuntimeScene &scene,
        const runtime::CompiledBeamOpticalProfile &beam, const SetupIndex *index) {
    using namespace runtime;
    WheelPresentationEligibility result;
    if (beam.color_presentation_status==ColorPresentationStatus::MissingWheelResource) {
        result.rejection="wheel_missing_palette"; return result;
    }
    result.approximate=beam.color_presentation_status==ColorPresentationStatus::UnsupportedEffectApproximation;
    std::set<int32_t> binding_ids;
    std::map<int32_t,std::vector<const CompiledDmxSourceProgram*>> sources_by_wheel;
    std::vector<const CompiledWheelTargetBinding *> reference_bindings;
    if (!index) for (const auto &binding : scene.wheel_bindings) reference_bindings.push_back(&binding);
    const std::vector<const CompiledWheelTargetBinding *> empty;
    const auto &bindings = !index ? reference_bindings : index->wheels.count(beam.fixture_id) ? index->wheels.at(beam.fixture_id) : empty;
    for (const auto *binding_ptr : bindings) {
        const auto &binding = *binding_ptr;
        if (binding.fixture_id>0 && binding.fixture_id!=beam.fixture_id) continue;
        if (binding.beam_render_target_id>0 && binding.beam_render_target_id!=beam.render_target_id) continue;
        if (binding.fixture_id<=0 || binding.beam_render_target_id<=0) { result.rejection="wheel_ambiguous_ownership"; return result; }
        if (int32_t(binding.mode)<0 || int32_t(binding.mode)>int32_t(CompiledWheelMode::OtherUnsupported)) {
            result.rejection="wheel_unknown_presentation_contract"; return result;
        }
        result.approximate=result.approximate || binding.mode!=CompiledWheelMode::Select;
        if (binding.binding_id<=0 || binding.source_program_id<=0 || binding.wheel_renderer_id<=0 || !binding_ids.insert(binding.binding_id).second || !std::isfinite(binding.placement_offset_degrees)) {
            result.rejection="wheel_invalid_binding"; return result;
        }
        const auto reference_source = index ? scene.source_programs.end() : std::find_if(scene.source_programs.begin(),scene.source_programs.end(),
            [&](const auto &p) { return p.program_id==binding.source_program_id; });
        const auto *source = index ? index->source(binding.source_program_id) : reference_source==scene.source_programs.end() ? nullptr : &*reference_source;
        if (!source || !source->activation.valid || source->sources.empty() || source->sources.size()>4 || source->dmx_from>source->dmx_to) {
            result.rejection="wheel_missing_source_authority"; return result;
        }
        const size_t source_count = index ? index->source_counts.at(binding.source_program_id) :
            std::count_if(scene.source_programs.begin(),scene.source_programs.end(),[&](const auto &p) { return p.program_id==binding.source_program_id; });
        if (source_count!=1) { result.rejection="wheel_missing_source_authority"; return result; }
        for (const auto &byte:source->sources) if (byte.universe_id<0 || byte.universe_id!=source->sources.front().universe_id || byte.address<0 || byte.address>=512) {
            result.rejection="wheel_missing_source_authority"; return result;
        }
        if (source->activation.target_kind!=gdtf_runtime::ModeMasterTargetKind::None &&
                (index ? !index->source(source->activation.master_program_id) : std::none_of(scene.source_programs.begin(),scene.source_programs.end(),[&](const auto &p) { return p.program_id==source->activation.master_program_id; }))) {
            result.rejection="wheel_missing_source_authority"; return result;
        }
        for (const auto *previous:sources_by_wheel[binding.wheel_renderer_id]) {
            bool same_bytes=previous->sources.size()==source->sources.size();
            for (size_t i=0;same_bytes && i<source->sources.size();++i)
                same_bytes=std::tie(previous->sources[i].universe_id,previous->sources[i].address,previous->sources[i].byte_order)==
                    std::tie(source->sources[i].universe_id,source->sources[i].address,source->sources[i].byte_order);
            if (!same_bytes || (source->dmx_from<=previous->dmx_to && source->dmx_to>=previous->dmx_from)) {
                result.rejection="wheel_ambiguous_control"; return result;
            }
        }
        sources_by_wheel[binding.wheel_renderer_id].push_back(&*source);
        const auto reference_palette = index ? scene.wheel_palettes.end() : std::find_if(scene.wheel_palettes.begin(),scene.wheel_palettes.end(),
            [&](const auto &p) { return p.wheel_renderer_id==binding.wheel_renderer_id; });
        const auto *palette = index ? (index->palettes.count(binding.wheel_renderer_id) ? index->palettes.at(binding.wheel_renderer_id) : nullptr) :
            reference_palette==scene.wheel_palettes.end() ? nullptr : &*reference_palette;
        if (!palette || palette->fixture_id!=beam.fixture_id || palette->slots.empty() ||
                (index ? index->palette_counts.at(binding.wheel_renderer_id) : std::count_if(scene.wheel_palettes.begin(),scene.wheel_palettes.end(),[&](const auto &p) { return p.wheel_renderer_id==binding.wheel_renderer_id; }))!=1) {
            result.rejection="wheel_missing_palette"; return result;
        }
        SetupIndex::PaletteProof reference_proof;
        if (!index) reference_proof = SetupIndex::validate_palette(*palette);
        const auto &proof = index ? index->palette_proofs.at(binding.wheel_renderer_id) : reference_proof;
        if (proof.rejection) { result.rejection=proof.rejection; return result; }
        const auto &slots=proof.slots;
        if (binding.mode==CompiledWheelMode::Select && binding.channel_sets.empty()) { result.rejection="wheel_invalid_selection"; return result; }
        std::vector<WheelSetSignature> sets;
        for (const auto &set:binding.channel_sets) {
            if (set.dmx_from>set.dmx_to || !slots.count(set.wheel_slot_index) || !std::isfinite(set.physical_from) || !std::isfinite(set.physical_to)) {
                result.rejection="wheel_invalid_selection"; return result;
            }
            for (const auto &previous:sets) if (set.dmx_from<=std::get<1>(previous) && set.dmx_to>=std::get<0>(previous)) {
                result.rejection="wheel_ambiguous_selection"; return result;
            }
            sets.emplace_back(set.dmx_from,set.dmx_to,set.wheel_slot_index,set.physical_from,set.physical_to);
        }
        result.controls.emplace_back(binding.wheel_renderer_id,binding.source_program_id,int32_t(binding.mode),binding.snap,binding.placement_offset_degrees,std::move(sets));
    }
    return result;
}
}
