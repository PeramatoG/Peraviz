#pragma once
#include "gdtf_runtime/compiled_gdtf_fixture.h"
#include "runtime/visual_runtime_types.h"
#include "runtime/color_science.h"
#include <algorithm>

namespace peraviz::gdtf_runtime {
using PhysicalResourceTemplates = std::pair<std::vector<runtime::CompiledEmitterResource>, std::vector<runtime::CompiledFilterResource>>;
// Integrates immutable spectra and fallback colors once per selected definition;
// resource IDs remain definition-local until the scene compiler binds each fixture UUID.
inline PhysicalResourceTemplates compile_physical_resource_templates(const CompiledGdtfFixtureType &fixture_type) {
    PhysicalResourceTemplates resources;
    for (const PhysicalEmitterResource &emitter : fixture_type.emitters) {
        runtime::CompiledEmitterResource compiled;
        compiled.resource_id = emitter.id;
        compiled.name = emitter.name;
        compiled.color = {emitter.color.x, emitter.color.y, emitter.color.Y, emitter.color.valid};
        compiled.dominant_wavelength_nm = emitter.dominant_wavelength_nm;
        compiled.has_dominant_wavelength = emitter.has_dominant_wavelength;
        for (const PhysicalColorMeasurement &measurement : emitter.measurements) {
            runtime::CompiledColorMeasurement cm;
            cm.physical_percent = measurement.physical_percent;
            cm.luminous_intensity = measurement.luminous_intensity;
            cm.transmission = measurement.transmission;
            cm.interpolation_to = measurement.interpolation_to;
            for (const PhysicalSpectralPoint &point : measurement.spectral_points) cm.spectral_points.push_back({point.wavelength_nm, point.energy});
            std::vector<runtime::SpectralSample> samples;
            for (const runtime::CompiledSpectralPoint &point : cm.spectral_points) samples.push_back({point.wavelength_nm, point.energy});
            const runtime::CieXyz xyz = runtime::spectrum_to_xyz(samples);
            cm.has_spectrum_xyz = xyz.valid;
            cm.xyz_x = xyz.x; cm.xyz_y = xyz.y; cm.xyz_z = xyz.z;
            compiled.measurements.push_back(cm);
        }
        const runtime::CieXyz xyz = compiled.color.valid ? runtime::cie_xyy_to_xyz({compiled.color.x, compiled.color.y, compiled.color.Y, true}) : runtime::dominant_wavelength_to_xyz(compiled.dominant_wavelength_nm);
        const runtime::LinearRgb rgb = runtime::xyz_to_linear_srgb(xyz);
        compiled.fallback_linear_r = rgb.r; compiled.fallback_linear_g = rgb.g; compiled.fallback_linear_b = rgb.b;
        compiled.valid = xyz.valid || !compiled.measurements.empty();
        resources.first.push_back(std::move(compiled));
    }
    for (const PhysicalFilterResource &filter : fixture_type.filters) {
        runtime::CompiledFilterResource compiled;
        compiled.resource_id = filter.id;
        compiled.name = filter.name;
        compiled.color = {filter.color.x, filter.color.y, filter.color.Y, filter.color.valid};
        for (const PhysicalColorMeasurement &measurement : filter.measurements) {
            runtime::CompiledColorMeasurement cm;
            cm.physical_percent = measurement.physical_percent;
            cm.luminous_intensity = measurement.luminous_intensity;
            cm.transmission = measurement.transmission;
            cm.interpolation_to = measurement.interpolation_to;
            for (const PhysicalSpectralPoint &point : measurement.spectral_points) cm.spectral_points.push_back({point.wavelength_nm, point.energy});
            std::vector<runtime::SpectralSample> samples;
            for (const runtime::CompiledSpectralPoint &point : cm.spectral_points) samples.push_back({point.wavelength_nm, point.energy});
            const runtime::CieXyz xyz = runtime::spectrum_to_xyz(samples);
            cm.has_spectrum_xyz = xyz.valid;
            cm.xyz_x = xyz.x; cm.xyz_y = xyz.y; cm.xyz_z = xyz.z;
            compiled.measurements.push_back(cm);
        }
        const runtime::CieXyz xyz = runtime::cie_xyy_to_xyz({compiled.color.x, compiled.color.y, compiled.color.Y, compiled.color.valid});
        const runtime::LinearRgb rgb = runtime::xyz_to_linear_srgb(xyz);
        compiled.fallback_linear_r = rgb.r; compiled.fallback_linear_g = rgb.g; compiled.fallback_linear_b = rgb.b;
        compiled.fallback_transmission = compiled.color.valid ? std::clamp(compiled.color.Y, 0.0, 1.0) : 1.0;
        compiled.valid = xyz.valid || !compiled.measurements.empty();
        resources.second.push_back(std::move(compiled));
    }
    return resources;
}
}
