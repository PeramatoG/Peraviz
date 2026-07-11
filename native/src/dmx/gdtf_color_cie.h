#pragma once

#include <string>
#include <vector>

namespace peraviz::dmx {

struct GdtfDiagnostic {
    std::string code;
    std::string message;
};

struct GdtfSrgbPreview {
    double red = 0.0;
    double green = 0.0;
    double blue = 0.0;
    bool clipped = false;
    std::vector<GdtfDiagnostic> diagnostics;
};

struct GdtfColorCie {
    std::string raw_source_text;
    double x = 0.0;
    double y = 0.0;
    double luminance_y = 0.0;
    bool valid = false;
    std::string value_origin;
    std::vector<GdtfDiagnostic> diagnostics;
};

GdtfColorCie parse_gdtf_color_cie(const std::string &raw_source_text, const std::string &value_origin);
GdtfSrgbPreview convert_cie_xyy_to_srgb_preview(const GdtfColorCie &color);

} // namespace peraviz::dmx
