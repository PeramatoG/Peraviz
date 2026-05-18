#pragma once

// Defines Peraviz-local matrix basis and origin storage used by MVR/GDTF transforms.

#include <array>

struct Matrix {
    std::array<float, 3> u{1.0f, 0.0f, 0.0f};
    std::array<float, 3> v{0.0f, 1.0f, 0.0f};
    std::array<float, 3> w{0.0f, 0.0f, 1.0f};
    std::array<float, 3> o{0.0f, 0.0f, 0.0f};
};
