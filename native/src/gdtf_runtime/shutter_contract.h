#pragma once
#include <algorithm>
#include <cmath>
#include <charconv>
#include <cstdint>
#include <string>

namespace peraviz::gdtf_runtime {
enum class ShutterWave : int32_t { Unsupported=-1, Open=0, Closed=1, Strobe=2, Pulse=3, PulseOpen=4, PulseClose=5, Duration=6, Frequency=7, Mode=8, RandomStrobe=9, RandomPulse=10, RandomOpen=11, RandomClose=12 };
struct ShutterAttribute { ShutterWave wave=ShutterWave::Unsupported; int32_t index=1; bool recognized=false; };
// Recognizes exact official numbered families, never arbitrary strings containing "strobe".
inline ShutterAttribute shutter_attribute(const std::string &name) {
    ShutterAttribute out;
    std::string suffix;
    if (name.rfind("Shutter",0)==0) {
        size_t end=7;
        while (end<name.size() && name[end]>='0' && name[end]<='9') ++end;
        if (end==7) return out;
        const auto parsed=std::from_chars(name.data()+7,name.data()+end,out.index);
        if (parsed.ec!=std::errc() || out.index<1) return out;
        suffix=name.substr(end);
        out.recognized=true;
        if (suffix.empty()) out.wave=ShutterWave::Mode;
        else if (suffix=="Strobe") out.wave=ShutterWave::Strobe;
        else if (suffix=="StrobePulse") out.wave=ShutterWave::Pulse;
        else if (suffix=="StrobePulseOpen") out.wave=ShutterWave::PulseOpen;
        else if (suffix=="StrobePulseClose") out.wave=ShutterWave::PulseClose;
        else if (suffix=="StrobeRandom") out.wave=ShutterWave::RandomStrobe;
        else if (suffix=="StrobeRandomPulse") out.wave=ShutterWave::RandomPulse;
        else if (suffix=="StrobeRandomPulseOpen") out.wave=ShutterWave::RandomOpen;
        else if (suffix=="StrobeRandomPulseClose") out.wave=ShutterWave::RandomClose;
    } else if (name.rfind("Strobe",0)==0) {
        out.recognized=true;
        if (name=="StrobeFrequency") out.wave=ShutterWave::Frequency;
        else if (name=="StrobeDuration") out.wave=ShutterWave::Duration;
        else if (name=="StrobeModeShutter") out.wave=ShutterWave::Mode;
        else if (name=="StrobeModeStrobe") out.wave=ShutterWave::Strobe;
        else if (name=="StrobeModePulse") out.wave=ShutterWave::Pulse;
        else if (name=="StrobeModePulseOpen") out.wave=ShutterWave::PulseOpen;
        else if (name=="StrobeModePulseClose") out.wave=ShutterWave::PulseClose;
        else if (name=="StrobeModeRandom") out.wave=ShutterWave::RandomStrobe;
        else if (name=="StrobeModeRandomPulse") out.wave=ShutterWave::RandomPulse;
        else if (name=="StrobeModeRandomPulseOpen") out.wave=ShutterWave::RandomOpen;
        else if (name=="StrobeModeRandomPulseClose") out.wave=ShutterWave::RandomClose;
    }
    return out;
}
// Explicit English source labels establish polarity; generic Shutter is never a linear dimmer.
inline ShutterWave shutter_label(std::string label) {
    std::string normalized;
    for (unsigned char c:label) {
        if (c>='A' && c<='Z') c+=32;
        if (c==' ' || c=='\t' || c=='\n' || c=='\r' || c=='_' || c=='-' || c==':' || c=='(' || c==')') {
            if (!normalized.empty() && normalized.back()!=' ') normalized+=' ';
        } else normalized+=char(c);
    }
    if (!normalized.empty() && normalized.back()==' ') normalized.pop_back();
    if (normalized=="open" || normalized=="shutter open" || normalized=="open shutter" || normalized=="shutter fully open") return ShutterWave::Open;
    if (normalized=="closed" || normalized=="close" || normalized=="shutter closed" || normalized=="shutter close" || normalized=="closed shutter" || normalized=="close shutter" || normalized=="shutter fully closed") return ShutterWave::Closed;
    return ShutterWave::Unsupported;
}
struct ShutterParameters {
    ShutterWave wave=ShutterWave::Open;
    int32_t function_id=0, revision=0, status=0;
    double frequency=0, duration=0.025, duty=1, offset=1, phase=0, reference=0;
    int32_t activation=0;
    uint32_t seed=0; // Deterministic immutable control-authority seed, independent of physical member identity.
};
// Wraps a phase consistently for negative offsets and explicit test timestamps.
inline double shutter_fraction(double value) { return value-std::floor(value); }
// Recognizes temporal modes without treating parameter or generic selector attributes as waveforms.
inline bool shutter_random(ShutterWave wave) { return wave>=ShutterWave::RandomStrobe && wave<=ShutterWave::RandomClose; }
// Includes official random families in the existing compact active set.
inline bool shutter_periodic(ShutterWave wave) { return (wave>=ShutterWave::Strobe && wave<=ShutterWave::PulseClose) || shutter_random(wave); }
// Maps random presentation onto the same square/triangle/ramp definitions, never onto a generic square wave.
inline ShutterWave shutter_shape(ShutterWave wave) { return shutter_random(wave)?ShutterWave(int(wave)-7):wave; }
// Produces a reproducible counter-based value; no mutable RNG or per-frame random decisions exist.
inline uint64_t shutter_mix(uint64_t value) {
    value+=0x9e3779b97f4a7c15ULL; value=(value^(value>>30))*0xbf58476d1ce4e5b9ULL;
    value=(value^(value>>27))*0x94d049bb133111ebULL; return value^(value>>31);
}
// One event per nominal cycle, jittered within its middle half. Intervals are bounded to [0.5,1.5]/Hz.
// This stratified distribution is a Peraviz approximation; GDTF does not prescribe a random distribution.
inline double shutter_event_start(const ShutterParameters &p,int64_t index) {
    const uint64_t key=shutter_mix((uint64_t(p.seed)<<32)|uint32_t(p.activation))^shutter_mix(uint32_t(p.function_id));
    const double jitter=double(shutter_mix(key^uint64_t(index))>>11)*(1.0/9007199254740992.0);
    return double(index)+0.25+0.5*jitter;
}
// Evaluates a normalized active square/triangle/ramp without altering its duration or canonical intensity.
inline double shutter_shape_value(ShutterWave wave,double x) {
    if (wave==ShutterWave::Pulse) return 1-std::abs(2*x-1);
    if (wave==ShutterWave::PulseOpen) return x;
    if (wave==ShutterWave::PulseClose) return 1-x;
    return 1;
}
// Evaluates Annex F's end-offset convention; random event positions use bounded stateless counter jitter.
inline double shutter_envelope(const ShutterParameters &p,double now) {
    if (p.wave==ShutterWave::Closed) return 0;
    if (!shutter_periodic(p.wave) || p.frequency<=0) return 1;
    const double cycles=p.phase+std::max(now-p.reference,0.0)*p.frequency;
    const auto shape=shutter_shape(p.wave);
    const double width=shutter_random(p.wave) && shape==ShutterWave::Strobe?
        std::max(0.0,p.duration*p.frequency):std::clamp(shape==ShutterWave::Strobe?p.duration*p.frequency:p.duty,0.0,1.0);
    if (width<=0) return 0;
    if (shutter_random(p.wave)) {
        // Long equal-duration flashes overlap continuously once their window covers every bounded interval.
        if (shape==ShutterWave::Strobe && width>=1.75 && p.offset>=0 && p.offset<=1) return 1;
        const double position=cycles-p.offset+width;
        // Counter overflow is outside representable timing, never an unchecked floating-to-integer conversion.
        if (!std::isfinite(position) || position<0 || position>=double(INT64_MAX-2)) return 0;
        const auto index=int64_t(std::floor(position)); double envelope=0;
        // Two candidates suffice: pulses span at most one cycle; equal-duration square flashes need only the latest event.
        for (int64_t event=index-1;event<=index;++event) if (event>=0) {
            const double local=position-shutter_event_start(p,event);
            if (local>=0 && local<width) envelope=std::max(envelope,shutter_shape_value(shape,local/width));
        }
        return envelope;
    }
    const double local=shutter_fraction(shutter_fraction(cycles)-(p.offset-width));
    return local>=width?0:shutter_shape_value(shape,local/width);
}
// Changes parameters only on effective state changes; frequency edits integrate the previous phase.
inline bool update_shutter(ShutterParameters &held,ShutterParameters next,double now) {
    if (held.revision && held.function_id==next.function_id && held.wave==next.wave && held.frequency==next.frequency &&
        held.duration==next.duration && held.duty==next.duty && held.offset==next.offset && held.status==next.status) return false;
    const bool continuing=held.revision && held.function_id==next.function_id && held.wave==next.wave;
    const double accumulated=held.phase+std::max(now-held.reference,0.0)*held.frequency;
    next.phase=continuing?(shutter_random(next.wave)?accumulated:shutter_fraction(accumulated)):0;
    next.activation=continuing?held.activation:held.revision+1;
    next.reference=now; next.revision=held.revision+1; held=next;
    return true;
}
}
