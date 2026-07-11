#include "dmx/gdtf_color_cie.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <sstream>

namespace peraviz::dmx {
namespace {

// Applies the sRGB electro-optical transfer function to a linear component.
double encode_srgb_component(double value) {
    if (value <= 0.0031308) {
        return 12.92 * value;
    }
    return 1.055 * std::pow(value, 1.0 / 2.4) - 0.055;
}

// Clips a color component into the displayable preview range.
double clip_component(double value, bool &clipped) {
    if (value < 0.0 || value > 1.0) {
        clipped = true;
    }
    return std::clamp(value, 0.0, 1.0);
}

} // namespace

// Parses a GDTF CIE xyY color while preserving the exact source text.
GdtfColorCie parse_gdtf_color_cie(const std::string &raw_source_text, const std::string &value_origin) {
    GdtfColorCie color;
    color.raw_source_text = raw_source_text;
    color.value_origin = value_origin;

    std::string normalized = raw_source_text;
    std::replace(normalized.begin(), normalized.end(), ',', ' ');
    std::istringstream input(normalized);
    if (!(input >> color.x >> color.y >> color.luminance_y)) {
        color.diagnostics.push_back({"malformed_color", "Color must contain x, y, and Y numeric values."});
        return color;
    }
    if (!std::isfinite(color.x) || !std::isfinite(color.y) || !std::isfinite(color.luminance_y)) {
        color.diagnostics.push_back({"non_finite_color", "Color contains a non-finite CIE component."});
        return color;
    }
    if (color.y <= 0.0) {
        color.diagnostics.push_back({"invalid_y", "CIE y must be greater than zero."});
        return color;
    }
    color.valid = true;
    return color;
}

// Converts a valid CIE xyY value to an approximate clipped display sRGB preview.
GdtfSrgbPreview convert_cie_xyy_to_srgb_preview(const GdtfColorCie &color) {
    GdtfSrgbPreview preview;
    if (!color.valid) {
        preview.diagnostics.push_back({"invalid_color", "Cannot convert an invalid CIE color."});
        return preview;
    }

    const double x_xyz = color.x * color.luminance_y / color.y;
    const double y_xyz = color.luminance_y;
    const double z_xyz = (1.0 - color.x - color.y) * color.luminance_y / color.y;

    double red_linear = 3.2406 * x_xyz - 1.5372 * y_xyz - 0.4986 * z_xyz;
    double green_linear = -0.9689 * x_xyz + 1.8758 * y_xyz + 0.0415 * z_xyz;
    double blue_linear = 0.0557 * x_xyz - 0.2040 * y_xyz + 1.0570 * z_xyz;

    red_linear = clip_component(red_linear, preview.clipped);
    green_linear = clip_component(green_linear, preview.clipped);
    blue_linear = clip_component(blue_linear, preview.clipped);

    preview.red = clip_component(encode_srgb_component(red_linear), preview.clipped);
    preview.green = clip_component(encode_srgb_component(green_linear), preview.clipped);
    preview.blue = clip_component(encode_srgb_component(blue_linear), preview.clipped);
    if (preview.clipped) {
        preview.diagnostics.push_back({"srgb_clipped", "CIE color was clipped to the display sRGB gamut."});
    }
    return preview;
}

} // namespace peraviz::dmx
