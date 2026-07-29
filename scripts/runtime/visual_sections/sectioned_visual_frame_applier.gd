extends RefCounted
class_name SectionedVisualFrameApplier

const SECTION_GEOMETRY_TRANSFORM: int = 1
const SECTION_EMITTER_INTENSITY: int = 2
const SECTION_EMITTER_COLOR: int = 3
const SECTION_BEAM_OPTICS: int = 4
const SECTION_WHEEL_SELECTION: int = 5
const SECTION_WHEEL_MOTION: int = 6
const SECTION_TEMPORAL_OUTPUT: int = 8
const DESCRIPTOR_STRIDE: int = 5

const VISUAL_CHANGE_TRANSFORM: int = 1 << 0
const VISUAL_CHANGE_DIMMER: int = 1 << 1
const VISUAL_CHANGE_COLOR: int = 1 << 2
const VISUAL_CHANGE_ZOOM: int = 1 << 3
const VISUAL_CHANGE_GOBO: int = 1 << 4
const VISUAL_CHANGE_GOBO_ROTATION: int = 1 << 5

var _schema: Dictionary = {}
var _section_strides: Dictionary = {}

func install_schema(schema: Dictionary) -> void:
	_schema = schema.duplicate(true)
	_section_strides.clear()
	for section in schema.get("sections", []):
		if section is Dictionary:
			_section_strides[int(section.get("section_type", 0))] = {
				"ints": int(section.get("row_stride_ints", 0)),
				"floats": int(section.get("row_stride_floats", 0)),
			}

func apply_snapshot(snapshot: Dictionary, loader: Node, light_apply_service: FixtureLightApplyService, frame_delta_sec: float, dmx_runtime: Object, fixture_uuids_by_id: Dictionary, scene_fixture_uuids: Dictionary = {}) -> Dictionary:
	var descriptors: PackedInt32Array = snapshot.get("descriptors", PackedInt32Array())
	var integers: PackedInt32Array = snapshot.get("integers", PackedInt32Array())
	var floats: PackedFloat32Array = snapshot.get("floats", PackedFloat32Array())
	if descriptors.is_empty() or descriptors.size() % DESCRIPTOR_STRIDE != 0:
		return {"updated": 0, "skipped": 0, "fixtures_considered": 0, "visual_mask_counts": {}, "skip_diagnostics": _new_skip_diagnostics()}
	var counts: Dictionary = _new_counts()
	var skip_diagnostics: Dictionary = _new_skip_diagnostics()
	var updated_fixtures: Dictionary = {}
	var skipped: int = 0
	var applied_rows: int = 0
	var failed_rows: int = 0
	for descriptor_base in range(0, descriptors.size(), DESCRIPTOR_STRIDE):
		var section_type: int = descriptors[descriptor_base]
		var row_count: int = descriptors[descriptor_base + 1]
		var int_offset: int = descriptors[descriptor_base + 2]
		var float_offset: int = descriptors[descriptor_base + 3]
		var strides: Dictionary = _section_strides.get(section_type, {})
		var int_stride: int = int(strides.get("ints", 0))
		var float_stride: int = int(strides.get("floats", 0))
		if int_stride <= 0 or float_stride < 0:
			skipped += row_count
			skip_diagnostics["invalid_schema_payload"] = int(skip_diagnostics.get("invalid_schema_payload", 0)) + row_count
			_record_failure(skip_diagnostics, {"reason": "invalid schema stride", "section_type": section_type})
			continue
		for row_index in range(row_count):
			skip_diagnostics["rows_generated"] = int(skip_diagnostics.get("rows_generated", 0)) + 1
			var row_int_base: int = int_offset + (row_index * int_stride)
			var row_float_base: int = float_offset + (row_index * float_stride)
			var fixture_id: int = _fixture_id_for_row(row_int_base, integers)
			var fixture_uuid: String = str(fixture_uuids_by_id.get(fixture_id, ""))
			if fixture_uuid.is_empty():
				skipped += 1
				skip_diagnostics["unknown_fixture_id"] = int(skip_diagnostics.get("unknown_fixture_id", 0)) + 1
				_record_failure(skip_diagnostics, {"reason": "unknown fixture ID", "fixture_id": fixture_id, "section_type": section_type})
				continue
			if not scene_fixture_uuids.is_empty() and not scene_fixture_uuids.has(fixture_uuid):
				skipped += 1
				skip_diagnostics["missing_scene_fixture"] = int(skip_diagnostics.get("missing_scene_fixture", 0)) + 1
				_record_failure(skip_diagnostics, {"reason": "fixture not present in SceneRegistry", "fixture_id": fixture_id, "fixture_uuid": fixture_uuid, "section_type": section_type})
				continue
			var row_result: Dictionary = _apply_section_row(section_type, row_int_base, row_float_base, integers, floats, loader, light_apply_service, fixture_uuid, frame_delta_sec, dmx_runtime, counts)
			_merge_application_result(skip_diagnostics, row_result)
			if not bool(row_result.get("applied", false)):
				skipped += 1
				failed_rows += 1
				continue
			updated_fixtures[fixture_uuid] = true
			applied_rows += 1
	return {"updated": updated_fixtures.size(), "skipped": skipped, "fixtures_considered": updated_fixtures.size() + skipped, "visual_mask_counts": counts, "targets_applied": applied_rows, "targets_failed": failed_rows, "skip_diagnostics": skip_diagnostics}

