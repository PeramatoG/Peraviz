#pragma once

#include "types.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <iomanip>
#include <sstream>
#include <string>

namespace MatrixUtils {

// Computes the magnitude of each basis axis to extract non-uniform scale.
inline std::array<float, 3> ExtractScale(const Matrix &matrix) {
    const auto length = [](const std::array<float, 3> &axis) {
        return std::sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
    };
    return {length(matrix.u), length(matrix.v), length(matrix.w)};
}

// Applies a new rotation basis while preserving the original basis-axis scales.
inline Matrix ApplyRotationPreservingScale(const Matrix &source_with_scale,
                                           const Matrix &rotation_only) {
    Matrix result = rotation_only;
    const std::array<float, 3> scale = ExtractScale(source_with_scale);
    for (int i = 0; i < 3; ++i) {
        result.u[i] *= scale[0];
        result.v[i] *= scale[1];
        result.w[i] *= scale[2];
    }
    result.o = source_with_scale.o;
    return result;
}

// Parses a 12-float MVR/GDTF matrix string into basis vectors and translation.
inline void ParseMatrix(const std::string &text, Matrix &out) {
    std::string normalized = text;
    for (char &ch : normalized) {
        const unsigned char c = static_cast<unsigned char>(ch);
        if (!(std::isdigit(c) || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E')) {
            ch = ' ';
        }
    }

    std::stringstream ss(normalized);
    std::array<float, 12> values{};
    for (float &value : values) {
        if (!(ss >> value)) {
            out = Matrix{};
            return;
        }
    }
    out.u = {values[0], values[1], values[2]};
    out.v = {values[3], values[4], values[5]};
    out.w = {values[6], values[7], values[8]};
    out.o = {values[9], values[10], values[11]};
}

// Converts a rotation matrix basis into XYZ Euler angles in degrees.
inline std::array<float, 3> MatrixToEuler(const Matrix &m) {
    constexpr float kRadiansToDegrees = 57.29577951308232F;
    const float sy = std::sqrt(m.u[0] * m.u[0] + m.v[0] * m.v[0]);
    const bool singular = sy < 1e-6F;

    float x = 0.0F;
    float y = 0.0F;
    float z = 0.0F;

    if (!singular) {
        x = std::atan2(m.w[1], m.w[2]);
        y = std::atan2(-m.w[0], sy);
        z = std::atan2(m.v[0], m.u[0]);
    } else {
        x = std::atan2(-m.v[2], m.v[1]);
        y = std::atan2(-m.w[0], sy);
        z = 0.0F;
    }

    return {x * kRadiansToDegrees, y * kRadiansToDegrees, z * kRadiansToDegrees};
}

// Builds a rotation matrix basis from XYZ Euler angles in degrees.
inline Matrix EulerToMatrix(const std::array<float, 3> &euler_degrees) {
    constexpr float kDegreesToRadians = 0.017453292519943295F;
    const float x = euler_degrees[0] * kDegreesToRadians;
    const float y = euler_degrees[1] * kDegreesToRadians;
    const float z = euler_degrees[2] * kDegreesToRadians;

    const float cx = std::cos(x);
    const float sx = std::sin(x);
    const float cy = std::cos(y);
    const float sy = std::sin(y);
    const float cz = std::cos(z);
    const float sz = std::sin(z);

    Matrix out;
    out.u = {cy * cz, cy * sz, -sy};
    out.v = {sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy};
    out.w = {cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy};
    out.o = {0.0F, 0.0F, 0.0F};
    return out;
}

// Formats a matrix as a single-line 12-float string for diagnostics.
inline std::string FormatMatrix(const Matrix &m) {
    std::ostringstream os;
    os << std::fixed << std::setprecision(6) << m.u[0] << ' ' << m.u[1] << ' ' << m.u[2] << ' '
       << m.v[0] << ' ' << m.v[1] << ' ' << m.v[2] << ' ' << m.w[0] << ' ' << m.w[1] << ' '
       << m.w[2] << ' ' << m.o[0] << ' ' << m.o[1] << ' ' << m.o[2];
    return os.str();
}

// Returns the canonical identity transform matrix.
inline Matrix Identity() {
    return Matrix{};
}

// Multiplies two affine matrices using basis/translation composition semantics.
inline Matrix Multiply(const Matrix &a, const Matrix &b) {
    Matrix out;

    auto axis_multiply = [](const Matrix &lhs, const std::array<float, 3> &rhs_axis) {
        return std::array<float, 3>{
            lhs.u[0] * rhs_axis[0] + lhs.v[0] * rhs_axis[1] + lhs.w[0] * rhs_axis[2],
            lhs.u[1] * rhs_axis[0] + lhs.v[1] * rhs_axis[1] + lhs.w[1] * rhs_axis[2],
            lhs.u[2] * rhs_axis[0] + lhs.v[2] * rhs_axis[1] + lhs.w[2] * rhs_axis[2]};
    };

    out.u = axis_multiply(a, b.u);
    out.v = axis_multiply(a, b.v);
    out.w = axis_multiply(a, b.w);

    out.o = {
        a.u[0] * b.o[0] + a.v[0] * b.o[1] + a.w[0] * b.o[2] + a.o[0],
        a.u[1] * b.o[0] + a.v[1] * b.o[1] + a.w[1] * b.o[2] + a.o[1],
        a.u[2] * b.o[0] + a.v[2] * b.o[1] + a.w[2] * b.o[2] + a.o[2]};

    return out;
}

} // namespace MatrixUtils
