#include "presentation/render_group_projection.h"
#include "runtime/visual_runtime_types.h"
#include <algorithm>
#include <cmath>

namespace peraviz::presentation {
namespace {
using namespace runtime;
// Decodes the existing boundary's sRGB chromaticity before radiometric accumulation.
double linear(double c) { c=std::clamp(c,0.0,1.0); return c<=0.04045?c/12.92:std::pow((c+0.055)/1.055,2.4); }
// Encodes once at the renderer boundary; the shader's source_color conversion stays unchanged.
float encoded(double c) { c=std::clamp(c,0.0,1.0); return float(c<=0.0031308?12.92*c:1.055*std::pow(c,1.0/2.4)-0.055); }
// Builds the member's already photometrically scaled contribution without double-applying flux or gain.
MemberContribution contribution(const RenderValues &v) {
    MemberContribution c;
    c.values=v; c.valid=true;
    c.energy=std::max(0.0f,v[BeamEnergy]);
    c.red=linear(v[Red])*c.energy; c.green=linear(v[Green])*c.energy; c.blue=linear(v[Blue])*c.energy;
    c.intensity=std::max(0.0f,v[BeamIntensity]);
    return c;
}
}
// Validates complete inverse membership and reserves exactly one boundary row per renderer source.
bool RenderGroupProjection::install(const std::vector<uint32_t> &mapping, const std::vector<RenderPresentationClass> &classes) {
    std::vector<uint32_t> counts(classes.size(),0);
    for (uint32_t row:mapping) { if (row>=classes.size()) return false; ++counts[row]; }
    for (size_t r=0;r<classes.size();++r) if (counts[r]==0 || (classes[r]!=RenderPresentationClass::Individual && classes[r]!=RenderPresentationClass::Aggregated) ||
        (classes[r]==RenderPresentationClass::Individual && counts[r]!=1)) return false;
    clear();
    physical_to_row_=mapping; members_.resize(mapping.size()); rows_.resize(classes.size());
    for (size_t r=0;r<classes.size();++r) rows_[r].presentation=classes[r];
    for (size_t i=mapping.size();i>0;--i) rows_[mapping[i-1]].representative=uint32_t(i-1);
    dirty_rows_.reserve(classes.size()); prepared_.reserve(classes.size());
    return true;
}
// Releases all setup-generation state, including derived sums and borrowed row capacity.
void RenderGroupProjection::clear() {
    decltype(physical_to_row_)().swap(physical_to_row_); decltype(members_)().swap(members_);
    decltype(rows_)().swap(rows_); decltype(prepared_)().swap(prepared_); decltype(dirty_rows_)().swap(dirty_rows_);
}
// Renderer replacement replays held values without changing static membership or moving the centroid.
void RenderGroupProjection::invalidate() { for (auto &row:rows_) row.committed=false; }
// Subtracts/adds only changed physical contributions, then emits each dirty renderer source once.
void RenderGroupProjection::prepare(const DensePresentationState &physical) {
    prepared_.clear(); dirty_rows_.clear();
    for (uint32_t index:physical.dirty_indices()) {
        if (index>=members_.size()) continue;
        auto &old=members_[index];
        auto &row=rows_[physical_to_row_[index]];
        const auto values=physical.render_values(index);
        const uint32_t pending=physical.pending_mask(index);
        if (old.valid && old.values==values && row.committed && !(pending & VisualChangeBeamTopology)) continue;
        if (row.mask==0) dirty_rows_.push_back(physical_to_row_[index]);
        row.mask |= pending | VisualChangeDimmer | VisualChangeColor | VisualChangeMaterial;
        if (!old.valid || !row.committed) row.mask |= VisualChangeBeamTopology | VisualChangeZoom;
        const auto next=contribution(values);
        if (row.presentation==RenderPresentationClass::Aggregated) {
            row.energy+=next.energy-old.energy; row.red+=next.red-old.red; row.green+=next.green-old.green;
            row.blue+=next.blue-old.blue; row.intensity+=next.intensity-old.intensity;
        }
        old=next;
    }
    for (uint32_t index:dirty_rows_) {
        auto &row=rows_[index];
        auto values=physical.render_values(row.representative);
        if (row.presentation==RenderPresentationClass::Aggregated) {
            const double energy=std::max(row.energy,0.0);
            // Keep a deterministic held chromaticity during complete blackout; physical RGB stays exact.
            for (size_t channel=Red;channel<=Blue;++channel) values[channel]=row.committed?row.previous[channel]:1.0f;
            if (energy>1e-12) { values[Red]=encoded(row.red/energy); values[Green]=encoded(row.green/energy); values[Blue]=encoded(row.blue/energy); }
            values[BeamEnergy]=values[SpotEnergy]=float(energy);
            values[BeamIntensity]=float(std::clamp(row.intensity,0.0,50.0));
            values[Dimmer]=values[Visible]=values[BeamIntensity]>0.000001f?1.0f:0.0f;
            values[MaterialEnergy]=0; values[ColorGain]=1;
        }
        if (!row.committed || row.previous!=values || (row.mask & VisualChangeBeamTopology)) {
            prepared_.push_back({index,row.mask,values}); row.previous=values; row.committed=true;
        }
        row.mask=0;
    }
}
// Reports retained POD storage in constant time, independently of trace or renderer resources.
size_t RenderGroupProjection::buffer_bytes() const {
    return physical_to_row_.capacity()*sizeof(uint32_t)+dirty_rows_.capacity()*sizeof(uint32_t)+
        members_.capacity()*sizeof(MemberContribution)+rows_.capacity()*sizeof(RenderRowAccumulator)+prepared_.capacity()*sizeof(PreparedRenderRow);
}
} // namespace peraviz::presentation
