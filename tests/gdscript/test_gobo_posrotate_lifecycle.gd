extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const RegistryScript = preload("res://scripts/runtime/native_gobo_resource_registry.gd")
const FrameApplierScript = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")
const RotationPresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

class MultiTargetLoader:
	extends Node
	var registry: RefCounted
	var targets: Dictionary = {}

	func _apply_native_gobo_selection(beam_target_id: int, wheel_id: int, wheel_instance_index: int, slot_index: int, asset_id: int, selection_mode: int) -> Dictionary:
		return registry.apply_selection(beam_target_id, wheel_id, wheel_instance_index, slot_index, asset_id, selection_mode, targets[beam_target_id])

	func _apply_native_gobo_rotation_state(beam_target_id: int, wheel_id: int, wheel_instance_index: int, rotation_mode: int, revision: int, phase_degrees: float, angular_velocity_dps: float, reference_seconds: float, native_now_seconds: float) -> Dictionary:
		return registry.apply_rotation_state(beam_target_id, wheel_id, wheel_instance_index, rotation_mode, revision, phase_degrees, angular_velocity_dps, reference_seconds, native_now_seconds, targets[beam_target_id], 1000000)

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	var failures := PackedStringArray()
	_test_protocol_mask(failures)
	_test_rotation_lifecycle(failures)
	_test_eight_target_clear_reapply(failures)
	if failures.is_empty():
		print("Gobo PosRotate lifecycle checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_protocol_mask(failures: PackedStringArray) -> void:
	var applier: RefCounted = FrameApplierScript.new()
	var integers := PackedInt32Array()
	for row in range(30):
		integers.append_array(PackedInt32Array([1000 + row, 2000 + row, 0x40 + row, 1 + (row % 2), 2, 0x20, 700 + row]))
	for row in range(30):
		var mask: int = applier._changed_mask_for_row(15, row * 7, integers)
		_check(mask == 0x20, "Protocol 2.3 GoboRotation must read changed_mask from integer field 5 for every row.", failures)

func _test_rotation_lifecycle(failures: PackedStringArray) -> void:
	var registry: RefCounted = RegistryScript.new()
	var path: String = _write_mask()
	var assets := [{"gobo_asset_id": 101, "wheel_id": 11, "slot_index": 1, "extracted_media_path": path, "media_valid": true}]
	registry.install_or_update_assets(assets)
	var beam := MeshInstance3D.new()
	var light := SpotLight3D.new()
	var target := {"beam_instances": [beam], "emitter_anchors": [light]}
	var targets := {77: target}
	registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	registry.apply_rotation_state(77, 11, 1, 2, 1, 45.0, 30.0, 5.0, 5.0, target, 1000000)
	var mesh_before: Mesh = beam.mesh
	registry.advance_motion_at_usec(3000000, targets)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 105.0), "Continuous presentation should use its local monotonic reference.", failures)
	registry.clear_renderer_targets()
	registry.rehydrate_renderer_state(targets, 4000000)
	_check(beam.mesh == mesh_before, "Renderer rehydration must reuse the selected gobo mesh.", failures)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 135.0), "Renderer rehydration must apply the current continuous phase without new DMX.", failures)
	registry.install_or_update_assets(assets)
	registry.rehydrate_renderer_state(targets, 5000000)
	_check(beam.mesh == mesh_before and is_equal_approx(RotationPresentationScript.physical_angle(beam), 165.0), "Unchanged asset reinstall must preserve cached resources and motion state.", failures)
	registry.apply_rotation_state(77, 11, 1, 2, 1, 0.0, 30.0, 0.0, 0.0, target, 6000000)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 195.0), "A bootstrapped native runtime generation must preserve the renderer-local continuous phase.", failures)
	registry.apply_selection(77, 11, 1, 2, 0, 0, target)
	registry.advance_motion_at_usec(7000000, targets)
	registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	registry.rehydrate_renderer_state(targets, 7000000)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 225.0), "Open-slot motion must resume at the current phase.", failures)
	registry.apply_selection(77, 12, 2, 1, 101, 0, target)
	registry.apply_rotation_state(77, 12, 2, 2, 1, 10.0, -20.0, 5.0, 5.0, target, 1000000)
	var deferred: Dictionary = registry.apply_rotation_state(77, 11, 1, 2, 2, 225.0, 30.0, 5.0, 5.0, target, 7000000)
	_check(bool(deferred.get("unsupported_moving_composition", false)), "Independent motion with two visible layers must remain explicitly deferred.", failures)
	var counters: Dictionary = registry.counters()
	_check(int(counters.get("active_continuous_layers", 0)) == 2 and int(counters.get("deferred_multi_wheel_warnings", 0)) > 0, "Motion diagnostics must expose active and deferred multi-layer state.", failures)
	registry.reset_scene_state()
	_check(int(registry.counters().get("active_continuous_layers", -1)) == 0, "A true new-scene reset must clear obsolete motion state.", failures)
	beam.free()
	light.free()
	DirAccess.remove_absolute(path)

