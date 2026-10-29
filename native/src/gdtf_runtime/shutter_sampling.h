#pragma once
#include "gdtf_runtime/shutter_contract.h"
#include <array>

namespace peraviz::gdtf_runtime {
struct ShutterSampling { int fps=0,events=0,visible_events=0; double event_window_seconds=0; };
// Compares exact event windows with uniform presentation samples, with frozen parameters and bounded work.
// This is an opt-in aliasing diagnostic, not a change to the physically defined waveform or period.
inline std::array<ShutterSampling,4> shutter_sampling(ShutterParameters p) {
    std::array<ShutterSampling,4> rows{{{15},{30},{60},{120}}};
    if (!shutter_periodic(p.wave) || p.frequency<=0 || !std::isfinite(p.frequency)) return rows;
    const auto shape=shutter_shape(p.wave);
    const double width=shape==ShutterWave::Strobe?std::max(0.0,p.duration*p.frequency):std::clamp(p.duty,0.0,1.0);
    if (!std::isfinite(width) || width>=double(INT64_MAX-32)) return rows;
    const int64_t first=std::max<int64_t>(2,int64_t(std::ceil(width))+2);
    for (auto &row:rows) for (int event=0;event<20;++event) {
        const double begin=(p.offset-width+(shutter_random(p.wave)?shutter_event_start(p,event+first):event+first))/p.frequency;
        const double end=begin+width/p.frequency;
        ++row.events; row.event_window_seconds+=width/p.frequency;
        double sample=std::ceil(begin*row.fps)/row.fps;
        // Pulse/ramp starts may be exactly dark. The following sample is the only other candidate needed.
        for (int candidate=0;candidate<2;++candidate,sample+=1.0/row.fps) if (width>0 && sample>=begin-1e-12 && sample<end-1e-12 && shutter_shape_value(shape,std::max(0.0,(sample-begin)*p.frequency/width))>1e-12) {
            ++row.visible_events; break;
        }
    }
    return rows;
}
}
