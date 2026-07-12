extends SceneTree

const SectionedVisualFrameApplierScript = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")
const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const DmxFixtureRuntimeScript = preload("res://scripts/dmx_fixture_runtime.gd")

class FakeLoader:
	extends Node
	var pan_node := Node3D.new()
	var tilt_node := Node3D.new()
	var dimmer_node := Node3D.new()
	var dimmer_valid: bool = true
	var dimmer_has_resources: bool = true
	var last_dimmer_light: SpotLight3D = null
	var beam_valid: bool = true
	var beam_light := SpotLight3D.new()
	var beam_mesh := MeshInstance3D.new()

	func _apply_native_transform_targets(pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> Dictionary:
		var result: Dictionary = {"pan_requested": pan_component_id > 0, "pan_applied": false, "tilt_requested": tilt_component_id > 0, "tilt_applied": false, "failed": 0}
		if pan_component_id == 101:
			pan_node.rotation_degrees.y = pan_degrees
			result["pan_applied"] = true
		elif pan_component_id > 0:
			result["failed"] = int(result["failed"]) + 1
		if tilt_component_id == 102:
			tilt_node.rotation_degrees.x = tilt_degrees
			result["tilt_applied"] = true
		elif tilt_component_id > 0:
			result["failed"] = int(result["failed"]) + 1
		return result

	func _has_native_dimmer_target(dimmer_target_id: int) -> bool:
		return dimmer_valid and dimmer_target_id == 201

	func _has_native_beam_intensity_target(beam_target_id: int) -> bool:
		return beam_valid and beam_target_id == 301

	func _get_native_beam_intensity_target_record(beam_target_id: int) -> Dictionary:
		if not beam_valid or beam_target_id != 301:
			return {}
		return {"emitter_anchors": [beam_light], "beam_instances": [beam_mesh], "lens_material_targets": [], "beam_optical_profile": {"luminous_flux": 320.0, "beam_angle": 25.0}}

	func _get_beam_resource_for_light(light: SpotLight3D) -> MeshInstance3D:
		return beam_mesh if light == beam_light else null

	func _apply_emitter_light_state(light: SpotLight3D, _photometric: Dictionary, normalized_dimmer: float, controls: Dictionary = {}) -> void:
		var values: PackedFloat32Array = controls.get("render_ready_values", PackedFloat32Array())
		var intensity: float = values[7] if values.size() >= 8 else normalized_dimmer * 20.0
		light.light_energy = values[0] if values.size() >= 1 else normalized_dimmer
		light.set_meta("peraviz_beam_last_params", {"scaled_intensity": intensity, "beam_intensity": intensity, "intensity_visibility_threshold": 0.015, "intensity_max": 50.0})
		beam_mesh.visible = intensity > 0.015

	func _update_beam_intensity_for_light(light: SpotLight3D, _normalized_dimmer: float, _beam_color: Color, scaled_intensity_override: float = -1.0) -> bool:
		if light != beam_light:
			return false
		var intensity: float = scaled_intensity_override if scaled_intensity_override >= 0.0 else 0.0
		beam_mesh.visible = intensity > 0.015
		light.set_meta("peraviz_beam_last_params", {"scaled_intensity": intensity, "beam_intensity": intensity, "intensity_visibility_threshold": 0.015, "intensity_max": 50.0})
		return true

	func _get_native_dimmer_target_record(dimmer_target_id: int) -> Dictionary:
		if not dimmer_valid or dimmer_target_id != 201:
			return {}
		if not dimmer_has_resources:
			return {
				"geometry_nodes": [dimmer_node],
				"emitter_nodes": [],
				"emitter_anchors": [],
				"beam_instances": [],
				"lens_material_targets": [],
				"emitter_photometrics": [],
			}
		last_dimmer_light = SpotLight3D.new()
		return {
			"geometry_nodes": [dimmer_node],
			"emitter_nodes": [dimmer_node],
			"emitter_anchors": [last_dimmer_light],
			"beam_instances": [last_dimmer_light],
			"lens_material_targets": [],
			"emitter_photometrics": [],
		}

	func _get_fixture_geometry_nodes(_fixture_uuid: String) -> Array:
		return [Node3D.new()]

	func _get_fixture_emitter_nodes(_fixture_uuid: String) -> Array:
		return [Node3D.new()]

	func _get_fixture_emitter_photometrics(_fixture_uuid: String) -> Array:
		return []

	func _collect_fixture_emitter_lights(_fixture_uuid: String, _emitter_nodes: Array) -> Array:
		var light := SpotLight3D.new()
		return [light]

	func _collect_fixture_emissive_materials(_fixture_uuid: String, _geometry_nodes: Array) -> Array:
		return []

class FakeNativeSceneLoader:
	extends Node

	func compile_visual_runtime_scene(_universe_offset: int) -> Dictionary:
		return {"renderer_manifest": [], "property_count": 0, "setup_summary": {}}

class FakeRendererTargetRegistry:
	extends Node
	var install_calls: int = 0

	func _register_native_runtime_targets(_renderer_manifest: Array) -> void:
		install_calls += 1

	func _get_native_target_registry_summary() -> Dictionary:
		return {"registry_summary": {}}

	func _apply_native_transform_targets(_pan_component_id: int, _tilt_component_id: int, _pan_degrees: float, _tilt_degrees: float) -> Dictionary:
		return {}

	func _has_native_dimmer_target(_dimmer_target_id: int) -> bool:
		return false

	func _get_native_dimmer_target_record(_dimmer_target_id: int) -> Dictionary:
		return {}

	func _get_native_target_failure(_target_id: int) -> Variant:
		return null

func _init() -> void:
	var applier = SectionedVisualFrameApplierScript.new()
	applier.install_schema({"sections": [
		{"section_type": 1, "row_stride_ints": 4, "row_stride_floats": 2},
		{"section_type": 2, "row_stride_ints": 3, "row_stride_floats": 5},
		{"section_type": 14, "row_stride_ints": 3, "row_stride_floats": 6},
	]})
	var loader := FakeLoader.new()
	var light_apply_service = FixtureLightApplyServiceScript.new()
	var snapshot: Dictionary = {
		"descriptors": PackedInt32Array([1, 1, 0, 0, 0, 2, 1, 4, 2, 0]),
		"integers": PackedInt32Array([1, 101, 102, 1, 1, 201, 2]),
		"floats": PackedFloat32Array([45.0, -30.0, 1.0, 20.0, 20.0, 1.0, 4.0]),
	}
	var result: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	assert(int(result.get("updated", 0)) == 1)
	assert(is_equal_approx(loader.pan_node.rotation_degrees.y, 45.0))
	assert(is_equal_approx(loader.tilt_node.rotation_degrees.x, -30.0))
	assert(loader.last_dimmer_light != null)
	assert(loader.last_dimmer_light.light_energy > 0.0)
	var diagnostics: Dictionary = result.get("skip_diagnostics", {})
	assert(int(diagnostics.get("dimmer_requested", 0)) == 1)
	assert(int(diagnostics.get("dimmer_mutated", 0)) == 1)
	assert(int(diagnostics.get("dimmer_lights_mutated", 0)) >= 1)
	var beam_snapshot: Dictionary = {
		"descriptors": PackedInt32Array([14, 1, 0, 0, 0]),
		"integers": PackedInt32Array([1, 301, 2]),
		"floats": PackedFloat32Array([1.0, 320.0, 0.02, 6.4, 0.4, 0.0]),
	}
	var beam_result: Dictionary = applier.apply_snapshot(beam_snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	var beam_diagnostics: Dictionary = beam_result.get("skip_diagnostics", {})
	assert(int(beam_diagnostics.get("beam_target_rows", 0)) == 1)
	assert(int(beam_diagnostics.get("beam_targets_resolved", 0)) == 1)
	assert(int(beam_diagnostics.get("beams_updated", 0)) >= 1)
	assert(loader.beam_mesh.visible)
	var beam_zero: Dictionary = {
		"descriptors": PackedInt32Array([14, 1, 0, 0, 0]),
		"integers": PackedInt32Array([1, 301, 2]),
		"floats": PackedFloat32Array([0.0, 320.0, 0.02, 0.0, 0.0, 0.0]),
	}
	var zero_result: Dictionary = applier.apply_snapshot(beam_zero, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	assert(int(zero_result.get("skip_diagnostics", {}).get("beam_targets_failed", 0)) == 0)
	assert(not loader.beam_mesh.visible)
	loader.beam_valid = false
	var missing_beam: Dictionary = applier.apply_snapshot(beam_snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	assert(int(missing_beam.get("skip_diagnostics", {}).get("beam_targets_failed", 0)) == 1)
	loader.beam_valid = true
	loader.dimmer_has_resources = false
	var no_resource: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	assert(int(no_resource.get("skipped", 0)) > 0)
	var no_resource_diagnostics: Dictionary = no_resource.get("skip_diagnostics", {})
	assert(int(no_resource_diagnostics.get("dimmer_failed", 0)) == 1)
	loader.dimmer_has_resources = true
	loader.dimmer_valid = false
	var failed: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	assert(int(failed.get("skipped", 0)) > 0)
	var runtime = DmxFixtureRuntimeScript.new()
	var native_loader := FakeNativeSceneLoader.new()
	var renderer_registry := FakeRendererTargetRegistry.new()
	runtime.configure(native_loader, null, renderer_registry, null)
	assert(runtime._install_renderer_manifest([]))
	assert(renderer_registry.install_calls == 1)
	var missing_registry_runtime = DmxFixtureRuntimeScript.new()
	missing_registry_runtime.configure(native_loader, null, null, null)
	assert(not missing_registry_runtime._install_renderer_manifest([]))
	quit(0)
