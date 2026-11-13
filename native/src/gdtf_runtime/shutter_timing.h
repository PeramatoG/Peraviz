#pragma once
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include <array>
#include <cmath>
#include <unordered_set>

namespace peraviz::gdtf_runtime {
struct ShutterTiming {
    std::array<double,3> from{{0.025,1,1}},to{{0.025,1,1}};
    int32_t variable_mask=0;
    bool valid=true;
};
// Resolves function-local timing intervals, preserving explicit invalid data and local Type links.
inline ShutterTiming compile_shutter_timing(const ChannelProgram &program,const AttributeIdentity *attribute) {
    ShutterTiming timing;
    timing.valid=!program.shutter_subsets_invalid;
    std::unordered_set<std::string> types;
    if (attribute) for (auto sub:attribute->subphysical_units) {
        if (!types.insert(sub.type).second || !std::isfinite(sub.physical_from) || !std::isfinite(sub.physical_to)) timing.valid=false;
        int matches=0;
        for (const auto &override:program.shutter_subsets) if (override.type==sub.type) {
            ++matches; sub.physical_from=override.physical_from; sub.physical_to=override.physical_to;
        }
        if (matches>1) timing.valid=false;
        const int index=sub.type=="Duration"?0:sub.type=="DutyCycle"?1:sub.type=="TimeOffset"?2:-1;
        if (index<0) continue;
        const char *unit=index==0?"Time":"Percent";
        if (!sub.physical_unit.empty() && sub.physical_unit!="None" && sub.physical_unit!=unit) timing.valid=false;
        const double scale=index==0?1:0.01;
        timing.from[index]=sub.physical_from*scale; timing.to[index]=sub.physical_to*scale;
        if (timing.from[index]!=timing.to[index]) timing.variable_mask|=1<<index;
    }
    for (const auto &override:program.shutter_subsets)
        if (!types.count(override.type) || (override.type!="Duration" && override.type!="DutyCycle" && override.type!="TimeOffset")) timing.valid=false;
    for (size_t index=0;index<3;++index) for (double value:{timing.from[index],timing.to[index]})
        if (!std::isfinite(value) || value<0 || (index>0 && value>1)) timing.valid=false;
    return timing;
}
}
