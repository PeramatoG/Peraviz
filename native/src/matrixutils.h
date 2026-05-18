#pragma once

// Provides Peraviz-local helper functions for parsing and composing 4x3 transformation matrices.

#include "types.h"

#include <array>
#include <cmath>
#include <sstream>
#include <string>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace MatrixUtils {

// Computes per-axis scale magnitudes from the matrix basis vectors.
inline std::array<float, 3> ExtractScale(const Matrix &m) {
    auto norm = [](const std::array<float, 3> &v) {
        return std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    };
    return {norm(m.u), norm(m.v), norm(m.w)};
}

// Reapplies source scale to a rotation matrix while overriding translation.
inline Matrix ApplyRotationPreservingScale(const Matrix &source,
                                           const Matrix &rotation,
                                           const std::array<float, 3> &translation) {
    Matrix out = rotation;
    const auto scales = ExtractScale(source);

    for (int i = 0; i < 3; ++i) {
        out.u[i] *= scales[0];
        out.v[i] *= scales[1];
        out.w[i] *= scales[2];
    }
    out.o = translation;
    return out;
}

// Parses MVR 4x3 or GDTF 4x4 matrix text and stores the result in Matrix layout.
inline bool ParseMatrix(const std::string &text, Matrix &outMatrix) {
    std::string cleaned;
    cleaned.reserve(text.size());
    for (char c : text) {
        if (c == '{' || c == '}' || c == ',') {
            cleaned.push_back(' ');
        } else {
            cleaned.push_back(c);
        }
    }

    std::stringstream ss(cleaned);
    std::vector<float> values;
    float v;
    while (ss >> v) {
        values.push_back(v);
    }

    if (values.size() == 16) {
        outMatrix.u = std::array<float, 3>{values[0], values[4], values[8]};
        outMatrix.v = std::array<float, 3>{values[1], values[5], values[9]};
        outMatrix.w = std::array<float, 3>{values[2], values[6], values[10]};
        outMatrix.o = std::array<float, 3>{values[3], values[7], values[11]};
        return true;
    }
    if (values.size() == 12) {
        outMatrix.u = std::array<float, 3>{values[0], values[1], values[2]};
        outMatrix.v = std::array<float, 3>{values[3], values[4], values[5]};
        outMatrix.w = std::array<float, 3>{values[6], values[7], values[8]};
        outMatrix.o = std::array<float, 3>{values[9], values[10], values[11]};
        return true;
    }

    return false;
}

// Converts matrix rotation axes into Euler yaw/pitch/roll angles in degrees.
inline std::array<float, 3> MatrixToEuler(const Matrix &m) {
    float r00 = m.u[0];
    float r01 = m.u[1];
    float r10 = m.v[0];
    float r11 = m.v[1];
    float r20 = m.w[0];
    float r21 = m.w[1];
    float r22 = m.w[2];

    float pitch = std::atan2(-r20, std::sqrt(r00 * r00 + r10 * r10));
    float yaw;
    float roll;
    if (std::abs(std::cos(pitch)) > 1e-6f) {
        yaw = std::atan2(r10, r00);
        roll = std::atan2(r21, r22);
    } else {
        yaw = 0.0f;
        roll = std::atan2(-r01, r11);
    }

    const float toDeg = 180.0f / static_cast<float>(M_PI);
    return {yaw * toDeg, pitch * toDeg, roll * toDeg};
}

// Builds a rotation matrix from Euler yaw/pitch/roll angles in degrees.
inline Matrix EulerToMatrix(float yawDeg, float pitchDeg, float rollDeg) {
    const float toRad = static_cast<float>(M_PI) / 180.0f;
    float yaw = yawDeg * toRad;
    float pitch = pitchDeg * toRad;
    float roll = rollDeg * toRad;

    float cy = std::cos(yaw);
    float sy = std::sin(yaw);
    float cp = std::cos(pitch);
    float sp = std::sin(pitch);
    float cr = std::cos(roll);
    float sr = std::sin(roll);

    Matrix m;
    m.u = std::array<float, 3>{cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr};
    m.v = std::array<float, 3>{sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr};
    m.w = std::array<float, 3>{-sp, cp * sr, cp * cr};
    return m;
}

// Formats a matrix to the canonical MVR-style 4x3 braced string form.
inline std::string FormatMatrix(const Matrix &m) {
    std::ostringstream ss;
    ss << "{" << m.u[0] << "," << m.u[1] << "," << m.u[2] << "}"
       << "{" << m.v[0] << "," << m.v[1] << "," << m.v[2] << "}"
       << "{" << m.w[0] << "," << m.w[1] << "," << m.w[2] << "}"
       << "{" << m.o[0] << "," << m.o[1] << "," << m.o[2] << "}";
    return ss.str();
}

// Returns an identity matrix with unit basis and zero translation.
inline Matrix Identity() {
    return Matrix{};
}

// Multiplies two affine transform matrices preserving basis and translation composition.
inline Matrix Multiply(const Matrix &a, const Matrix &b) {
    Matrix r;
    for (int i = 0; i < 3; ++i) {
        r.u[i] = a.u[i] * b.u[0] + a.v[i] * b.u[1] + a.w[i] * b.u[2];
        r.v[i] = a.u[i] * b.v[0] + a.v[i] * b.v[1] + a.w[i] * b.v[2];
        r.w[i] = a.u[i] * b.w[0] + a.v[i] * b.w[1] + a.w[i] * b.w[2];
        r.o[i] = a.u[i] * b.o[0] + a.v[i] * b.o[1] + a.w[i] * b.o[2] + a.o[i];
    }
    return r;
}

} // namespace MatrixUtils