func _new_counts() -> Dictionary:
	return {
		"changed_transform_count": 0,
		"changed_dimmer_count": 0,
		"changed_color_count": 0,
		"changed_zoom_count": 0,
		"changed_gobo_count": 0,
		"changed_gobo_rotation_count": 0,
		"transform_rows_generated": 0,
		"intensity_rows_generated": 0,
		"beam_optics_rows_generated": 0,
	}

func _new_skip_diagnostics() -> Dictionary:
	return {
		"rows_generated": 0,
		"unknown_fixture_id": 0,
		"missing_scene_fixture": 0,
		"legacy_bound_map_rejections": 0,
		"invalid_schema_payload": 0,
		"pan_requested": 0,
		"pan_resolved": 0,
		"pan_failed": 0,
		"pan_mutated": 0,
		"tilt_requested": 0,
		"tilt_resolved": 0,
		"tilt_failed": 0,
		"tilt_mutated": 0,
		"dimmer_requested": 0,
		"dimmer_resolved": 0,
		"dimmer_failed": 0,
		"dimmer_mutated": 0,
		"dimmer_lights_mutated": 0,
		"dimmer_beams_mutated": 0,
		"dimmer_materials_mutated": 0,
		"optics_requested": 0,
		"optics_resolved": 0,
		"optics_failed": 0,
		"optics_mutated": 0,
		"first_failures": [],
	}

func _record_failure(skip_diagnostics: Dictionary, failure: Dictionary) -> void:
	var failures: Array = skip_diagnostics.get("first_failures", [])
	if failures.size() < 5:
		failures.append(failure)
	skip_diagnostics["first_failures"] = failures

func _merge_application_result(skip_diagnostics: Dictionary, row_result: Dictionary) -> void:
	for key in ["pan_requested", "pan_resolved", "pan_failed", "pan_mutated", "tilt_requested", "tilt_resolved", "tilt_failed", "tilt_mutated", "dimmer_requested", "dimmer_resolved", "dimmer_failed", "dimmer_mutated", "dimmer_lights_mutated", "dimmer_beams_mutated", "dimmer_materials_mutated", "optics_requested", "optics_resolved", "optics_failed", "optics_mutated"]:
		skip_diagnostics[key] = int(skip_diagnostics.get(key, 0)) + int(row_result.get(key, 0))
	if row_result.has("failure"):
		_record_failure(skip_diagnostics, row_result.get("failure", {}))

func _fixture_id_for_row(int_base: int, integers: PackedInt32Array) -> int:
	if int_base < 0 or int_base >= integers.size():
		return 0
	return integers[int_base]

