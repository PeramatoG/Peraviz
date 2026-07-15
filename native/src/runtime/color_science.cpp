#include "runtime/color_science.h"

#include "dmx/gdtf_attribute_classifier.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <sstream>

namespace peraviz::runtime {
namespace {

constexpr double kEpsilon = 0.000001;

// Approximates the CIE 1931 2-degree observer with deterministic Gaussian fits.
CieXyz observer_xyz(double wavelength_nm) {
    if (wavelength_nm < 380.0 || wavelength_nm > 780.0) return {};
    const double t1 = (wavelength_nm - 442.0) * (wavelength_nm < 442.0 ? 0.0624 : 0.0374);
    const double t2 = (wavelength_nm - 599.8) * (wavelength_nm < 599.8 ? 0.0264 : 0.0323);
    const double t3 = (wavelength_nm - 501.1) * (wavelength_nm < 501.1 ? 0.0490 : 0.0382);
    const double x = 0.362 * std::exp(-0.5 * t1 * t1) + 1.056 * std::exp(-0.5 * t2 * t2) - 0.065 * std::exp(-0.5 * t3 * t3);
    const double y1 = (wavelength_nm - 568.8) * (wavelength_nm < 568.8 ? 0.0213 : 0.0247);
    const double y2 = (wavelength_nm - 530.9) * (wavelength_nm < 530.9 ? 0.0613 : 0.0322);
    const double y = 0.821 * std::exp(-0.5 * y1 * y1) + 0.286 * std::exp(-0.5 * y2 * y2);
    const double z1 = (wavelength_nm - 437.0) * (wavelength_nm < 437.0 ? 0.0845 : 0.0278);
    const double z2 = (wavelength_nm - 459.0) * (wavelength_nm < 459.0 ? 0.0385 : 0.0725);
    const double z = 1.217 * std::exp(-0.5 * z1 * z1) + 0.681 * std::exp(-0.5 * z2 * z2);
    return {x, y, z, std::isfinite(x) && std::isfinite(y) && std::isfinite(z)};
}

// Parses a comma/space separated list of floating point values.
std::vector<double> parse_number_list(std::string value) {
    for (char &ch : value) if (ch == ',' || ch == ';') ch = ' ';
    std::istringstream stream(value);
    std::vector<double> values;
    double parsed = 0.0;
    while (stream >> parsed) values.push_back(parsed);
    return values;
}

} // namespace

// Parses a GDTF ColorCIE value and applies percentage-style Y normalization only for physical resources.
CieXyY parse_cie_xyy(const std::string &value, bool percentage_y) {
    const std::vector<double> values = parse_number_list(value);
    if (values.size() < 3) return {};
    CieXyY out{values[0], values[1], values[2], true};
    if (percentage_y && out.Y > 1.0) out.Y *= 0.01;
    out.valid = std::isfinite(out.x) && std::isfinite(out.y) && std::isfinite(out.Y) && out.x >= 0.0 && out.y > kEpsilon && out.Y >= 0.0;
    return out;
}

// Converts CIE 1931 xyY into XYZ while rejecting unsafe values.
CieXyz cie_xyy_to_xyz(const CieXyY &xyy) {
    if (!xyy.valid || xyy.y <= kEpsilon || !std::isfinite(xyy.x) || !std::isfinite(xyy.y) || !std::isfinite(xyy.Y) || xyy.Y < 0.0) return {};
    return {xyy.x * xyy.Y / xyy.y, xyy.Y, (1.0 - xyy.x - xyy.y) * xyy.Y / xyy.y, true};
}

// Converts XYZ into the renderer's linear sRGB/D65 working space.
LinearRgb xyz_to_linear_srgb(const CieXyz &xyz) {
    if (!xyz.valid) return {};
    return {3.2404542 * xyz.x - 1.5371385 * xyz.y - 0.4985314 * xyz.z,
            -0.9692660 * xyz.x + 1.8760108 * xyz.y + 0.0415560 * xyz.z,
            0.0556434 * xyz.x - 0.2040259 * xyz.y + 1.0572252 * xyz.z};
}

// Encodes one linear component as nonlinear sRGB at the renderer boundary.
double srgb_encode(double value) {
    const double clamped = std::clamp(value, 0.0, 1.0);
    if (clamped <= 0.0031308) return clamped * 12.92;
    return 1.055 * std::pow(clamped, 1.0 / 2.4) - 0.055;
}

// Converts a visible dominant wavelength into an approximate XYZ sample.
CieXyz dominant_wavelength_to_xyz(double wavelength_nm) {
    return observer_xyz(wavelength_nm);
}

// Integrates a prevalidated spectrum into XYZ using trapezoidal wavelength spacing.
CieXyz spectrum_to_xyz(const std::vector<SpectralSample> &samples) {
    if (samples.size() < 2) return {};
    double x = 0.0, y = 0.0, z = 0.0;
    double previous_wavelength = samples.front().wavelength_nm;
    if (!std::isfinite(previous_wavelength)) return {};
    for (size_t index = 0; index < samples.size(); ++index) {
        const SpectralSample &sample = samples[index];
        if (!std::isfinite(sample.wavelength_nm) || !std::isfinite(sample.energy) || sample.energy < 0.0 || (index > 0 && sample.wavelength_nm <= previous_wavelength)) return {};
        const CieXyz obs = observer_xyz(sample.wavelength_nm);
        const double width = index == 0 ? std::max(1.0, samples[1].wavelength_nm - sample.wavelength_nm) : sample.wavelength_nm - previous_wavelength;
        x += obs.x * sample.energy * width;
        y += obs.y * sample.energy * width;
        z += obs.z * sample.energy * width;
        previous_wavelength = sample.wavelength_nm;
    }
    const bool valid = std::isfinite(x) && std::isfinite(y) && std::isfinite(z) && y > kEpsilon;
    return {x, y, z, valid};
}

// Approximates a Planckian white point for CCT correction in linear sRGB.
LinearRgb cct_to_linear_srgb(double kelvin) {
    const double t = kelvin / 100.0;
    double r = t <= 66.0 ? 1.0 : std::clamp(1.292936186 * std::pow(t - 60.0, -0.1332047592), 0.0, 1.0);
    double g = t <= 66.0 ? std::clamp(0.3900815788 * std::log(t) - 0.6318414438, 0.0, 1.0) : std::clamp(1.129890861 * std::pow(t - 60.0, -0.0755148492), 0.0, 1.0);
    double b = t >= 66.0 ? 1.0 : (t <= 19.0 ? 0.0 : std::clamp(0.5432067891 * std::log(t - 10.0) - 1.1962540891, 0.0, 1.0));
    return {r, g, b};
}

// Splits linear color into normalized chromaticity and scalar gain without folding gain into sRGB.
LinearRgb normalize_color_gain(const LinearRgb &rgb, double &gain) {
    gain = std::max({rgb.r, rgb.g, rgb.b, 0.0});
    if (gain <= kEpsilon) {
        gain = 0.0;
        return {};
    }
    return {rgb.r / gain, rgb.g / gain, rgb.b / gain};
}

} // namespace peraviz::runtime