func _test_eight_target_clear_reapply(failures: PackedStringArray) -> void:
	var registry: RefCounted = RegistryScript.new()
	var path: String = _write_mask()
	registry.install_or_update_assets([{"gobo_asset_id": 101, "wheel_id": 11, "slot_index": 1, "extracted_media_path": path, "media_valid": true}])
	var loader := MultiTargetLoader.new()
	loader.registry = registry
	var fixture_ids: Dictionary = {}
	var beams: Array[MeshInstance3D] = []
	for index in range(8):
		var beam := MeshInstance3D.new()
		beams.append(beam)
		loader.targets[500 + index] = {"beam_instances": [beam], "emitter_anchors": []}
		fixture_ids[index + 1] = "fixture-%d" % index
	get_root().add_child(loader)
	var applier: RefCounted = FrameApplierScript.new()
	applier.install_schema({"sections": [{"section_type": 14, "row_stride_ints": 9, "row_stride_floats": 1}, {"section_type": 15, "row_stride_ints": 7, "row_stride_floats": 3}]})
	var service: RefCounted = FixtureLightApplyServiceScript.new()
	var selection_ints := PackedInt32Array()
	var rotation_ints := PackedInt32Array()
	var floats := PackedFloat32Array()
	for index in range(8):
		selection_ints.append_array(PackedInt32Array([index + 1, 500 + index, 11, 1, 1, 101, 0, 16, 1]))
		floats.append(0.0)
	for index in range(8):
		rotation_ints.append_array(PackedInt32Array([index + 1, 500 + index, 11, 1, 2, 32, 1]))
		floats.append_array(PackedFloat32Array([30.0, 45.0, 1.0]))
	var integers := PackedInt32Array(selection_ints)
	integers.append_array(rotation_ints)
	var descriptors := PackedInt32Array([14, 8, 0, 0, 0, 15, 8, selection_ints.size(), 8, 0])
	applier.apply_snapshot({"runtime_now_seconds": 1.0, "descriptors": descriptors, "integers": integers, "floats": floats}, loader, service, 0.0, null, fixture_ids)
	for beam in beams:
		_check(beam.mesh != null, "All eight physical Beam targets must receive the selected gobo resource.", failures)
	registry.advance_motion_at_usec(3000000, loader.targets)
	for beam in beams:
		_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 120.0), "All eight Continuous layers must advance identically.", failures)
	var open_ints := PackedInt32Array()
	var open_floats := PackedFloat32Array()
	for index in range(8):
		open_ints.append_array(PackedInt32Array([index + 1, 500 + index, 11, 1, 2, 0, 0, 16, 2]))
		open_floats.append(0.0)
	applier.apply_snapshot({"descriptors": PackedInt32Array([14, 8, 0, 0, 0]), "integers": open_ints, "floats": open_floats}, loader, service, 0.0, null, fixture_ids)
	for beam in beams:
		_check(beam.mesh == null, "Open selection rows must clear every physical Beam resource.", failures)
	applier.apply_snapshot({"descriptors": PackedInt32Array([14, 8, 0, 0, 0]), "integers": selection_ints, "floats": PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])}, loader, service, 0.0, null, fixture_ids)
	for beam in beams:
		_check(beam.mesh != null, "Reselecting the same prior gobo must restore every physical Beam resource.", failures)
	loader.free()
	for beam in beams:
		beam.free()
	DirAccess.remove_absolute(path)

func _write_mask() -> String:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var value: float = 1.0 if x >= 3 and x <= 6 and y >= 2 and y <= 13 else 0.0
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	var path: String = ProjectSettings.globalize_path("user://gobo_posrotate_lifecycle.png")
	image.save_png(path)
	return path

func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