func _apply_section_row(section_type: int, int_base: int, float_base: int, integers: PackedInt32Array, floats: PackedFloat32Array, loader: Node, light_apply_service: FixtureLightApplyService, fixture_uuid: String, _frame_delta_sec: float, _dmx_runtime: Object, counts: Dictionary) -> Dictionary:
	if int_base < 0 or int_base >= integers.size() or float_base < 0 or float_base > floats.size():
		return {"applied": false}
	var changed_mask: int = _changed_mask_for_row(section_type, int_base, integers)
	_record_changed_mask(changed_mask, counts)
	match section_type:
		SECTION_GEOMETRY_TRANSFORM:
			counts["transform_rows_generated"] += 1
			if float_base + 1 >= floats.size(): return {"applied": false, "failure": {"reason": "invalid transform payload", "fixture_uuid": fixture_uuid}}
			var pan_component_id: int = integers[int_base + 1] if int_base + 1 < integers.size() else 0
			var tilt_component_id: int = integers[int_base + 2] if int_base + 2 < integers.size() else 0
			var transform_result: Dictionary = light_apply_service.apply_transform_targets(loader, pan_component_id, tilt_component_id, floats[float_base], floats[float_base + 1])
			transform_result["applied"] = bool(transform_result.get("pan_applied", false)) or bool(transform_result.get("tilt_applied", false))
			return _categorized_transform_result(loader, fixture_uuid, pan_component_id, tilt_component_id, transform_result)
		SECTION_EMITTER_INTENSITY:
			counts["intensity_rows_generated"] += 1
			if float_base + 4 >= floats.size(): return {"applied": false, "failure": {"reason": "invalid intensity payload", "fixture_uuid": fixture_uuid}}
			var dimmer_target_id: int = integers[int_base + 1] if int_base + 1 < integers.size() else 0
			var intensity_result: Dictionary = light_apply_service.apply_emitter_intensity(loader, fixture_uuid, dimmer_target_id, changed_mask, floats[float_base], floats[float_base + 1], floats[float_base + 2], floats[float_base + 3], floats[float_base + 4])
			intensity_result["applied"] = bool(intensity_result.get("dimmer_applied", false))
			return _categorized_dimmer_result(loader, fixture_uuid, dimmer_target_id, intensity_result)
		SECTION_EMITTER_COLOR:
			if float_base + 3 >= floats.size(): return {"applied": false}
			var color_target_id: int = integers[int_base + 1] if int_base + 1 < integers.size() else 0
			var color_result: Dictionary = light_apply_service.apply_emitter_color(loader, fixture_uuid, color_target_id, changed_mask, Color(floats[float_base], floats[float_base + 1], floats[float_base + 2], 1.0), floats[float_base + 3])
			color_result["applied"] = bool(color_result.get("color_applied", false))
			return color_result
		SECTION_BEAM_OPTICS:
			counts["beam_optics_rows_generated"] += 1
			if float_base + 2 >= floats.size(): return {"applied": false}
			var optics_target_id: int = integers[int_base + 1] if int_base + 1 < integers.size() else 0
			var optics_result: Dictionary = light_apply_service.apply_beam_optics(loader, fixture_uuid, optics_target_id, changed_mask, floats[float_base], floats[float_base + 1], floats[float_base + 2])
			optics_result["applied"] = bool(optics_result.get("optics_applied", false))
			return optics_result
		SECTION_WHEEL_SELECTION:
			if int_base + 7 >= integers.size() or float_base + 7 >= floats.size(): return {"applied": false, "failure": {"reason": "invalid wheel selection payload", "fixture_uuid": fixture_uuid}}
			return light_apply_service.apply_wheel_optical_state(loader, fixture_uuid, integers[int_base + 1], integers[int_base + 2], integers[int_base + 3], integers[int_base + 4], integers[int_base + 5], integers[int_base + 6], integers[int_base + 7], floats[float_base], floats[float_base + 1], floats[float_base + 2], Color(floats[float_base + 3], floats[float_base + 4], floats[float_base + 5], 1.0), floats[float_base + 6], floats[float_base + 7])
		SECTION_WHEEL_MOTION:
			if int_base + 5 >= integers.size() or float_base + 3 >= floats.size(): return {"applied": false, "failure": {"reason": "invalid wheel motion payload", "fixture_uuid": fixture_uuid}}
			return light_apply_service.apply_wheel_motion_state(loader, fixture_uuid, integers[int_base + 1], integers[int_base + 2], integers[int_base + 3], integers[int_base + 4], integers[int_base + 5], floats[float_base], floats[float_base + 1], floats[float_base + 2], floats[float_base + 3])
		SECTION_TEMPORAL_OUTPUT:
			if float_base >= floats.size(): return {"applied": false}
			light_apply_service.apply_temporal_output(loader, fixture_uuid, floats[float_base], floats[float_base + 1] if float_base + 1 < floats.size() else 1.0)
		_:
			return {"applied": false}
	return {"applied": true}

