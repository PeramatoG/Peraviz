#include "archive/zip_archive.h"
#include "gdtf_runtime/runtime_scene_compiler.h"
#include "runtime/gobo_motion_evaluator.h"

#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

// Reports a gobo motion integration test failure.
int fail(const char *message) {
    std::cerr << message << std::endl;
    return 1;
}

// Derives the repository root path relative to this source file.
std::filesystem::path repo_root_from_source() {
    return std::filesystem::weakly_canonical(std::filesystem::path(__FILE__)).parent_path().parent_path().parent_path();
}

// Creates a minimal GDTF archive with the provided XML.
bool write_gdtf_archive(const std::filesystem::path &path, const std::string &description_xml) {
    peraviz::archive::ZipArchive archive;
    return archive.open_create_or_modify(path) && archive.write_file("description.xml", description_xml) && archive.close();
}

} // namespace

// Verifies exact gobo motion and structured ModeMaster data reach the production setup contract.
bool test_gobo_motion_setup_contract() {
    const std::filesystem::path path = repo_root_from_source() / "native/build/gobo_motion_setup_contract.gdtf";
    std::filesystem::create_directories(path.parent_path());
    const std::string xml = R"XML(<GDTF><FixtureType Name="MotionContract">
<AttributeDefinitions><Attributes>
 <Attribute Name="Gobo1" PhysicalUnit="None"/><Attribute Name="Gobo1Pos" PhysicalUnit="Angle"/>
 <Attribute Name="Gobo1PosRotate" MainAttribute="Gobo1Pos" PhysicalUnit="AngularSpeed"/>
 <Attribute Name="Gobo1PosShake" PhysicalUnit="Frequency"><SubPhysicalUnit Type="Amplitude"/></Attribute>
 <Attribute Name="Gobo1SelectSpin" PhysicalUnit="AngularSpeed"><SubPhysicalUnit Type="PlacementOffset" PhysicalUnit="Angle" PhysicalFrom="-180" PhysicalTo="180"/></Attribute>
 <Attribute Name="Gobo1SelectShake" PhysicalUnit="Frequency"><SubPhysicalUnit Type="PlacementOffset"/><SubPhysicalUnit Type="Amplitude"/></Attribute>
 <Attribute Name="Gobo1SelectEffects" PhysicalUnit="None"/>
 <Attribute Name="Gobo1WheelSpin" PhysicalUnit="AngularSpeed"><SubPhysicalUnit Type="PlacementOffset" PhysicalUnit="Angle"/></Attribute>
 <Attribute Name="Gobo1WheelIndex" PhysicalUnit="Angle"><SubPhysicalUnit Type="PlacementOffset" PhysicalUnit="Angle"/></Attribute>
 <Attribute Name="Gobo1WheelShake" PhysicalUnit="Frequency"><SubPhysicalUnit Type="PlacementOffset"/><SubPhysicalUnit Type="Amplitude" PhysicalUnit="Angle"/></Attribute>
 <Attribute Name="Gobo2" PhysicalUnit="None"/><Attribute Name="Gobo2Pos" PhysicalUnit="Angle"/>
</Attributes></AttributeDefinitions>
<Wheels><Wheel Name="Gobos"><Slot Name="Open"/><Slot Name="Pattern"/></Wheel><Wheel Name="Gobos2"><Slot Name="Open"/><Slot Name="Pattern2"/></Wheel></Wheels>
<Geometries><Geometry Name="Root"><Beam Name="Beam" BeamType="Spot"/></Geometry></Geometries>
<DMXModes><DMXMode Name="Mode 1" Geometry="Root"><DMXChannels>
 <DMXChannel Offset="1" Geometry="Beam"><LogicalChannel Attribute="Gobo1"><ChannelFunction Name="Select" Attribute="Gobo1" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1"><ChannelSet Name="Open" DMXFrom="0/1" WheelSlotIndex="1"/><ChannelSet Name="Pattern" DMXFrom="128/1" WheelSlotIndex="2"/></ChannelFunction></LogicalChannel></DMXChannel>
 <DMXChannel Offset="2" Geometry="Beam"><LogicalChannel Attribute="Gobo1Pos">
  <ChannelFunction Name="IndexFn" Attribute="Gobo1Pos" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="-180" PhysicalTo="180" ModeMaster="Beam_Gobo1"/>
  <ChannelFunction Name="RotateFn" Attribute="Gobo1PosRotate" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="-2" PhysicalTo="2" ModeMaster="Beam_Gobo1" ModeFrom="80/1" ModeTo="159/1"/>
  <ChannelFunction Name="ShakeFn" Attribute="Gobo1PosShake" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="0" PhysicalTo="20" ModeMaster="Beam_Gobo1" ModeFrom="160/1" ModeTo="255/1"/>
 </LogicalChannel></DMXChannel>
 <DMXChannel Offset="3" Geometry="Beam"><LogicalChannel Attribute="Gobo1SelectSpin"><ChannelFunction Name="SpinSelect" Attribute="Gobo1SelectSpin" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="-2" PhysicalTo="2"/></LogicalChannel></DMXChannel>
 <DMXChannel Offset="4" Geometry="Beam"><LogicalChannel Attribute="Gobo1SelectShake"><ChannelFunction Name="ShakeSelect" Attribute="Gobo1SelectShake" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="0" PhysicalTo="20"/></LogicalChannel></DMXChannel>
 <DMXChannel Offset="5" Geometry="Beam"><LogicalChannel Attribute="Gobo1SelectEffects"><ChannelFunction Name="EffectsSelect" Attribute="Gobo1SelectEffects" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1"/></LogicalChannel></DMXChannel>
 <DMXChannel Offset="6" Geometry="Beam"><LogicalChannel Attribute="Gobo1WheelSpin"><ChannelFunction Name="WheelSpinFn" Attribute="Gobo1WheelSpin" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="-1" PhysicalTo="1" ModeMaster="Beam_Gobo1Pos.Gobo1Pos.RotateFn" ModeFrom="0/1" ModeTo="255/1"/></LogicalChannel></DMXChannel>
 <DMXChannel Offset="7" Geometry="Beam"><LogicalChannel Attribute="Gobo1WheelIndex"><ChannelFunction Name="WheelIndexFn" Attribute="Gobo1WheelIndex" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="-180" PhysicalTo="180"/></LogicalChannel></DMXChannel>
 <DMXChannel Offset="8" Geometry="Beam"><LogicalChannel Attribute="Gobo1WheelShake"><ChannelFunction Name="WheelShakeFn" Attribute="Gobo1WheelShake" Wheel="Gobos" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="0" PhysicalTo="20"/></LogicalChannel></DMXChannel>
 <DMXChannel Offset="9,10" Geometry="Beam"><LogicalChannel Attribute="Gobo2"><ChannelFunction Name="Select2" Attribute="Gobo2" Wheel="Gobos2" DMXFrom="0/1" DMXTo="255/1"><ChannelSet Name="Open2" DMXFrom="0/1" WheelSlotIndex="1"/><ChannelSet Name="Pattern2" DMXFrom="128/1" WheelSlotIndex="2"/></ChannelFunction></LogicalChannel></DMXChannel>
 <DMXChannel Offset="11" Geometry="Beam"><LogicalChannel Attribute="Gobo2Pos"><ChannelFunction Name="Index2" Attribute="Gobo2Pos" Wheel="Gobos2" DMXFrom="0/1" DMXTo="255/1" PhysicalFrom="-90" PhysicalTo="90" ModeMaster="Beam_Gobo2" ModeFrom="255/1s" ModeTo="255/1"/></LogicalChannel></DMXChannel>
</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>)XML";
    if (!write_gdtf_archive(path, xml)) return fail("Expected gobo motion contract fixture archive") == 0;
    peraviz::SceneModel model;
    model.fixture_patches.push_back({"motion-fixture", 1, 1, "Mode 1", path.string()});
    peraviz::SceneNode beam;
    beam.node_id = "motion-fixture/Root/Beam";
    beam.gdtf_geometry_path = "Root/Beam";
    beam.gdtf_geometry_key = beam.node_id;
    beam.is_fixture = true;
    beam.is_beam = true;
    model.nodes.push_back(beam);
    const auto scene = peraviz::gdtf_runtime::compile_runtime_scene(model, 0);
    if (scene.contract_version != 5 || scene.gobo_bindings.size() != 2) return fail("Expected only exact Gobo1 and Gobo2 to compile as static selection") == 0;
    if (scene.gobo_motion_bindings.size() != 10) return fail("Expected ten exact non-static gobo motion bindings") == 0;
    const peraviz::runtime::CompiledGoboMotionBinding *rotate = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *shake = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *effects = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *index = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *wheel_spin = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *wheel_shake = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *select_spin = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *select_shake = nullptr;
    const peraviz::runtime::CompiledGoboMotionBinding *gobo2_index = nullptr;
    for (const auto &binding : scene.gobo_motion_bindings) {
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::PosRotate) rotate = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::PosShake) shake = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::SelectEffects) effects = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::Pos && binding.wheel_instance_index == 1) index = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::WheelSpin) wheel_spin = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::WheelShake) wheel_shake = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::SelectSpin) select_spin = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::SelectShake) select_shake = &binding;
        if (binding.semantic_kind == peraviz::gdtf_runtime::GoboSemanticKind::Pos && binding.wheel_instance_index == 2) gobo2_index = &binding;
    }
    if (!rotate || rotate->physical_unit != "AngularSpeed" || rotate->mode_master.target_kind != peraviz::gdtf_runtime::ModeMasterTargetKind::DmxChannel) return fail("Expected compiled rotate metadata and exact channel ModeMaster") == 0;
    if (!shake || !shake->amplitude.present || shake->amplitude.physical_unit != "None" || shake->amplitude.physical_to != 1.0) return fail("Expected defaulted Amplitude SubPhysicalUnit metadata") == 0;
    if (!effects || effects->scalar_evaluable || effects->rendered) return fail("Expected SelectEffects to remain preserved-only and unrendered") == 0;
    if (!index || index->mode_master.from != 0 || index->mode_master.to != 0) return fail("Expected omitted ModeFrom and ModeTo to default to 0/1") == 0;
    if (!wheel_spin || wheel_spin->controlled_scope != peraviz::gdtf_runtime::GoboControlledScope::CompleteWheel || !wheel_spin->placement_offset.present || wheel_spin->mode_master.target_kind != peraviz::gdtf_runtime::ModeMasterTargetKind::ChannelFunction) return fail("Expected exact ChannelFunction cascade and whole-wheel metadata") == 0;
    if (!wheel_shake || wheel_shake->physical_unit != "Frequency" || !wheel_shake->placement_offset.present || !wheel_shake->amplitude.present) return fail("Expected whole-wheel shake physical metadata") == 0;
    if (!select_spin || select_spin->physical_unit != "AngularSpeed" || !select_spin->placement_offset.present || select_spin->controlled_scope != peraviz::gdtf_runtime::GoboControlledScope::SelectionAndSelectedGobo) return fail("Expected SelectSpin combined-scope metadata") == 0;
    if (!select_shake || select_shake->physical_unit != "Frequency" || !select_shake->placement_offset.present || !select_shake->amplitude.present) return fail("Expected SelectShake combined-scope metadata") == 0;
    if (!gobo2_index || gobo2_index->wheel_id == index->wheel_id || gobo2_index->mode_master.master_channel_id == index->mode_master.master_channel_id || gobo2_index->mode_master.from != 65280 || gobo2_index->mode_master.to != 65535) return fail("Expected independent Gobo2 wheel identity and compiled mirror/shift bounds") == 0;
    std::vector<peraviz::runtime::GoboSourceValue> values;
    for (const auto &program : scene.source_programs) values.push_back({program.program_id, program.program_id == rotate->source_program_id ? 128U : 100U});
    const auto evaluated = peraviz::runtime::evaluate_gobo_motion_scalar(*rotate, scene.source_programs, values);
    if (!evaluated.active || evaluated.semantic_kind != peraviz::gdtf_runtime::GoboSemanticKind::PosRotate || evaluated.physical_unit != "AngularSpeed") return fail("Expected instantaneous rotate scalar evaluation") == 0;
    const auto cascaded = peraviz::runtime::evaluate_gobo_motion_scalar(*wheel_spin, scene.source_programs, values);
    if (!cascaded.active || cascaded.semantic_kind != peraviz::gdtf_runtime::GoboSemanticKind::WheelSpin) return fail("Expected parsed ChannelFunction ModeMaster cascade to activate") == 0;
    return true;
}
