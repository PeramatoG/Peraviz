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

func apply_snapshot(snapshot: Dictionary, loader: Node, light_apply_service: FixtureLightApplyService, frame_delta_sec: float, dmx_runtime: Object, fixture_uuids_by_id: Dictionary, bound_fixture_ids: Dictionary) -> Dictionary:
	var descriptors: PackedInt32Array = snapshot.get("descriptors", PackedInt32Array())
	var integers: PackedInt32Array = snapshot.get("integers", PackedInt32Array())
	var floats: PackedFloat32Array = snapshot.get("floats", PackedFloat32Array())
	if descriptors.is_empty() or descriptors.size() % DESCRIPTOR_STRIDE != 0:
		return {"updated": 0, "skipped": 0, "fixtures_considered": 0, "visual_mask_counts": {}}
	var counts: Dictionary = _new_counts()
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
			continue
		for row_index in range(row_count):
			var row_int_base: int = int_offset + (row_index * int_stride)
			var row_float_base: int = float_offset + (row_index * float_stride)
			var fixture_id: int = _fixture_id_for_row(row_int_base, integers)
			var fixture_uuid: String = str(fixture_uuids_by_id.get(fixture_id, ""))
			if fixture_uuid.is_empty() or not bound_fixture_ids.has(fixture_uuid):
				skipped += 1
				continue
			var row_result: Dictionary = _apply_section_row(section_type, row_int_base, row_float_base, integers, floats, loader, light_apply_service, fixture_uuid, frame_delta_sec, dmx_runtime, counts)
			if not bool(row_result.get("applied", false)):
				skipped += 1
				failed_rows += 1
				continue
			updated_fixtures[fixture_uuid] = true
			applied_rows += 1
	return {"updated": updated_fixtures.size(), "skipped": skipped, "fixtures_considered": updated_fixtures.size() + skipped, "visual_mask_counts": counts, "targets_applied": applied_rows, "targets_failed": failed_rows}

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
	}

func _fixture_id_for_row(int_base: int, integers: PackedInt32Array) -> int:
	if int_base < 0 or int_base >= integers.size():
		return 0
	return integers[int_base]

func _apply_section_row(section_type: int, int_base: int, float_base: int, integers: PackedInt32Array, floats: PackedFloat32Array, loader: Node, light_apply_service: FixtureLightApplyService, fixture_uuid: String, frame_delta_sec: float, dmx_runtime: Object, counts: Dictionary) -> Dictionary:
	if int_base < 0 or int_base >= integers.size() or float_base < 0 or float_base > floats.size():
		return {"applied": false}
	var changed_mask: int = _changed_mask_for_row(section_type, int_base, integers)
	_record_changed_mask(changed_mask, counts)
	match section_type:
		SECTION_GEOMETRY_TRANSFORM:
			counts["transform_rows_generated"] += 1
			if float_base + 1 >= floats.size(): return {"applied": false}
			var pan_component_id: int = integers[int_base + 1] if int_base + 1 < integers.size() else 0
			var tilt_component_id: int = integers[int_base + 2] if int_base + 2 < integers.size() else 0
			var transform_result: Dictionary = light_apply_service.apply_transform_targets(loader, fixture_uuid, pan_component_id, tilt_component_id, floats[float_base], floats[float_base + 1])
			return {"applied": bool(transform_result.get("pan_applied", false)) or bool(transform_result.get("tilt_applied", false))}
		SECTION_EMITTER_INTENSITY:
			counts["intensity_rows_generated"] += 1
			if float_base + 4 >= floats.size(): return {"applied": false}
			var dimmer_target_id: int = integers[int_base + 1] if int_base + 1 < integers.size() else 0
			var intensity_result: Dictionary = light_apply_service.apply_emitter_intensity(loader, fixture_uuid, dimmer_target_id, changed_mask, floats[float_base], floats[float_base + 1], floats[float_base + 2], floats[float_base + 3], floats[float_base + 4])
			return {"applied": bool(intensity_result.get("dimmer_applied", false))}
		SECTION_EMITTER_COLOR:
			if float_base + 2 >= floats.size(): return {"applied": false}
			light_apply_service.apply_emitter_color(loader, fixture_uuid, Color(floats[float_base], floats[float_base + 1], floats[float_base + 2], 1.0))
		SECTION_BEAM_OPTICS:
			if float_base + 2 >= floats.size(): return {"applied": false}
			light_apply_service.apply_beam_optics(loader, fixture_uuid, floats[float_base], floats[float_base + 1])
		SECTION_WHEEL_SELECTION:
			if float_base >= floats.size(): return {"applied": false}
			light_apply_service.apply_wheel_selection(loader, fixture_uuid, changed_mask, frame_delta_sec, floats[float_base], dmx_runtime)
		SECTION_WHEEL_MOTION:
			if float_base + 1 >= floats.size(): return {"applied": false}
			light_apply_service.apply_wheel_motion(loader, fixture_uuid, changed_mask, frame_delta_sec, floats[float_base], floats[float_base + 1], dmx_runtime)
		SECTION_TEMPORAL_OUTPUT:
			if float_base >= floats.size(): return {"applied": false}
			light_apply_service.apply_temporal_output(loader, fixture_uuid, floats[float_base], floats[float_base + 1] if float_base + 1 < floats.size() else 1.0)
		_:
			return {"applied": false}
	return {"applied": true}

func _changed_mask_for_row(section_type: int, int_base: int, integers: PackedInt32Array) -> int:
	if section_type == SECTION_WHEEL_SELECTION and int_base + 4 < integers.size():
		return integers[int_base + 4]
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