func _categorized_transform_result(loader: Node, fixture_uuid: String, pan_component_id: int, tilt_component_id: int, result: Dictionary) -> Dictionary:
	result["pan_requested"] = 1 if pan_component_id > 0 else 0
	result["tilt_requested"] = 1 if tilt_component_id > 0 else 0
	result["pan_mutated"] = 1 if bool(result.get("pan_applied", false)) else 0
	result["tilt_mutated"] = 1 if bool(result.get("tilt_applied", false)) else 0
	result["pan_resolved"] = result["pan_mutated"]
	result["tilt_resolved"] = result["tilt_mutated"]
	result["pan_failed"] = 1 if pan_component_id > 0 and not bool(result.get("pan_applied", false)) else 0
	result["tilt_failed"] = 1 if tilt_component_id > 0 and not bool(result.get("tilt_applied", false)) else 0
	if not bool(result.get("applied", false)):
		result["failure"] = {"reason": "transform target not mutated", "fixture_uuid": fixture_uuid, "pan_component_id": pan_component_id, "tilt_component_id": tilt_component_id, "pan_target_failure": _target_failure_for(loader, pan_component_id), "tilt_target_failure": _target_failure_for(loader, tilt_component_id)}
	return result

func _categorized_dimmer_result(loader: Node, fixture_uuid: String, dimmer_target_id: int, result: Dictionary) -> Dictionary:
	var target_resolved: bool = bool(result.get("target_resolved", false))
	var dimmer_applied: bool = bool(result.get("dimmer_applied", false))
	result["dimmer_requested"] = 1 if dimmer_target_id > 0 else 0
	result["dimmer_resolved"] = 1 if target_resolved else 0
	result["dimmer_mutated"] = 1 if dimmer_applied else 0
	result["dimmer_lights_mutated"] = int(result.get("lights_mutated", 0))
	result["dimmer_beams_mutated"] = int(result.get("beams_mutated", 0))
	result["dimmer_materials_mutated"] = int(result.get("materials_mutated", 0))
	result["dimmer_failed"] = 1 if dimmer_target_id > 0 and not dimmer_applied else 0
	if not bool(result.get("applied", false)):
		result["failure"] = {"reason": str(result.get("failure_reason", "dimmer target not mutated")), "fixture_uuid": fixture_uuid, "dimmer_target_id": dimmer_target_id, "target_failure": _target_failure_for(loader, dimmer_target_id), "lights_considered": int(result.get("lights_considered", 0)), "lights_mutated": int(result.get("lights_mutated", 0)), "beams_mutated": int(result.get("beams_mutated", 0)), "materials_mutated": int(result.get("materials_mutated", 0))}
	return result

func _target_failure_for(loader: Node, target_id: int) -> Variant:
	if target_id <= 0 or not loader.has_method("_get_native_target_failure"):
		return null
	return loader._get_native_target_failure(target_id)

func _changed_mask_for_row(section_type: int, int_base: int, integers: PackedInt32Array) -> int:
	if section_type == SECTION_WHEEL_SELECTION and int_base + 6 < integers.size():
		return integers[int_base + 6]
	if section_type == SECTION_WHEEL_MOTION and int_base + 2 < integers.size():
		return integers[int_base + 2]
	if section_type == SECTION_TEMPORAL_OUTPUT and int_base + 3 < integers.size():
		return integers[int_base + 3]
	if section_type == SECTION_GEOMETRY_TRANSFORM and int_base + 3 < integers.size():
		return integers[int_base + 3]
	if int_base + 2 < integers.size():
		return integers[int_base + 2]
	return 0

func _record_changed_mask(changed_mask: int, counts: Dictionary) -> void:
	if (changed_mask & VISUAL_CHANGE_TRANSFORM) != 0: counts["changed_transform_count"] += 1
	if (changed_mask & VISUAL_CHANGE_DIMMER) != 0: counts["changed_dimmer_count"] += 1
	if (changed_mask & VISUAL_CHANGE_COLOR) != 0: counts["changed_color_count"] += 1
	if (changed_mask & VISUAL_CHANGE_ZOOM) != 0: counts["changed_zoom_count"] += 1
	if (changed_mask & VISUAL_CHANGE_GOBO) != 0: counts["changed_gobo_count"] += 1
	if (changed_mask & VISUAL_CHANGE_GOBO_ROTATION) != 0: counts["changed_gobo_rotation_count"] += 1
