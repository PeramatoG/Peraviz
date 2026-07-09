extends SceneTree

const SectionedVisualFrameApplierScript = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")
const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")

class FakeLoader:
	extends Node
	var pan_node := Node3D.new()
	var tilt_node := Node3D.new()
	var dimmer_node := Node3D.new()
	var dimmer_valid: bool = true

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

	func _get_native_dimmer_target_record(dimmer_target_id: int) -> Dictionary:
		if not dimmer_valid or dimmer_target_id != 201:
			return {}
		var light := SpotLight3D.new()
		return {
			"geometry_nodes": [dimmer_node],
			"emitter_nodes": [dimmer_node],
			"emitter_lights": [light],
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

func _init() -> void:
	var applier = SectionedVisualFrameApplierScript.new()
	applier.install_schema({"sections": [
		{"section_type": 1, "row_stride_ints": 4, "row_stride_floats": 2},
		{"section_type": 2, "row_stride_ints": 3, "row_stride_floats": 5},
	]})
	var loader := FakeLoader.new()
	var light_apply_service = FixtureLightApplyServiceScript.new()
	var snapshot: Dictionary = {
		"descriptors": PackedInt32Array([1, 1, 0, 0, 0, 2, 1, 4, 2, 0]),
		"integers": PackedInt32Array([1, 101, 102, 1, 1, 201, 2]),
		"floats": PackedFloat32Array([45.0, -30.0, 1.0, 20.0, 20.0, 1.0, 4.0]),
	}
	var result: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"}, {"fixture-a": true})
	assert(int(result.get("updated", 0)) == 1)
	assert(is_equal_approx(loader.pan_node.rotation_degrees.y, 45.0))
	assert(is_equal_approx(loader.tilt_node.rotation_degrees.x, -30.0))
	loader.dimmer_valid = false
	var failed: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"}, {"fixture-a": true})
	assert(int(failed.get("skipped", 0)) > 0)
	quit(0)
