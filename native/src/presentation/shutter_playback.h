#pragma once
#include "gdtf_runtime/shutter_contract.h"
#include "presentation/dense_presentation_state.h"
#include "runtime/visual_frame_schema.h"
#include <chrono>
#include <unordered_map>

namespace peraviz::presentation {
// Main-thread presentation: one sampled effect per proven native authority, with indexed physical broadcasting.
class ShutterPlayback {
    using Clock=std::chrono::steady_clock;
    struct Authority {
        int32_t id=0,index=1,active_slot=-1;
        gdtf_runtime::ShutterParameters p;
        std::vector<uint32_t> owners;
        float value=1;
        bool dirty=false;
    };
    Clock::time_point epoch_;
    bool clock_set_=false;
    std::unordered_map<int32_t,uint32_t> owners_,authority_slots_;
    std::vector<Authority> authorities_;
    std::vector<std::vector<uint32_t>> by_owner_;
    std::vector<uint32_t> active_,dirty_authorities_,dirty_,changed_,active_layers_;
    std::vector<uint8_t> nominated_,force_;
    std::vector<float> envelopes_;
    size_t active_outputs_=0,associations_=0;
    uint64_t evaluations_=0,changes_=0;
    // Maintains physical activity counts only on membership/mode changes, never by walking idle scene outputs.
    void activity(uint32_t owner,bool add) {
        if (add) { if (active_layers_[owner]++==0) ++active_outputs_; }
        else if (--active_layers_[owner]==0) --active_outputs_;
    }
    // Schedules at most one evaluation per control for this presentation sample.
    void evaluate_later(uint32_t slot) {
        if (!authorities_[slot].dirty) { authorities_[slot].dirty=true; dirty_authorities_.push_back(slot); }
    }
public:
    // Allocates physical routes at installation; authority membership arrives with native parameter rows.
    void install(const std::vector<OutputBinding> &bindings) {
        *this={}; by_owner_.resize(bindings.size()); envelopes_.assign(bindings.size(),1); active_layers_.assign(bindings.size(),0);
        nominated_.assign(bindings.size(),0); force_.assign(bindings.size(),0);
        active_.reserve(bindings.size()); dirty_authorities_.reserve(std::min<size_t>(bindings.size(),8)); authorities_.reserve(std::min<size_t>(bindings.size(),8));
        dirty_.reserve(bindings.size()); changed_.reserve(bindings.size()); authority_slots_.reserve(std::min<size_t>(bindings.size(),8));
        for (uint32_t i=0;i<bindings.size();++i) owners_.emplace(bindings[i].canonical_id,i);
    }
    // Invalidates only presentation resources; control phase and shared cached envelopes remain authoritative.
    void nominate(uint32_t owner,bool force=false) {
        if (owner>=nominated_.size() || by_owner_[owner].empty()) return;
        force_[owner]|=force;
        if (!nominated_[owner]) { nominated_[owner]=1; dirty_.push_back(owner); }
    }
    // Replays retained shutter-owned resources after reconfiguration, without restarting their shared controls.
    void invalidate() { for (const auto &[id,owner]:owners_) if (!by_owner_[owner].empty()) nominate(owner,true); }
    // Admits native authority IDs/seeds, not inferred equality of values or physical geometry identity.
    bool ingest(const int32_t *d,size_t nd,const int32_t *ints,size_t ni,const float *v,size_t nv) {
        using namespace gdtf_runtime;
        if (nd%5) return false;
        for (size_t b=0;b<nd;b+=5) if (d[b]==int(runtime::VisualSectionType::ShutterState)) {
            if (d[b+1]<0 || d[b+2]<0 || d[b+3]<0 || size_t(d[b+2])+size_t(d[b+1])*10>ni || size_t(d[b+3])+size_t(d[b+1])*7>nv) return false;
            for (int row=0;row<d[b+1];++row) {
                const auto *i=ints+d[b+2]+row*10; const auto *f=v+d[b+3]+row*7;
                if (i[2]<1 || i[8]<1 || i[3]<-1 || (i[3]>5 && (i[3]<9 || i[3]>12)) || i[4]<1) return false;
                for (int j=0;j<7;++j) if (!std::isfinite(f[j])) return false;
            }
        }
        const auto received=Clock::now();
        for (size_t b=0;b<nd;b+=5) if (d[b]==int(runtime::VisualSectionType::ShutterState)) for (int row=0;row<d[b+1];++row) {
            const auto *i=ints+d[b+2]+row*10; const auto *f=v+d[b+3]+row*7;
            const auto owner=owners_.find(i[1]); if (owner==owners_.end()) continue;
            const auto inserted=authority_slots_.emplace(i[8],uint32_t(authorities_.size()));
            if (inserted.second) { Authority authority; authority.id=i[8]; authority.index=i[2]; authorities_.push_back(std::move(authority)); }
            const auto slot=inserted.first->second; auto &authority=authorities_[slot];
            if (authority.index!=i[2]) return false;
            if (!clock_set_) {
                epoch_=received-std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(f[6])); clock_set_=true;
            }
            if (authority.p.revision<i[4]) {
                authority.p={ShutterWave(i[3]),i[6],i[4],i[5],f[0],f[1],f[2],f[3],f[4],f[5]};
                authority.p.activation=i[7]; authority.p.seed=uint32_t(i[9]);
                const bool active=shutter_periodic(authority.p.wave) && authority.p.frequency>0;
                if (active && authority.active_slot<0) {
                    authority.active_slot=int32_t(active_.size()); active_.push_back(slot);
                    for (uint32_t member:authority.owners) activity(member,true);
                } else if (!active && authority.active_slot>=0) {
                    const auto last=active_.back(); active_[authority.active_slot]=last; authorities_[last].active_slot=authority.active_slot;
                    active_.pop_back(); authority.active_slot=-1;
                    for (uint32_t member:authority.owners) activity(member,false);
                }
                evaluate_later(slot);
            }
            auto &routes=by_owner_[owner->second];
            if (std::find(routes.begin(),routes.end(),slot)==routes.end()) {
                routes.push_back(slot); authority.owners.push_back(owner->second); ++associations_;
                if (authority.active_slot>=0) activity(owner->second,true);
                nominate(owner->second,true);
            }
        }
        return true;
    }
    // Samples each active/changed authority once, then broadcasts only changed results to indexed physical members.
    const std::vector<uint32_t> &tick(double test_now=-1) {
        using namespace gdtf_runtime;
        changed_.clear();
        if (!pending()) return changed_;
        const double now=test_now>=0?test_now:std::chrono::duration<double>(Clock::now()-epoch_).count();
        for (uint32_t slot:active_) evaluate_later(slot);
        for (uint32_t slot:dirty_authorities_) {
            auto &authority=authorities_[slot];
            const float value=float(shutter_envelope(authority.p,now)); ++evaluations_;
            if (authority.value!=value) { authority.value=value; for (uint32_t owner:authority.owners) nominate(owner); }
            authority.dirty=false;
        }
        dirty_authorities_.clear();
        for (uint32_t owner:dirty_) {
            float value=1;
            for (uint32_t slot:by_owner_[owner]) value*=authorities_[slot].value;
            if (force_[owner] || value!=envelopes_[owner]) { envelopes_[owner]=value; changed_.push_back(owner); ++changes_; }
            nominated_[owner]=0; force_[owner]=0;
        }
        dirty_.clear(); return changed_;
    }
    // Estimates retained buffers only at opt-in diagnostic boundaries, excluding allocator/GPU accounting precision.
    size_t buffer_bytes() const {
        size_t bytes=envelopes_.capacity()*4+(active_.capacity()+dirty_authorities_.capacity()+dirty_.capacity()+changed_.capacity()+active_layers_.capacity())*4;
        bytes+=nominated_.capacity()+force_.capacity()+by_owner_.capacity()*sizeof(std::vector<uint32_t>)+authorities_.capacity()*sizeof(Authority);
        for (const auto &routes:by_owner_) bytes+=routes.capacity()*4;
        for (const auto &authority:authorities_) bytes+=authority.owners.capacity()*4;
        return bytes+(owners_.size()+authority_slots_.size())*(8+2*sizeof(void*));
    }
    // Exposes authority routing per numbered layer only on explicit inspection requests.
    std::vector<int32_t> authority_ids(int32_t index) const {
        std::vector<int32_t> result(by_owner_.size(),0);
        for (size_t owner=0;owner<by_owner_.size();++owner) for (auto slot:by_owner_[owner])
            if (authorities_[slot].index==index) result[owner]=authorities_[slot].id;
        return result;
    }
    // Borrows physical presentation multipliers, independently of canonical native intensity/color state.
    const std::vector<float> &envelopes() const { return envelopes_; }
    // Keeps idle/Open/Closed scenes free of continuous temporal work.
    bool pending() const { return !active_.empty() || !dirty_authorities_.empty() || !dirty_.empty(); }
    // Counts affected physical outputs without rescanning the imported scene.
    size_t active() const { return active_outputs_; }
    // Counts immutable physical-to-layer associations, not duplicate temporal instances.
    size_t layers() const { return associations_; }
    // Counts actual temporal controls and their compact active prefix.
    size_t authorities() const { return authorities_.size(); }
    // Counts controls requiring continuous numerical evaluation.
    size_t active_authorities() const { return active_.size(); }
    // Counts samples once per authority, independent of member count.
    uint64_t evaluations() const { return evaluations_; }
    // Counts committed physical envelope changes and explicit renderer replays.
    uint64_t changes() const { return changes_; }
};
}
