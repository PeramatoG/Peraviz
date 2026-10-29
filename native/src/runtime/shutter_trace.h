#pragma once
#include "gdtf_runtime/shutter_contract.h"
#include <cstdint>

namespace peraviz::runtime {
// Borrowed-state diagnostic records are materialized only for one explicitly selected output.
struct ShutterTrace {
    int32_t fixture=0,target=0,index=1,source=0,bytes=0;
    uint32_t from=0,to=0,raw=0;
    uint32_t mode_from=0,mode_to=UINT32_MAX;
    int64_t master_raw=-1;
    int32_t activation_function_id=0,authority=0,authority_members=0;
    double physical_from=0,physical_to=0,physical=0;
    bool initialized=false,active=false;
    gdtf_runtime::ShutterParameters parameters;
};
}
