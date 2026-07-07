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
const VISUAL_CHANGE_PRISM: int = 1 << 6
const VISUAL_CHANGE_STROBE: int = 1 << 7
const VISUAL_CHANGE_MATERIAL: int = 1 << 8
const VISUAL_CHANGE_BEAM_TOPOLOGY: int = 1 << 9

const LEGACY_HEADER_COUNT: int = 3
const LEGACY_CHANNEL_COUNT: int = 13
const LEGACY_RENDER_VALUE_COUNT: int = 9
const LEGACY_STRIDE: int = LEGACY_HEADER_COUNT + LEGACY_CHANNEL_COUNT + LEGACY_RENDER_VALUE_COUNT
const LEGACY_VISUAL_MASK_OFFSET: int = 2
const LEGACY_VALUES_OFFSET: int = LEGACY_HEADER_COUNT
const LEGACY_RENDER_VALUES_OFFSET: int = LEGACY_HEADER_COUNT + LEGACY_CHANNEL_COUNT

var _schema: Dictionary = {}
var _section_strides: Dictionary = {}
var _fixture_rows: Dictionary = {}

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
	if descriptors.is_empty():
		return {"updated": 0, "skipped": 0, "fixtures_considered": 0, "visual_mask_counts": {}}
	var touched: Dictionary = {}
	var counts: Dictionary = {
		"changed_transform_count": 0,
		"changed_dimmer_count": 0,
		"changed_color_count": 0,
		"changed_zoom_count": 0,
		"changed_gobo_count": 0,
		"changed_gobo_rotation_count": 0,
	}
	for descriptor_base in range(0, descriptors.size(), DESCRIPTOR_STRIDE):
		var section_type: int = descriptors[descriptor_base]
		var row_count: int = descriptors[descriptor_base + 1]
		var int_offset: int = descriptors[descriptor_base + 2]
		var float_offset: int = descriptors[descriptor_base + 3]
		var strides: Dictionary = _section_strides.get(section_type, {})
		var int_stride: int = int(strides.get("ints", 0))
		var float_stride: int = int(strides.get("floats", 0))
		for row_index in range(row_count):
			_apply_section_row(section_type, int_offset + (row_index * int_stride), float_offset + (row_index * float_stride), integers, floats, touched, counts)
	var updated: int = 0
	var skipped: int = 0
	for fixture_id in touched.keys():
		var fixture_uuid: String = str(fixture_uuids_by_id.get(int(fixture_id), ""))
		if fixture_uuid.is_empty() or not bound_fixture_ids.has(fixture_uuid):
			skipped += 1
			continue
		var row: PackedFloat32Array = _fixture_rows.get(int(fixture_id), PackedFloat32Array())
		if row.size() != LEGACY_STRIDE:
			continue
		if dmx_runtime != null and dmx_runtime.has_method("update_live_visual_gobo_from_section"):
			dmx_runtime.update_live_visual_gobo_from_section(fixture_uuid, row[LEGACY_VALUES_OFFSET + 7], row[LEGACY_VALUES_OFFSET + 8], row[LEGACY_VALUES_OFFSET + 9], int(row[LEGACY_VISUAL_MASK_OFFSET]))
		light_apply_service.apply_visual_frame_to_fixture(loader, fixture_uuid, row, 0, frame_delta_sec, dmx_runtime)
		row[LEGACY_VISUAL_MASK_OFFSET] = 0
		updated += 1
	return {"updated": updated, "skipped": skipped, "fixtures_considered": updated, "visual_mask_counts": counts}

func _row_for_fixture(fixture_id: int) -> PackedFloat32Array:
	var row: PackedFloat32Array = _fixture_rows.get(fixture_id, PackedFloat32Array())
	if row.size() != LEGACY_STRIDE:
		row.resize(LEGACY_STRIDE)
		row[0] = fixture_id
	_fixture_rows[fixture_id] = row
	return row

func _apply_section_row(section_type: int, int_base: int, float_base: int, integers: PackedInt32Array, floats: PackedFloat32Array, touched: Dictionary, counts: Dictionary) -> void:
	if int_base < 0 or int_base >= integers.size():
		return
	var fixture_id: int = integers[int_base]
	var row: PackedFloat32Array = _row_for_fixture(fixture_id)
	var changed_mask: int = 0
	if section_type == SECTION_WHEEL_MOTION:
		changed_mask = integers[int_base + 2]
	elif section_type == SECTION_TEMPORAL_OUTPUT:
		changed_mask = integers[int_base + 3]
	elif int_base + 2 < integers.size():
		changed_mask = integers[int_base + 2]
	row[LEGACY_VISUAL_MASK_OFFSET] = int(row[LEGACY_VISUAL_MASK_OFFSET]) | changed_mask
	touched[fixture_id] = true
	if (changed_mask & VISUAL_CHANGE_TRANSFORM) != 0: counts["changed_transform_count"] += 1
	if (changed_mask & VISUAL_CHANGE_DIMMER) != 0: counts["changed_dimmer_count"] += 1
	if (changed_mask & VISUAL_CHANGE_COLOR) != 0: counts["changed_color_count"] += 1
	if (changed_mask & VISUAL_CHANGE_ZOOM) != 0: counts["changed_zoom_count"] += 1
	if (changed_mask & VISUAL_CHANGE_GOBO) != 0: counts["changed_gobo_count"] += 1
	if (changed_mask & VISUAL_CHANGE_GOBO_ROTATION) != 0: counts["changed_gobo_rotation_count"] += 1
	match section_type:
		SECTION_GEOMETRY_TRANSFORM:
			row[LEGACY_VALUES_OFFSET + 1] = floats[float_base]
			row[LEGACY_VALUES_OFFSET + 2] = floats[float_base + 1]
		SECTION_EMITTER_INTENSITY:
			row[LEGACY_VALUES_OFFSET] = floats[float_base]
			row[LEGACY_RENDER_VALUES_OFFSET] = floats[float_base + 1]
			row[LEGACY_RENDER_VALUES_OFFSET + 1] = floats[float_base + 2]
			row[LEGACY_RENDER_VALUES_OFFSET + 7] = floats[float_base + 3]
			row[LEGACY_RENDER_VALUES_OFFSET + 8] = floats[float_base + 4]
		SECTION_EMITTER_COLOR:
			row[LEGACY_RENDER_VALUES_OFFSET + 4] = floats[float_base]
			row[LEGACY_RENDER_VALUES_OFFSET + 5] = floats[float_base + 1]
			row[LEGACY_RENDER_VALUES_OFFSET + 6] = floats[float_base + 2]
		SECTION_BEAM_OPTICS:
			row[LEGACY_RENDER_VALUES_OFFSET + 2] = floats[float_base]
			row[LEGACY_RENDER_VALUES_OFFSET + 3] = floats[float_base + 1]
			row[LEGACY_VALUES_OFFSET + 3] = floats[float_base + 2]
		SECTION_WHEEL_SELECTION:
			row[LEGACY_VALUES_OFFSET + 7] = floats[float_base]
		SECTION_WHEEL_MOTION:
			row[LEGACY_VALUES_OFFSET + 8] = floats[float_base]
			row[LEGACY_VALUES_OFFSET + 9] = floats[float_base + 1]
		SECTION_TEMPORAL_OUTPUT:
			row[LEGACY_VALUES_OFFSET + 12] = floats[float_base]
