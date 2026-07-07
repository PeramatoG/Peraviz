#include "gdtf_runtime/compiled_gdtf_fixture.h"

#include <cctype>

namespace peraviz::gdtf_runtime {
namespace {

// Splits a trailing numeric suffix from an official wildcard attribute family.
std::pair<std::string, int32_t> split_family_index(const std::string &name) {
    size_t digit_start = name.size();
    while (digit_start > 0 && std::isdigit(static_cast<unsigned char>(name[digit_start - 1])) != 0) {
        --digit_start;
    }
    if (digit_start == name.size()) {
        return {name, 0};
    }
    return {name.substr(0, digit_start), std::stoi(name.substr(digit_start))};
}

} // namespace

// Produces the canonical serialization-neutral identity used by Peraviz and Perastage test vectors.
AttributeIdentity normalize_attribute_identity(int32_t id, const std::string &attribute_name) {
    AttributeIdentity identity;
    identity.id = id;
    identity.name = attribute_name;
    auto [family, index] = split_family_index(attribute_name);
    identity.canonical_family = family;
    identity.primary_index = index;
    identity.known_official = family == "Dimmer" || family == "Pan" || family == "Tilt" || family == "Gobo" || family == "AnimationWheel" || family == "VideoEffect";
    if (family == "VideoEffect" && index > 0) {
        identity.canonical_family = "VideoEffectParameter";
        identity.secondary_index = index;
    }
    return identity;
}

// Builds a small fixture model that proves repeated GDTF wheel families remain independent.
CompiledGdtfFixtureType make_two_gobo_wheel_regression_fixture() {
    CompiledGdtfFixtureType fixture;
    fixture.fixture_type_name = "Peraviz Two Gobo Wheel Regression";
    fixture.dmx_mode_name = "Mode 1";
    fixture.attributes.push_back(normalize_attribute_identity(1, "Dimmer"));
    fixture.attributes.push_back(normalize_attribute_identity(2, "Gobo1"));
    fixture.attributes.push_back(normalize_attribute_identity(3, "Gobo2"));
    fixture.geometries.push_back({1, 0, "Base", "Geometry"});
    fixture.geometries.push_back({2, 1, "Head", "Beam"});
    fixture.components.push_back({1, 2, 1, 0, 1});
    fixture.components.push_back({2, 2, 2, 1, 2});
    fixture.components.push_back({3, 2, 3, 2, 3});
    fixture.channel_programs.push_back({1, 0, 8, 1, 2, 1, 0, 255, 0.0, 1.0});
    fixture.channel_programs.push_back({2, 1, 8, 2, 2, 2, 0, 127, 0.0, 6.0});
    fixture.channel_programs.push_back({3, 2, 8, 3, 2, 3, 128, 255, 0.0, 6.0});
    fixture.diagnostics.push_back({"PVZ-GDTF-UNKNOWN-PRESERVED", "info", "Unknown and custom attributes are retained in the semantic model before runtime compilation.", "AttributeDefinitions"});
    return fixture;
}

} // namespace peraviz::gdtf_runtime
