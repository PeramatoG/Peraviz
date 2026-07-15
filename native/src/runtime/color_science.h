#pragma once

#include <string>
#include <vector>

namespace peraviz::runtime {

struct LinearRgb {
    double r = 0.0;
    double g = 0.0;
    double b = 0.0;
};

struct CieXyz {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
    bool valid = false;
};

struct CieXyY {
    double x = 0.0;
    double y = 0.0;
    double Y = 0.0;
    bool valid = false;
};

struct SpectralSample {
    double wavelength_nm = 0.0;
    double energy = 0.0;
};

CieXyY parse_cie_xyy(const std::string &value, bool percentage_y);
CieXyz cie_xyy_to_xyz(const CieXyY &xyy);
LinearRgb xyz_to_linear_srgb(const CieXyz &xyz);
double srgb_encode(double value);
CieXyz dominant_wavelength_to_xyz(double wavelength_nm);
CieXyz spectrum_to_xyz(const std::vector<SpectralSample> &samples);
LinearRgb cct_to_linear_srgb(double kelvin);
LinearRgb normalize_color_gain(const LinearRgb &rgb, double &gain);

} // namespace peraviz::runtime
