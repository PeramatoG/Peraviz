#pragma once
#include "gdtf_runtime/shutter_contract.h"
#include "presentation/dense_presentation_state.h"
#include "runtime/visual_frame_schema.h"
#include <chrono>
#include <unordered_map>

namespace peraviz::presentation {
// Main-thread temporal presentation only. Canonical source evaluation remains in the native runtime.
class ShutterPlayback {
    using Clock=std::chrono::steady_clock;
    struct Layer { gdtf_runtime::ShutterParameters p; uint32_t owner=0; };
    Clock::time_point epoch_;
    bool clock_set_=false;
    std::unordered_map<int32_t,uint32_t> owners_;
    std::unordered_map<int64_t,Layer> layers_;
    std::vector<std::vector<int64_t>> by_owner_;
    std::vector<uint32_t> active_, dirty_, changed_;
    std::vector<int32_t> active_slot_;
    std::vector<uint8_t> nominated_,force_;
    std::vector<float> envelopes_;
    uint64_t evaluations_=0,changes_=0;
public:
    // Allocates owner routes only at physical binding installation.
    void install(const std::vector<OutputBinding> &bindings) {
        *this={}; by_owner_.resize(bindings.size()); envelopes_.assign(bindings.size(),1);
        nominated_.assign(bindings.size(),0); force_.assign(bindings.size(),0); active_slot_.assign(bindings.size(),-1);
        active_.reserve(bindings.size()); dirty_.reserve(bindings.size()); changed_.reserve(bindings.size());
        for (uint32_t i=0;i<bindings.size();++i) owners_.emplace(bindings[i].canonical_id,i);
    }
    // Deduplicates renderer invalidation without scanning the full imported scene.
    void nominate(uint32_t owner,bool force=false) {
        if (owner>=nominated_.size() || by_owner_[owner].empty()) return;
        force_[owner]|=force;
        if (!nominated_[owner]) { nominated_[owner]=1; dirty_.push_back(owner); }
    }
    // Replays only shutter-owned outputs after resource/policy replacement.
    void invalidate() { for (const auto &[id,owner]:owners_) if (!by_owner_[owner].empty()) nominate(owner,true); }
    // Admits changed native temporal parameters, preserving local phase on identical/stale publications.
    bool ingest(const int32_t *d,size_t nd,const int32_t *ints,size_t ni,const float *v,size_t nv) {
        using namespace gdtf_runtime;
        if (nd%5) return false;
        for (size_t b=0;b<nd;b+=5) if (d[b]==int(runtime::VisualSectionType::ShutterState)) {
            if (d[b+1]<0 || d[b+2]<0 || d[b+3]<0 || size_t(d[b+2])+size_t(d[b+1])*7>ni || size_t(d[b+3])+size_t(d[b+1])*7>nv) return false;
            for (int row=0;row<d[b+1];++row) {
                const auto *i=ints+d[b+2]+row*7; const auto *f=v+d[b+3]+row*7;
                if (i[2]<1 || i[3]<-1 || i[3]>5 || i[4]<1) return false;
                for (int j=0;j<7;++j) if (!std::isfinite(f[j])) return false;
            }
        }
        const auto received=Clock::now();
        for (size_t b=0;b+4<nd;b+=5) if (d[b]==int(runtime::VisualSectionType::ShutterState)) {
            for (int row=0;row<d[b+1];++row) {
                const auto *i=ints+d[b+2]+row*7; const auto *f=v+d[b+3]+row*7;
                const auto owner=owners_.find(i[1]); if (owner==owners_.end()) continue;
                for (int j=0;j<7;++j) if (!std::isfinite(f[j])) return false;
                const int64_t key=(int64_t(i[1])<<32)|uint32_t(i[2]);
                auto found=layers_.find(key);
                if (found!=layers_.end() && found->second.p.revision>=i[4]) continue;
                auto &layer=layers_[key];
                if (!layer.p.revision) by_owner_[owner->second].push_back(key);
                layer.owner=owner->second;
                if (!clock_set_) {
                    epoch_=received-std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(f[6]));
                    clock_set_=true;
                }
                layer.p={ShutterWave(i[3]),i[6],i[4],i[5],f[0],f[1],f[2],f[3],f[4],f[5]};
                bool active=false;
                for (auto k:by_owner_[layer.owner]) { const auto &p=layers_.at(k).p; active|=p.wave>=ShutterWave::Strobe && p.wave<=ShutterWave::PulseClose && p.frequency>0; }
                auto &slot=active_slot_[layer.owner];
                if (active && slot<0) { slot=int32_t(active_.size()); active_.push_back(layer.owner); }
                if (!active && slot>=0) { const auto last=active_.back(); active_[slot]=last; active_slot_[last]=slot; active_.pop_back(); slot=-1; }
                nominate(layer.owner,true);
            }
        }
        return true;
    }
    // Advances only active/changed owners; explicit absolute native timestamps make tests deterministic.
    const std::vector<uint32_t> &tick(double test_now=-1) {
        using namespace gdtf_runtime;
        changed_.clear();
        if (active_.empty() && dirty_.empty()) return changed_;
        const double now=test_now>=0?test_now:std::chrono::duration<double>(Clock::now()-epoch_).count();
        for (uint32_t owner:active_) nominate(owner);
        for (uint32_t owner:dirty_) {
            float value=1;
            for (int64_t key:by_owner_[owner]) {
                const auto &layer=layers_.at(key);
                value*=float(shutter_envelope(layer.p,now)); ++evaluations_;
            }
            if (force_[owner] || value!=envelopes_[owner]) { envelopes_[owner]=value; changed_.push_back(owner); ++changes_; }
            nominated_[owner]=0; force_[owner]=0;
        }
        dirty_.clear(); return changed_;
    }
    // Estimates retained CPU buffers at explicit diagnostic boundaries; map-node allocator overhead is approximate.
    size_t buffer_bytes() const {
        size_t bytes=envelopes_.capacity()*sizeof(float)+(active_.capacity()+dirty_.capacity()+changed_.capacity()+active_slot_.capacity())*4;
        bytes+=(nominated_.capacity()+force_.capacity())*sizeof(uint8_t)+by_owner_.capacity()*sizeof(std::vector<int64_t>);
        for (const auto &layers:by_owner_) bytes+=layers.capacity()*sizeof(int64_t);
        return bytes+layers_.size()*(sizeof(Layer)+sizeof(int64_t)+2*sizeof(void*))+owners_.size()*(8+2*sizeof(void*));
    }
    // Borrows presentation multipliers independently of immutable physical values.
    const std::vector<float> &envelopes() const { return envelopes_; }
    // Reports whether the indexed presentation call has any work.
    bool pending() const { return !active_.empty() || !dirty_.empty(); }
    // Reports changing physical outputs independently of the imported scene size.
    size_t active() const { return active_.size(); }
    // Counts retained native temporal identities.
    size_t layers() const { return layers_.size(); }
    // Counts numerical waveform samples for focused diagnostics.
    uint64_t evaluations() const { return evaluations_; }
    // Counts committed envelope transitions, including explicit resource replays.
    uint64_t changes() const { return changes_; }
};
}
