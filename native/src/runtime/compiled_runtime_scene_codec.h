#pragma once

#include "runtime/visual_runtime_types.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace peraviz::runtime {

constexpr int32_t kPackedSceneV7HeaderIntegers = 11;
constexpr int32_t kPackedSceneV7SourceFixedIntegers = 14;
constexpr int32_t kPackedSceneV6SourceFixedIntegers = 8;
constexpr int32_t kPackedSceneFixtureIntegers = 6;
constexpr int32_t kPackedSceneByteSourceIntegers = 3;
constexpr int32_t kPackedSceneGoboMotionIntegers = 13;

struct PackedCompiledRuntimeScene {
    std::vector<int32_t> integers;
    std::vector<float> floats;
};

struct CompiledRuntimeSceneDecodeResult {
    CompiledRuntimeScene scene;
    size_t consumed_integers = 0;
    bool valid = false;
    std::string diagnostic;
};

PackedCompiledRuntimeScene encode_compiled_runtime_scene(const CompiledRuntimeScene &scene);
CompiledRuntimeSceneDecodeResult decode_compiled_runtime_scene(const std::vector<int32_t> &integers, const std::vector<float> &floats);

} // namespace peraviz::runtime
