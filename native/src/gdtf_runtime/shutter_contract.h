#pragma once
#include <algorithm>
#include <cmath>
#include <charconv>
#include <cstdint>
#include <string>

namespace peraviz::gdtf_runtime {
enum class ShutterWave : int32_t { Unsupported=-1, Open=0, Closed=1, Strobe=2, Pulse=3, PulseOpen=4, PulseClose=5, Duration=6, Frequency=7, Mode=8 };
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
    } else if (name.rfind("Strobe",0)==0) {
        out.recognized=true;
        if (name=="StrobeFrequency") out.wave=ShutterWave::Frequency;
        else if (name=="StrobeDuration") out.wave=ShutterWave::Duration;
        else if (name=="StrobeModeShutter") out.wave=ShutterWave::Mode;
        else if (name=="StrobeModeStrobe") out.wave=ShutterWave::Strobe;
        else if (name=="StrobeModePulse") out.wave=ShutterWave::Pulse;
        else if (name=="StrobeModePulseOpen") out.wave=ShutterWave::PulseOpen;
        else if (name=="StrobeModePulseClose") out.wave=ShutterWave::PulseClose;
    }
    return out;
}
// Explicit English source labels establish polarity; generic Shutter is never a linear dimmer.
inline ShutterWave shutter_label(std::string label) {
    std::transform(label.begin(),label.end(),label.begin(),[](unsigned char c){return c>='A'&&c<='Z'?char(c+'a'-'A'):char(c);});
    if (label=="open" || label=="shutter open") return ShutterWave::Open;
    if (label=="closed" || label=="close" || label=="shutter closed") return ShutterWave::Closed;
    return ShutterWave::Unsupported;
}
struct ShutterParameters {
    ShutterWave wave=ShutterWave::Open;
    int32_t function_id=0, revision=0, status=0;
    double frequency=0, duration=0.025, duty=1, offset=1, phase=0, reference=0;
};
// Wraps a phase consistently for negative offsets and explicit test timestamps.
inline double shutter_fraction(double value) { return value-std::floor(value); }
// Evaluates Annex F's end-offset convention; square flashes use Duration, not DutyCycle.
inline double shutter_envelope(const ShutterParameters &p,double now) {
    if (p.wave==ShutterWave::Closed) return 0;
    if (p.wave==ShutterWave::Open || p.wave==ShutterWave::Unsupported || p.frequency<=0) return 1;
    const double phase=shutter_fraction(p.phase+std::max(now-p.reference,0.0)*p.frequency);
    const double width=std::clamp(p.wave==ShutterWave::Strobe?p.duration*p.frequency:p.duty,0.0,1.0);
    if (width<=0) return 0;
    const double local=shutter_fraction(phase-(p.offset-width));
    if (local>=width) return 0;
    const double x=local/width;
    if (p.wave==ShutterWave::Pulse) return 1-std::abs(2*x-1);
    if (p.wave==ShutterWave::PulseOpen) return x;
    if (p.wave==ShutterWave::PulseClose) return 1-x;
    return 1;
}
// Changes parameters only on effective state changes; frequency edits integrate the previous phase.
inline bool update_shutter(ShutterParameters &held,ShutterParameters next,double now) {
    if (held.revision && held.function_id==next.function_id && held.wave==next.wave && held.frequency==next.frequency &&
        held.duration==next.duration && held.duty==next.duty && held.offset==next.offset && held.status==next.status) return false;
    next.phase=held.revision && held.function_id==next.function_id && held.wave==next.wave ?
        shutter_fraction(held.phase+std::max(now-held.reference,0.0)*held.frequency):0;
    next.reference=now; next.revision=held.revision+1; held=next;
    return true;
}
}
