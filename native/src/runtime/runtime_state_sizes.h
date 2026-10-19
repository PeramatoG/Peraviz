#pragma once

#include <array>
#include <cstddef>
#include <utility>

namespace peraviz::runtime {

// Fixed-shape snapshot produced only on request, never retained once per frame.
using RuntimeStateSizes = std::array<std::pair<const char *, size_t>, 13>;

} // namespace peraviz::runtime
