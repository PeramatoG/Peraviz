extends RefCounted
class_name DmxFixtureRuntime

const MAX_UNBOUND_PREVIEW: int = 8
const FORCE_COARSE_ONLY_DMX_READ: bool = false

const GoboVectorizationCacheScript = preload("res://scripts/gobo_vectorization/gobo_vectorization_cache.gd")

const NATIVE_CHANNEL_PAN: int = 1
const NATIVE_CHANNEL_TILT: int = 2
const NATIVE_CHANNEL_DIMMER: int = 3
const NATIVE_CHANNEL_ZOOM: int = 4
const NATIVE_CHANNEL_CYAN: int = 5
const NATIVE_CHANNEL_MAGENTA: int = 6
const NATIVE_CHANNEL_YELLOW: int = 7
const NATIVE_CHANNEL_GOBO: int = 8
const NATIVE_CHANNEL_GOBO_INDEX: int = 9
const NATIVE_CHANNEL_GOBO_ROTATION: int = 10
const NATIVE_CHANNEL_PRISM: int = 11
const NATIVE_CHANNEL_PRISM_ROTATION: int = 12
const NATIVE_CHANNEL_STROBE: int = 13

const NATIVE_COMPACT_STRIDE: int = 15
const NATIVE_RENDER_READY_STRIDE: int = 24
const NATIVE_COMPACT_DIMMER: int = 0
const NATIVE_COMPACT_PAN: int = 1
const NATIVE_COMPACT_TILT: int = 2
const NATIVE_COMPACT_ZOOM: int = 3
const NATIVE_COMPACT_CYAN: int = 4
const NATIVE_COMPACT_MAGENTA: int = 5
const NATIVE_COMPACT_YELLOW: int = 6
const NATIVE_COMPACT_GOBO: int = 7
const NATIVE_COMPACT_GOBO_INDEX: int = 8
const NATIVE_COMPACT_GOBO_ROTATION: int = 9
const NATIVE_COMPACT_PRISM: int = 10
const NATIVE_COMPACT_PRISM_ROTATION: int = 11
const NATIVE_COMPACT_STROBE: int = 12

const COMPACT_CONTROL_SIZE: int = 29
const COMPACT_HAS_PAN: int = 0
const COMPACT_PAN_NORM: int = 1
const COMPACT_HAS_TILT: int = 2
const COMPACT_TILT_NORM: int = 3
const COMPACT_HAS_DIMMER: int = 4
const COMPACT_DIMMER_NORM: int = 5
const COMPACT_HAS_ZOOM: int = 6
const COMPACT_ZOOM_NORM: int = 7
const COMPACT_HAS_ZOOM_LIMITS: int = 8
const COMPACT_ZOOM_MIN_DEG: int = 9
const COMPACT_ZOOM_MAX_DEG: int = 10
const COMPACT_HAS_CYAN: int = 11
const COMPACT_CYAN_NORM: int = 12
const COMPACT_HAS_MAGENTA: int = 13
const COMPACT_MAGENTA_NORM: int = 14
const COMPACT_HAS_YELLOW: int = 15
const COMPACT_YELLOW_NORM: int = 16
const COMPACT_HAS_GOBO: int = 17
const COMPACT_GOBO_NORM: int = 18
const COMPACT_HAS_GOBO_INDEX: int = 19
const COMPACT_GOBO_INDEX_NORM: int = 20
const COMPACT_HAS_GOBO_ROTATION: int = 21
const COMPACT_GOBO_ROTATION_NORM: int = 22
const COMPACT_HAS_PRISM: int = 23
const COMPACT_PRISM_NORM: int = 24
const COMPACT_HAS_PRISM_ROTATION: int = 25
const COMPACT_PRISM_ROTATION_NORM: int = 26
const COMPACT_HAS_STROBE: int = 27
const COMPACT_STROBE_NORM: int = 28

var _loader = null
var _scene_registry: SceneRegistry = null
var _bindings: Array = []
var _unbound: Array = []
var _fixture_patch_lookup: Dictionary = {}
var _fixture_nodes: Dictionary = {}
var _bound_fixture_ids: Dictionary = {}
var _fixture_channel_offsets: Dictionary = {}
var _fixture_snapshot_cache: Dictionary = {}
var _fixture_capability_state_cache: Dictionary = {}
var _native_visual_runtime: PeravizVisualRuntime = PeravizVisualRuntime.new()
var _native_fixture_ids_by_uuid: Dictionary = {}
var _native_fixture_uuids_by_id: Dictionary = {}
var _native_channel_values: Dictionary = {}
var _native_render_ready_values: Dictionary = {}
var _fixture_apply_plans: Dictionary = {}
var _fixture_output_buffers: Dictionary = {}
var _used_universes: Dictionary = {}
var _bindings_by_universe: Dictionary = {}
var _last_universe_counters: Dictionary = {}
var _cached_universe_frames: Dictionary = {}
var _universe_interest_offsets: Dictionary = {}
var _last_universe_interest_hashes: Dictionary = {}
var _fixture_time_tick_flags: Dictionary = {}
var _fixture_row_provider: FixtureRowProvider = null
var _time_tick_fixture_ids := PackedStringArray()
var _gobo_vectorization_cache: GoboVectorizationCache = null
var _debug_force_full_apply: bool = false

func configure(loader, scene_registry: SceneRegistry, fixture_row_provider: FixtureRowProvider = null) -> void:
	_loader = loader
	_scene_registry = scene_registry
	_fixture_row_provider = fixture_row_provider
	_gobo_vectorization_cache = GoboVectorizationCacheScript.new()

func rebuild(universe_offset: int) -> Dictionary:
	_bindings.clear()
	_unbound.clear()
	_fixture_patch_lookup.clear()
	_fixture_nodes.clear()
	_bound_fixture_ids.clear()
	_fixture_channel_offsets.clear()
	_fixture_snapshot_cache.clear()
	_fixture_capability_state_cache.clear()
	_native_visual_runtime.clear()
	_native_fixture_ids_by_uuid.clear()
	_native_fixture_uuids_by_id.clear()
	_native_channel_values.clear()
	_native_render_ready_values.clear()
	_fixture_apply_plans.clear()
	_fixture_output_buffers.clear()
	_used_universes.clear()
	_bindings_by_universe.clear()
	_last_universe_counters.clear()
	_cached_universe_frames.clear()
	_universe_interest_offsets.clear()
	_last_universe_interest_hashes.clear()
	_fixture_time_tick_flags.clear()
	_time_tick_fixture_ids = PackedStringArray()

	if _loader == null or _scene_registry == null:
		return {
			"bound": 0,
			"unbound": 0,
			"unbound_preview": PackedStringArray(),
		}

	_fixture_patch_lookup = _build_fixture_patch_lookup()

	var result: Dictionary = _loader.build_fixture_dmx_bindings(universe_offset)
	_bindings = result.get("bindings", [])
	_unbound = result.get("unbound", [])

	if _gobo_vectorization_cache != null:
		_gobo_vectorization_cache.enrich_bindings_with_vector_gobos(_bindings)

	for binding in _bindings:
		if binding is not Dictionary:
			continue
		var fixture_uuid: String = str(binding.get("fixture_uuid", ""))
		if fixture_uuid.is_empty():
			continue
		var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid)
		if fixture_node == null:
			_unbound.append({
				"fixture_uuid": fixture_uuid,
				"reason": "fixture node not found in loaded scene",
			})
			continue
		_fixture_nodes[fixture_uuid] = fixture_node
		_bound_fixture_ids[fixture_uuid] = true
		if _loader.has_method("_prepare_fixture_node_cache"):
			_loader._prepare_fixture_node_cache(fixture_uuid)
		_register_native_fixture_id(fixture_uuid)
		_fixture_apply_plans[fixture_uuid] = _build_fixture_apply_plan(binding)
		_fixture_output_buffers[fixture_uuid] = _build_fixture_output_buffer(binding)
		_fixture_channel_offsets[fixture_uuid] = _collect_used_channel_offsets(binding)
		var requires_time_tick: bool = _binding_requires_time_tick(binding)
		_fixture_time_tick_flags[fixture_uuid] = requires_time_tick
		if requires_time_tick:
			_time_tick_fixture_ids.append(fixture_uuid)
		var universe_id: int = int(binding.get("artnet_universe_id", -1))
		if universe_id >= 0:
			_used_universes[universe_id] = true
			if not _bindings_by_universe.has(universe_id):
				_bindings_by_universe[universe_id] = []
			_bindings_by_universe[universe_id].append(binding)
			_add_universe_interest_offsets(universe_id, _fixture_channel_offsets.get(fixture_uuid, PackedInt32Array()))

	_register_native_visual_runtime_bindings()
	_finalize_universe_interest_offsets()

	for universe_key in _used_universes.keys():
		var tracked_universe_id: int = int(universe_key)
		_last_universe_counters[tracked_universe_id] = {
			"counter": -1,
			"content_hash": -1,
			"interest_hash": -1,
			"interest_offsets": _get_universe_interest_offsets_array(tracked_universe_id),
		}

	if _fixture_row_provider != null:
		_fixture_row_provider.set_dmx_state(_bindings, _unbound)

	return _build_summary(universe_offset)

func set_debug_force_full_apply(enabled: bool) -> void:
	_debug_force_full_apply = enabled

func get_bound_fixture_ids() -> PackedStringArray:
	var fixture_ids := PackedStringArray()
	for fixture_uuid in _bound_fixture_ids.keys():
		fixture_ids.append(str(fixture_uuid))
	return fixture_ids

func get_fixture_rows() -> Array:
	if _fixture_row_provider != null:
		return _fixture_row_provider.get_fixture_rows()
	var rows: Array = []
	var seen_fixture_uuids: Dictionary = {}
	for fixture_uuid in _collect_known_fixture_uuids():
		var row: Dictionary = _build_fixture_inspection_row(str(fixture_uuid))
		rows.append(row)
		seen_fixture_uuids[str(fixture_uuid)] = true
	if _scene_registry != null:
		for fixture_uuid in _scene_registry.list_fixture_uuids():
			var key: String = str(fixture_uuid)
			if seen_fixture_uuids.has(key):
				continue
			rows.append(_build_fixture_inspection_row(key))
	rows.sort_custom(Callable(self, "_sort_fixture_inspection_rows"))
	return rows

func get_fixture_inspection_rows() -> Array:
	return get_fixture_rows()

func get_time_tick_fixture_ids() -> PackedStringArray:
	return _time_tick_fixture_ids

func _binding_requires_time_tick(binding: Dictionary) -> bool:
	var channel_bindings: Array = binding.get("channel_bindings", [])
	for channel_binding in channel_bindings:
		if _value_contains_time_tick_signal(channel_binding):
			return true
	if _value_contains_time_tick_signal(binding.get("capabilities", [])):
		return true
	return false

func _value_contains_time_tick_signal(value: Variant) -> bool:
	if value is Dictionary:
		var row: Dictionary = value
		for key in row.keys():
			if _string_requires_time_tick(str(key)):
				return true
			if _value_contains_time_tick_signal(row.get(key, null)):
				return true
		return false
	if value is Array:
		for item in value:
			if _value_contains_time_tick_signal(item):
				return true
		return false
	if value is String:
		return _string_requires_time_tick(str(value))
	return false

func _string_requires_time_tick(value: String) -> bool:
	var normalized: String = value.to_lower()
	if normalized.find("strobe") >= 0:
		return true
	if normalized.find("shake") >= 0:
		return true
	if normalized.find("rotation") >= 0:
		return true
	if normalized.find("rotate") >= 0:
		return true
	if normalized.find("continuous") >= 0:
		return true
	if normalized.find("speed") >= 0:
		return true
	return false

func collect_pending_controls(receiver) -> Dictionary:
	return _collect_dmx(receiver, Callable())

func apply_dmx(receiver, apply_fixture_callback: Callable) -> Dictionary:
	return _collect_dmx(receiver, apply_fixture_callback)

func apply_visual_frame(receiver, loader: Node, light_apply_service: FixtureLightApplyService, frame_delta_sec: float) -> Dictionary:
	return _collect_dmx(receiver, Callable(), loader, light_apply_service, frame_delta_sec)

func _collect_dmx(receiver, apply_fixture_callback: Callable, loader: Node = null, light_apply_service: FixtureLightApplyService = null, frame_delta_sec: float = 0.0) -> Dictionary:
	if receiver == null or not receiver.is_running():
		return {"updated": 0, "skipped": 0, "universes_changed": 0, "fixtures_considered": 0, "controls": []}

	var changed_frames: Dictionary = {}
	if receiver.has_method("get_dirty_universes") and receiver.has_method("consume_universe"):
		changed_frames = _consume_dirty_universe_frames(receiver)
	elif receiver.has_method("get_changed_universe_frames"):
		changed_frames = receiver.get_changed_universe_frames(_last_universe_counters)
	else:
		changed_frames = _collect_changed_universe_frames_compat(receiver)

	if changed_frames.is_empty() and not _debug_force_full_apply:
		return {"updated": 0, "skipped": 0, "universes_changed": 0, "fixtures_considered": 0, "controls": []}

	var updated: int = 0
	var skipped: int = 0
	var fixtures_considered: int = 0
	var pending_controls: Array = []
	for universe_key in changed_frames.keys():
		var universe_id: int = int(universe_key)
		var frame_entry: Dictionary = changed_frames.get(universe_key, {})
		var frame: PackedByteArray = frame_entry.get("data", PackedByteArray())
		if frame.is_empty():
			continue
		_cached_universe_frames[universe_id] = frame
		var interest_hash: int = int(frame_entry.get("interest_hash", -1))
		if interest_hash < 0:
			interest_hash = _compute_universe_interest_hash(universe_id, frame)
		_last_universe_counters[universe_id] = {
			"counter": int(frame_entry.get("counter", -1)),
			"content_hash": int(frame_entry.get("content_hash", -1)),
			"interest_hash": interest_hash,
			"interest_offsets": _get_universe_interest_offsets_array(universe_id),
		}
		if not _debug_force_full_apply and int(_last_universe_interest_hashes.get(universe_id, -1)) == interest_hash:
			continue
		_last_universe_interest_hashes[universe_id] = interest_hash
		_native_visual_runtime.submit_universe_frame(universe_id, frame)

	var visual_frame: PackedFloat32Array = _native_visual_runtime.consume_latest_visual_frame()
	if not visual_frame.is_empty():
		var compact_result: Dictionary = {}
		if loader != null and light_apply_service != null:
			compact_result = _apply_visual_frame_updates(visual_frame, loader, light_apply_service, frame_delta_sec)
		else:
			compact_result = _apply_compact_universe_updates(visual_frame, apply_fixture_callback, pending_controls)
		fixtures_considered += int(compact_result.get("fixtures_considered", 0))
		updated += int(compact_result.get("updated", 0))
		skipped += int(compact_result.get("skipped", 0))

	return {
		"updated": updated,
		"skipped": skipped,
		"universes_changed": changed_frames.size(),
		"fixtures_considered": fixtures_considered,
		"controls": pending_controls,
	}


func _consume_dirty_universe_frames(receiver) -> Dictionary:
	var changed_frames: Dictionary = {}
	var dirty_universes: PackedInt32Array = receiver.get_dirty_universes()
	for universe_id in dirty_universes:
		if not _used_universes.has(int(universe_id)):
			continue
		var frame: PackedByteArray = receiver.consume_universe(int(universe_id))
		if frame.is_empty():
			continue
		var interest_hash: int = _compute_universe_interest_hash(int(universe_id), frame)
		var previous_state: Variant = _last_universe_counters.get(int(universe_id), {})
		var previous_counter: int = -1
		if previous_state is Dictionary:
			previous_counter = int((previous_state as Dictionary).get("counter", -1))
		changed_frames[int(universe_id)] = {
			"data": frame,
			"counter": previous_counter + 1,
			"content_hash": _compute_snapshot_hash(frame),
			"interest_hash": interest_hash,
		}
	return changed_frames

func _collect_changed_universe_frames_compat(receiver) -> Dictionary:
	var changed_frames: Dictionary = {}
	for universe_key in _used_universes.keys():
		var universe_id: int = int(universe_key)
		var metadata: Dictionary = receiver.get_universe_metadata(universe_id) if receiver.has_method("get_universe_metadata") else {}
		var counter: int = int(metadata.get("counter", -2))
		var content_hash: int = int(metadata.get("content_hash", -1))
		var previous_state: Variant = _last_universe_counters.get(universe_id, {"counter": -1, "content_hash": -1})
		var previous_hash: int = -1
		var previous_counter: int = -1
		if previous_state is Dictionary:
			var previous_state_dict: Dictionary = previous_state
			previous_hash = int(previous_state_dict.get("content_hash", -1))
			previous_counter = int(previous_state_dict.get("counter", -1))
		else:
			previous_counter = int(previous_state)
		if not _debug_force_full_apply and ((content_hash >= 0 and content_hash == previous_hash) or (content_hash < 0 and counter >= 0 and counter == previous_counter)):
			continue
		var frame: PackedByteArray = receiver.get_universe_data(universe_id)
		if frame.is_empty():
			continue
		changed_frames[universe_id] = {
			"data": frame,
			"counter": counter,
			"content_hash": content_hash,
		}
	return changed_frames

func _add_universe_interest_offsets(universe_id: int, offsets: PackedInt32Array) -> void:
	if not _universe_interest_offsets.has(universe_id):
		_universe_interest_offsets[universe_id] = {}
	var offset_map: Dictionary = _universe_interest_offsets.get(universe_id, {})
	for offset in offsets:
		if offset >= 0:
			offset_map[int(offset)] = true
	_universe_interest_offsets[universe_id] = offset_map

func _finalize_universe_interest_offsets() -> void:
	for universe_key in _universe_interest_offsets.keys():
		var offset_map: Dictionary = _universe_interest_offsets.get(universe_key, {})
		var offsets: Array = offset_map.keys()
		offsets.sort()
		var packed_offsets := PackedInt32Array()
		for offset in offsets:
			packed_offsets.append(int(offset))
		_universe_interest_offsets[int(universe_key)] = packed_offsets

func _get_universe_interest_offsets_array(universe_id: int) -> PackedInt32Array:
	return _universe_interest_offsets.get(universe_id, PackedInt32Array())

func _compute_universe_interest_hash(universe_id: int, frame: PackedByteArray) -> int:
	var offsets: PackedInt32Array = _get_universe_interest_offsets_array(universe_id)
	var hash_value: int = 2166136261
	for offset in offsets:
		var value: int = int(frame[offset]) if offset >= 0 and offset < frame.size() else 0
		hash_value = int((hash_value ^ value) * 16777619)
		hash_value = int((hash_value ^ offset) * 16777619)
	return hash_value


func _register_native_fixture_id(fixture_uuid: String) -> void:
	if _native_fixture_ids_by_uuid.has(fixture_uuid):
		return
	var fixture_id: int = _native_fixture_ids_by_uuid.size() + 1
	_native_fixture_ids_by_uuid[fixture_uuid] = fixture_id
	_native_fixture_uuids_by_id[fixture_id] = fixture_uuid
	_native_channel_values[fixture_uuid] = {}

func _register_native_visual_runtime_bindings() -> void:
	var native_bindings: Array = []
	for universe_key in _bindings_by_universe.keys():
		for binding in _bindings_by_universe.get(universe_key, []):
			if binding is Dictionary:
				_append_native_bindings_for_fixture(native_bindings, binding)
	_native_visual_runtime.set_fixture_bindings(native_bindings)

func _append_native_bindings_for_fixture(native_bindings: Array, binding: Dictionary) -> void:
	var fixture_uuid: String = str(binding.get("fixture_uuid", ""))
	var fixture_id: int = int(_native_fixture_ids_by_uuid.get(fixture_uuid, 0))
	if fixture_id <= 0:
		return
	_register_native_fixture_render_params(fixture_id, binding)
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_PAN, "pan_channel_index_0", "pan_fine_channel_index_0", "pan_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_TILT, "tilt_channel_index_0", "tilt_fine_channel_index_0", "tilt_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_DIMMER, "dimmer_channel_index_0", "dimmer_fine_channel_index_0", "dimmer_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_ZOOM, "zoom_channel_index_0", "zoom_fine_channel_index_0", "zoom_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_CYAN, "cyan_channel_index_0", "cyan_fine_channel_index_0", "cyan_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_MAGENTA, "magenta_channel_index_0", "magenta_fine_channel_index_0", "magenta_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_YELLOW, "yellow_channel_index_0", "yellow_fine_channel_index_0", "yellow_ultra_fine_channel_index_0")
	if int(binding.get("gobo1_channel_index_0", -1)) >= 0:
		_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO, "gobo1_channel_index_0", "gobo1_fine_channel_index_0", "gobo1_ultra_fine_channel_index_0")
	else:
		_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO, "gobo_channel_index_0", "gobo_fine_channel_index_0", "gobo_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO_INDEX, "gobo_index_channel_index_0", "gobo_index_fine_channel_index_0", "gobo_index_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO_ROTATION, "gobo_rotation_channel_index_0", "gobo_rotation_fine_channel_index_0", "gobo_rotation_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_PRISM, "prism_channel_index_0", "prism_fine_channel_index_0", "prism_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_PRISM_ROTATION, "prism_rotation_channel_index_0", "prism_rotation_fine_channel_index_0", "prism_rotation_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_STROBE, "strobe_channel_index_0", "strobe_fine_channel_index_0", "strobe_ultra_fine_channel_index_0")

func _first_fixture_photometric(_fixture_id: int, binding: Dictionary) -> Dictionary:
	var fixture_uuid: String = str(binding.get("fixture_uuid", ""))
	if _scene_registry == null or fixture_uuid.is_empty():
		return {}
	var entries: Variant = _scene_registry.get_anchor(fixture_uuid, "emitter_photometrics")
	if entries is Array and not entries.is_empty() and entries[0] is Dictionary:
		return entries[0]
	return {}

func _binding_has_color_temperature(fixture_uuid: String) -> bool:
	if _scene_registry == null:
		return false
	var entries: Variant = _scene_registry.get_anchor(fixture_uuid, "emitter_photometrics")
	if entries is Array and not entries.is_empty() and entries[0] is Dictionary:
		return bool((entries[0] as Dictionary).get("has_color_temperature", false))
	return false

func _register_native_fixture_render_params(fixture_id: int, binding: Dictionary) -> void:
	var fixture_uuid: String = str(binding.get("fixture_uuid", ""))
	var photometric: Dictionary = _first_fixture_photometric(fixture_id, binding)
	_native_visual_runtime.set_fixture_render_params(fixture_id, {
		"luminous_flux": float(photometric.get("luminous_flux", 10000.0)),
		"beam_angle_default": float(photometric.get("beam_angle", 25.0)),
		"zoom_min_deg": float(binding.get("zoom_physical_min_degrees", -1.0)),
		"zoom_max_deg": float(binding.get("zoom_physical_max_degrees", -1.0)),
		"has_zoom": int(binding.get("zoom_channel_index_0", -1)) >= 0,
		"color_temp_k": float(photometric.get("color_temperature", 5600.0)),
		"spot_multiplier": 1.0,
		"beam_multiplier": 20.0,
		"has_color_temperature": _binding_has_color_temperature(fixture_uuid),
	})

func _append_native_channel_binding(native_bindings: Array, binding: Dictionary, fixture_id: int, channel_type: int, coarse_key: String, fine_key: String, ultra_fine_key: String) -> void:
	var coarse_index: int = int(binding.get(coarse_key, -1))
	var fine_index: int = int(binding.get(fine_key, -1))
	var ultra_fine_index: int = int(binding.get(ultra_fine_key, -1))
	if coarse_index < 0 and fine_index < 0 and ultra_fine_index < 0:
		return
	var start_address: int = coarse_index
	var resolved_fine_address: int = fine_index
	var resolved_ultra_fine_address: int = ultra_fine_index
	if start_address < 0:
		start_address = fine_index if fine_index >= 0 else ultra_fine_index
		resolved_fine_address = ultra_fine_index if fine_index >= 0 else -1
		resolved_ultra_fine_address = -1
	native_bindings.append({
		"fixture_id": fixture_id,
		"universe_id": int(binding.get("artnet_universe_id", -1)),
		"channel_type": channel_type,
		"start_address": start_address,
		"fine_address": resolved_fine_address,
		"ultra_fine_address": resolved_ultra_fine_address,
		"bit_depth": 8 + (8 if resolved_fine_address >= 0 else 0) + (8 if resolved_ultra_fine_address >= 0 else 0),
	})

func _apply_visual_frame_updates(visual_frame: PackedFloat32Array, loader: Node, light_apply_service: FixtureLightApplyService, frame_delta_sec: float) -> Dictionary:
	var updated: int = 0
	var skipped: int = 0
	var fixtures_considered: int = 0
	var fixture_count: int = int(visual_frame[0])
	var base: int = 1
	for _i in range(fixture_count):
		if base + NATIVE_RENDER_READY_STRIDE > visual_frame.size():
			break
		var fixture_id: int = int(visual_frame[base])
		var fixture_uuid: String = str(_native_fixture_uuids_by_id.get(fixture_id, ""))
		if fixture_uuid.is_empty() or not _bound_fixture_ids.has(fixture_uuid):
			skipped += 1
			base += NATIVE_RENDER_READY_STRIDE
			continue
		light_apply_service.apply_visual_frame_to_fixture(loader, fixture_uuid, visual_frame, base, frame_delta_sec)
		fixtures_considered += 1
		updated += 1
		base += NATIVE_RENDER_READY_STRIDE
	return {"updated": updated, "skipped": skipped, "fixtures_considered": fixtures_considered}

func _apply_compact_universe_updates(compact: PackedFloat32Array, apply_fixture_callback: Callable, pending_controls: Array = []) -> Dictionary:
	var updated: int = 0
	var skipped: int = 0
	var fixtures_considered: int = 0
	var fixture_count: int = int(compact[0])
	var stride: int = _compact_fixture_stride(compact)
	var base: int = 1
	for _i in range(fixture_count):
		if base + NATIVE_COMPACT_STRIDE > compact.size():
			break
		var fixture_id: int = int(compact[base])
		var changed_mask: int = int(compact[base + 1])
		var fixture_uuid: String = str(_native_fixture_uuids_by_id.get(fixture_id, ""))
		if fixture_uuid.is_empty():
			base += stride
			continue
		_store_compact_fixture_channel_updates(fixture_uuid, compact, base, changed_mask)
		_store_render_ready_fixture_values(fixture_uuid, compact, base, stride)
		var result: Dictionary = _apply_native_fixture_updates(fixture_uuid, apply_fixture_callback, pending_controls)
		if not result.is_empty():
			fixtures_considered += 1
			updated += int(result.get("updated", 0))
			skipped += int(result.get("skipped", 0))
		base += stride
	return {"updated": updated, "skipped": skipped, "fixtures_considered": fixtures_considered}


func _compact_fixture_stride(compact: PackedFloat32Array) -> int:
	var fixture_count: int = int(compact[0]) if not compact.is_empty() else 0
	if fixture_count > 0 and compact.size() >= 1 + (fixture_count * NATIVE_RENDER_READY_STRIDE):
		return NATIVE_RENDER_READY_STRIDE
	return NATIVE_COMPACT_STRIDE

func _store_compact_fixture_channel_updates(fixture_uuid: String, compact: PackedFloat32Array, base: int, changed_mask: int) -> void:
	var values: Dictionary = _native_channel_values.get(fixture_uuid, {})
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_DIMMER, NATIVE_CHANNEL_DIMMER, compact[base + 2 + NATIVE_COMPACT_DIMMER])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_PAN, NATIVE_CHANNEL_PAN, compact[base + 2 + NATIVE_COMPACT_PAN])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_TILT, NATIVE_CHANNEL_TILT, compact[base + 2 + NATIVE_COMPACT_TILT])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_ZOOM, NATIVE_CHANNEL_ZOOM, compact[base + 2 + NATIVE_COMPACT_ZOOM])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_CYAN, NATIVE_CHANNEL_CYAN, compact[base + 2 + NATIVE_COMPACT_CYAN])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_MAGENTA, NATIVE_CHANNEL_MAGENTA, compact[base + 2 + NATIVE_COMPACT_MAGENTA])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_YELLOW, NATIVE_CHANNEL_YELLOW, compact[base + 2 + NATIVE_COMPACT_YELLOW])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_GOBO, NATIVE_CHANNEL_GOBO, compact[base + 2 + NATIVE_COMPACT_GOBO])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_GOBO_INDEX, NATIVE_CHANNEL_GOBO_INDEX, compact[base + 2 + NATIVE_COMPACT_GOBO_INDEX])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_GOBO_ROTATION, NATIVE_CHANNEL_GOBO_ROTATION, compact[base + 2 + NATIVE_COMPACT_GOBO_ROTATION])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_PRISM, NATIVE_CHANNEL_PRISM, compact[base + 2 + NATIVE_COMPACT_PRISM])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_PRISM_ROTATION, NATIVE_CHANNEL_PRISM_ROTATION, compact[base + 2 + NATIVE_COMPACT_PRISM_ROTATION])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_STROBE, NATIVE_CHANNEL_STROBE, compact[base + 2 + NATIVE_COMPACT_STROBE])
	_native_channel_values[fixture_uuid] = values

func _store_render_ready_fixture_values(fixture_uuid: String, compact: PackedFloat32Array, base: int, stride: int) -> void:
	if stride < NATIVE_RENDER_READY_STRIDE:
		_native_render_ready_values.erase(fixture_uuid)
		return
	_native_render_ready_values[fixture_uuid] = PackedFloat32Array([
		compact[base + 15],
		compact[base + 16],
		compact[base + 17],
		compact[base + 18],
		compact[base + 19],
		compact[base + 20],
		compact[base + 21],
		compact[base + 22],
		compact[base + 23],
	])

func _store_compact_channel_value(values: Dictionary, changed_mask: int, compact_index: int, channel_type: int, normalized_value: float) -> void:
	if (changed_mask & (1 << compact_index)) == 0:
		return
	var clamped_value: float = clamp(normalized_value, 0.0, 1.0)
	var raw_value: int = int(round(clamped_value * 255.0))
	var existing: Variant = values.get(channel_type, null)
	if existing is Dictionary:
		existing["normalized_value"] = clamped_value
		existing["raw_value"] = raw_value
		var bytes: PackedInt32Array = existing.get("bytes", PackedInt32Array())
		if bytes.size() == 1:
			bytes[0] = raw_value
		else:
			existing["bytes"] = PackedInt32Array([raw_value])
		return
	values[channel_type] = {
		"fixture_id": 0,
		"channel_type": channel_type,
		"normalized_value": clamped_value,
		"raw_value": raw_value,
		"resolution_bits": 8,
		"bytes": PackedInt32Array([raw_value]),
	}

func _store_native_channel_updates(native_updates: Array) -> Dictionary:
	var changed_fixture_uuids: Dictionary = {}
	for update in native_updates:
		if update is not Dictionary:
			continue
		var fixture_uuid: String = str(_native_fixture_uuids_by_id.get(int(update.get("fixture_id", 0)), ""))
		if fixture_uuid.is_empty():
			continue
		var channel_type: int = int(update.get("channel_type", 0))
		var values: Dictionary = _native_channel_values.get(fixture_uuid, {})
		values[channel_type] = update
		_native_channel_values[fixture_uuid] = values
		changed_fixture_uuids[fixture_uuid] = true
	return changed_fixture_uuids

func _apply_native_fixture_updates(fixture_uuid: String, apply_fixture_callback: Callable, pending_controls: Array = []) -> Dictionary:
	if fixture_uuid.is_empty() or not _bound_fixture_ids.has(fixture_uuid):
		return {}
	var fixture_plan: Dictionary = _fixture_apply_plans.get(fixture_uuid, {})
	var controls: Dictionary = _build_controls_from_native_values(fixture_plan, fixture_uuid)
	if not _has_any_capability(controls):
		return {"fixture_uuid": fixture_uuid, "updated": 0, "skipped": 0}
	var changed_capability_types: Dictionary = controls.get("changed_capability_types", {})
	if not _debug_force_full_apply and changed_capability_types.is_empty():
		return {"fixture_uuid": fixture_uuid, "updated": 0, "skipped": 1}
	_apply_fixture_with_compatibility_adapter(apply_fixture_callback, fixture_uuid, controls, pending_controls)
	return {"fixture_uuid": fixture_uuid, "updated": 1, "skipped": 0}

func _build_controls_from_native_values(fixture_plan: Dictionary, fixture_uuid: String) -> Dictionary:
	var output: Dictionary = _fixture_output_buffers.get(fixture_uuid, _build_fixture_output_buffer(fixture_plan.get("binding", {})))
	_fixture_output_buffers[fixture_uuid] = output
	var compact_values: PackedFloat32Array = output.get("compact_values", PackedFloat32Array())
	_reset_compact_controls(compact_values)
	var values: Dictionary = _native_channel_values.get(fixture_uuid, {})
	var binding: Dictionary = fixture_plan.get("binding", {})
	if _native_render_ready_values.has(fixture_uuid):
		output["render_ready_values"] = _native_render_ready_values.get(fixture_uuid, PackedFloat32Array())
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_PAN, "has_pan", "pan_norm", "pan_raw_value", "pan_resolution_bits", "pan_bytes", COMPACT_HAS_PAN, COMPACT_PAN_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_TILT, "has_tilt", "tilt_norm", "tilt_raw_value", "tilt_resolution_bits", "tilt_bytes", COMPACT_HAS_TILT, COMPACT_TILT_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_DIMMER, "has_dimmer", "dimmer_norm", "dimmer_raw_value", "dimmer_resolution_bits", "dimmer_bytes", COMPACT_HAS_DIMMER, COMPACT_DIMMER_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_ZOOM, "has_zoom", "zoom_norm", "zoom_raw_value", "zoom_resolution_bits", "zoom_bytes", COMPACT_HAS_ZOOM, COMPACT_ZOOM_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_CYAN, "has_cyan", "cyan_norm", "cyan_raw_value", "cyan_resolution_bits", "cyan_bytes", COMPACT_HAS_CYAN, COMPACT_CYAN_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_MAGENTA, "has_magenta", "magenta_norm", "magenta_raw_value", "magenta_resolution_bits", "magenta_bytes", COMPACT_HAS_MAGENTA, COMPACT_MAGENTA_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_YELLOW, "has_yellow", "yellow_norm", "yellow_raw_value", "yellow_resolution_bits", "yellow_bytes", COMPACT_HAS_YELLOW, COMPACT_YELLOW_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_GOBO, "has_gobo", "gobo_norm", "gobo_raw_value", "gobo_resolution_bits", "gobo_bytes", COMPACT_HAS_GOBO, COMPACT_GOBO_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_GOBO_INDEX, "has_gobo_index", "gobo_index_norm", "gobo_index_raw_value", "gobo_index_resolution_bits", "gobo_index_bytes", COMPACT_HAS_GOBO_INDEX, COMPACT_GOBO_INDEX_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_GOBO_ROTATION, "has_gobo_rotation", "gobo_rotation_norm", "gobo_rotation_raw_value", "gobo_rotation_resolution_bits", "gobo_rotation_bytes", COMPACT_HAS_GOBO_ROTATION, COMPACT_GOBO_ROTATION_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_PRISM, "has_prism", "prism_norm", "prism_raw_value", "prism_resolution_bits", "prism_bytes", COMPACT_HAS_PRISM, COMPACT_PRISM_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_PRISM_ROTATION, "has_prism_rotation", "prism_rotation_norm", "prism_rotation_raw_value", "prism_rotation_resolution_bits", "prism_rotation_bytes", COMPACT_HAS_PRISM_ROTATION, COMPACT_PRISM_ROTATION_NORM)
	_sync_native_value(output, compact_values, values, NATIVE_CHANNEL_STROBE, "has_strobe", "strobe_norm", "strobe_raw_value", "strobe_resolution_bits", "strobe_bytes", COMPACT_HAS_STROBE, COMPACT_STROBE_NORM)
	if bool(output.get("has_zoom", false)):
		output["has_zoom_physical_limits"] = bool(binding.get("has_zoom_physical_limits", false))
		output["zoom_physical_min_degrees"] = float(binding.get("zoom_physical_min_degrees", -1.0))
		output["zoom_physical_max_degrees"] = float(binding.get("zoom_physical_max_degrees", -1.0))
		compact_values[COMPACT_HAS_ZOOM_LIMITS] = 1.0 if bool(output.get("has_zoom_physical_limits", false)) else 0.0
		compact_values[COMPACT_ZOOM_MIN_DEG] = float(output.get("zoom_physical_min_degrees", -1.0))
		compact_values[COMPACT_ZOOM_MAX_DEG] = float(output.get("zoom_physical_max_degrees", -1.0))
	if bool(output.get("has_gobo", false)):
		output["gobo_slots"] = binding.get("gobo1_slots", binding.get("gobo_slots", []))
		output["gobo_ranges"] = binding.get("gobo1_ranges", binding.get("gobo_ranges", []))
		output["gobo_wheel_name"] = str(binding.get("gobo1_wheel_name", binding.get("gobo_wheel_name", "")))
		output["gobo_wheel_number"] = int(binding.get("gobo_wheel_number", 0))
	output["compact_values"] = compact_values
	output["changed_capability_types"] = _filter_unchanged_compact_controls(fixture_uuid, compact_values)
	output["metadata"] = fixture_plan.get("metadata", output.get("metadata", {}))
	return output

func _sync_native_value(output: Dictionary, compact_values: PackedFloat32Array, values: Dictionary, channel_type: int, has_key: String, norm_key: String, raw_key: String, resolution_key: String, bytes_key: String, compact_has_index: int, compact_value_index: int) -> void:
	var has_value: bool = values.has(channel_type)
	output[has_key] = has_value
	if not has_value:
		output[norm_key] = 0.0
		return
	var value: Dictionary = values.get(channel_type, {})
	var normalized_value: float = float(value.get("normalized_value", 0.0))
	output[norm_key] = normalized_value
	output[raw_key] = int(value.get("raw_value", 0))
	output[resolution_key] = int(value.get("resolution_bits", 8))
	output[bytes_key] = value.get("bytes", PackedInt32Array())
	compact_values[compact_has_index] = 1.0
	if compact_value_index >= 0:
		compact_values[compact_value_index] = normalized_value

func _reset_compact_controls(compact_values: PackedFloat32Array) -> void:
	compact_values.resize(COMPACT_CONTROL_SIZE)
	for index in range(COMPACT_CONTROL_SIZE):
		compact_values[index] = 0.0
	compact_values[COMPACT_ZOOM_MIN_DEG] = -1.0
	compact_values[COMPACT_ZOOM_MAX_DEG] = -1.0

func _apply_binding_frame(binding: Dictionary, frame: PackedByteArray, apply_fixture_callback: Callable, pending_controls: Array = []) -> Dictionary:
	var fixture_uuid: String = str(binding.get("fixture_uuid", ""))
	if fixture_uuid.is_empty() or not _bound_fixture_ids.has(fixture_uuid):
		return {}
	var fixture_plan: Dictionary = _fixture_apply_plans.get(fixture_uuid, {})
	if fixture_plan.is_empty():
		fixture_plan = _build_fixture_apply_plan(binding)
		_fixture_apply_plans[fixture_uuid] = fixture_plan
	if not _fixture_output_buffers.has(fixture_uuid):
		_fixture_output_buffers[fixture_uuid] = _build_fixture_output_buffer(binding)
	var snapshot: PackedByteArray = _extract_snapshot_for_fixture(fixture_uuid, frame)
	if snapshot.is_empty():
		var controls_without_cache: Dictionary = _build_controls_for_plan(fixture_plan, frame, fixture_uuid)
		if not _has_any_capability(controls_without_cache):
			return {"fixture_uuid": fixture_uuid, "updated": 0, "skipped": 0}
		_apply_fixture_with_compatibility_adapter(apply_fixture_callback, fixture_uuid, controls_without_cache, pending_controls)
		return {"fixture_uuid": fixture_uuid, "updated": 1, "skipped": 0}
	var snapshot_hash: int = _compute_snapshot_hash(snapshot)
	var previous_state: Dictionary = _fixture_snapshot_cache.get(fixture_uuid, {})
	if not _debug_force_full_apply and _snapshot_is_unchanged(previous_state, snapshot_hash, snapshot):
		return {"fixture_uuid": fixture_uuid, "updated": 0, "skipped": 1}

	var controls: Dictionary = _build_controls_for_plan(fixture_plan, frame, fixture_uuid)
	if not _has_any_capability(controls):
		return {"fixture_uuid": fixture_uuid, "updated": 0, "skipped": 0}
	_fixture_snapshot_cache[fixture_uuid] = {
		"hash": snapshot_hash,
		"snapshot": snapshot,
	}
	_apply_fixture_with_compatibility_adapter(apply_fixture_callback, fixture_uuid, controls, pending_controls)
	return {"fixture_uuid": fixture_uuid, "updated": 1, "skipped": 0}

func _build_fixture_apply_plan(binding: Dictionary) -> Dictionary:
	return {
		"binding": binding,
		"metadata": binding.get("metadata", {}),
	}

func _build_fixture_output_buffer(binding: Dictionary) -> Dictionary:
	return {
		"compact_values": _build_empty_compact_controls(),
		"capabilities": {},
		"metadata": binding.get("metadata", {}),
	}

func _build_empty_compact_controls() -> PackedFloat32Array:
	var compact_values := PackedFloat32Array()
	_reset_compact_controls(compact_values)
	return compact_values

func _build_controls_for_plan(fixture_plan: Dictionary, _frame: PackedByteArray, fixture_uuid: String) -> Dictionary:
	return _build_controls_from_native_values(fixture_plan, fixture_uuid)

func _apply_fixture_with_compatibility_adapter(apply_fixture_callback: Callable, fixture_uuid: String, controls: Dictionary, pending_controls: Array = []) -> void:
	# Temporary compatibility adapter for incremental migration.
	# Old callback contract receives (fixture_uuid, controls).
	# New contract may receive a precompiled output envelope.
	if apply_fixture_callback.is_null():
		# Threaded DMX drains hold the runtime mutex while applying these shared buffers.
		pending_controls.append({"fixture_uuid": fixture_uuid, "controls": controls})
		return
	apply_fixture_callback.call(fixture_uuid, controls)

func _snapshot_is_unchanged(previous_state: Dictionary, snapshot_hash: int, snapshot: PackedByteArray) -> bool:
	if previous_state.is_empty():
		return false
	if int(previous_state.get("hash", -1)) != snapshot_hash:
		return false
	var previous_snapshot: PackedByteArray = previous_state.get("snapshot", PackedByteArray())
	return previous_snapshot == snapshot

func _extract_snapshot_for_fixture(fixture_uuid: String, frame: PackedByteArray) -> PackedByteArray:
	var offsets: PackedInt32Array = _fixture_channel_offsets.get(fixture_uuid, PackedInt32Array())
	var snapshot := PackedByteArray()
	for offset in offsets:
		if offset < 0 or offset >= frame.size():
			snapshot.append(0)
		else:
			snapshot.append(frame[offset])
	return snapshot

func _compute_snapshot_hash(snapshot: PackedByteArray) -> int:
	var hash_value: int = 2166136261
	for value in snapshot:
		hash_value = int((hash_value ^ int(value)) * 16777619)
	return hash_value

func _collect_used_channel_offsets(binding: Dictionary) -> PackedInt32Array:
	var offsets := PackedInt32Array()
	var used_offsets := {}
	for key in _collect_direct_channel_offset_keys():
		var offset: int = int(binding.get(key, -1))
		if offset >= 0:
			used_offsets[offset] = true
	var channel_bindings: Array = binding.get("channel_bindings", [])
	for channel_binding in channel_bindings:
		if channel_binding is not Dictionary:
			continue
		var offset: int = int(channel_binding.get("dmx_offset", -1))
		var fine_offset: int = int(channel_binding.get("dmx_fine_offset", -1))
		if offset >= 0:
			used_offsets[offset] = true
		if fine_offset >= 0:
			used_offsets[fine_offset] = true
	var sorted_offsets: Array = used_offsets.keys()
	sorted_offsets.sort()
	for offset in sorted_offsets:
		offsets.append(int(offset))
	return offsets

func _collect_direct_channel_offset_keys() -> PackedStringArray:
	return PackedStringArray([
		"dimmer_channel_index_0", "dimmer_fine_channel_index_0", "dimmer_ultra_fine_channel_index_0",
		"pan_channel_index_0", "pan_fine_channel_index_0", "pan_ultra_fine_channel_index_0",
		"tilt_channel_index_0", "tilt_fine_channel_index_0", "tilt_ultra_fine_channel_index_0",
		"zoom_channel_index_0", "zoom_fine_channel_index_0", "zoom_ultra_fine_channel_index_0",
		"cyan_channel_index_0", "cyan_fine_channel_index_0", "cyan_ultra_fine_channel_index_0",
		"magenta_channel_index_0", "magenta_fine_channel_index_0", "magenta_ultra_fine_channel_index_0",
		"yellow_channel_index_0", "yellow_fine_channel_index_0", "yellow_ultra_fine_channel_index_0",
		"gobo_channel_index_0", "gobo_fine_channel_index_0", "gobo_ultra_fine_channel_index_0",
		"gobo_index_channel_index_0", "gobo_index_fine_channel_index_0", "gobo_index_ultra_fine_channel_index_0",
		"gobo_rotation_channel_index_0", "gobo_rotation_fine_channel_index_0", "gobo_rotation_ultra_fine_channel_index_0",
		"gobo1_channel_index_0", "gobo1_fine_channel_index_0", "gobo1_ultra_fine_channel_index_0",
		"prism_channel_index_0", "prism_fine_channel_index_0", "prism_ultra_fine_channel_index_0",
		"prism_rotation_channel_index_0", "prism_rotation_fine_channel_index_0", "prism_rotation_ultra_fine_channel_index_0",
		"strobe_channel_index_0", "strobe_fine_channel_index_0", "strobe_ultra_fine_channel_index_0",
	])

func _filter_unchanged_compact_controls(fixture_uuid: String, compact_values: PackedFloat32Array) -> Dictionary:
	var changed_capability_types: Dictionary = {}
	var previous_state: PackedFloat32Array = _fixture_capability_state_cache.get(fixture_uuid, PackedFloat32Array())
	if _debug_force_full_apply or not _compact_control_state_matches(previous_state, compact_values):
		_add_changed_compact_capability_types(changed_capability_types, previous_state, compact_values)
	_fixture_capability_state_cache[fixture_uuid] = compact_values.duplicate()
	return changed_capability_types

func _add_changed_compact_capability_types(changed_capability_types: Dictionary, previous_state: PackedFloat32Array, current_state: PackedFloat32Array) -> void:
	_add_changed_compact_capability_type(changed_capability_types, "pan_tilt", previous_state, current_state, [COMPACT_HAS_PAN, COMPACT_PAN_NORM, COMPACT_HAS_TILT, COMPACT_TILT_NORM])
	_add_changed_compact_capability_type(changed_capability_types, "dimmer", previous_state, current_state, [COMPACT_HAS_DIMMER, COMPACT_DIMMER_NORM, COMPACT_HAS_ZOOM, COMPACT_ZOOM_NORM, COMPACT_HAS_ZOOM_LIMITS, COMPACT_ZOOM_MIN_DEG, COMPACT_ZOOM_MAX_DEG])
	_add_changed_compact_capability_type(changed_capability_types, "color_wheel", previous_state, current_state, [COMPACT_HAS_CYAN, COMPACT_CYAN_NORM, COMPACT_HAS_MAGENTA, COMPACT_MAGENTA_NORM, COMPACT_HAS_YELLOW, COMPACT_YELLOW_NORM])
	_add_changed_compact_capability_type(changed_capability_types, "gobo", previous_state, current_state, [COMPACT_HAS_GOBO, COMPACT_GOBO_NORM, COMPACT_HAS_GOBO_INDEX, COMPACT_GOBO_INDEX_NORM, COMPACT_HAS_GOBO_ROTATION, COMPACT_GOBO_ROTATION_NORM])
	_add_changed_compact_capability_type(changed_capability_types, "prism", previous_state, current_state, [COMPACT_HAS_PRISM, COMPACT_PRISM_NORM, COMPACT_HAS_PRISM_ROTATION, COMPACT_PRISM_ROTATION_NORM])
	_add_changed_compact_capability_type(changed_capability_types, "strobe", previous_state, current_state, [COMPACT_HAS_STROBE, COMPACT_STROBE_NORM])

func _add_changed_compact_capability_type(changed_capability_types: Dictionary, capability_type: String, previous_state: PackedFloat32Array, current_state: PackedFloat32Array, indexes: Array) -> void:
	if previous_state.size() != current_state.size():
		changed_capability_types[capability_type] = true
		return
	for index in indexes:
		if not is_equal_approx(float(previous_state[int(index)]), float(current_state[int(index)])):
			changed_capability_types[capability_type] = true
			return

func _compact_control_state_matches(previous_state: Variant, current_state: PackedFloat32Array) -> bool:
	if previous_state is not PackedFloat32Array:
		return false
	var previous: PackedFloat32Array = previous_state
	if previous.size() != current_state.size():
		return false
	for index in range(current_state.size()):
		if not is_equal_approx(float(previous[index]), float(current_state[index])):
			return false
	return true

func _has_any_capability(controls: Dictionary) -> bool:
	var compact_values: PackedFloat32Array = controls.get("compact_values", PackedFloat32Array())
	if compact_values.size() == COMPACT_CONTROL_SIZE:
		return compact_values[COMPACT_HAS_PAN] > 0.5 or compact_values[COMPACT_HAS_TILT] > 0.5 or compact_values[COMPACT_HAS_DIMMER] > 0.5 or compact_values[COMPACT_HAS_ZOOM] > 0.5 or compact_values[COMPACT_HAS_CYAN] > 0.5 or compact_values[COMPACT_HAS_MAGENTA] > 0.5 or compact_values[COMPACT_HAS_YELLOW] > 0.5 or compact_values[COMPACT_HAS_GOBO] > 0.5 or compact_values[COMPACT_HAS_GOBO_INDEX] > 0.5 or compact_values[COMPACT_HAS_GOBO_ROTATION] > 0.5 or compact_values[COMPACT_HAS_PRISM] > 0.5 or compact_values[COMPACT_HAS_PRISM_ROTATION] > 0.5 or compact_values[COMPACT_HAS_STROBE] > 0.5
	var capabilities: Dictionary = controls.get("capabilities", {})
	for key in capabilities.keys():
		var items: Array = capabilities.get(key, [])
		if not items.is_empty():
			return true
	return false

func get_bound_count() -> int:
	return _bound_fixture_ids.size()

func get_unbound_count() -> int:
	return _unbound.size()

func get_unbound_preview() -> PackedStringArray:
	var lines := PackedStringArray()
	for index in range(min(MAX_UNBOUND_PREVIEW, _unbound.size())):
		var row: Dictionary = _unbound[index]
		lines.append(_format_unbound_preview_line(row))
	return lines

func _collect_known_fixture_uuids() -> PackedStringArray:
	var seen_fixture_uuids: Dictionary = {}
	for fixture_uuid in _fixture_patch_lookup.keys():
		_add_seen_fixture_uuid(seen_fixture_uuids, str(fixture_uuid))
	for binding in _bindings:
		if binding is Dictionary:
			_add_seen_fixture_uuid(seen_fixture_uuids, str(binding.get("fixture_uuid", "")))
	for row in _unbound:
		if row is Dictionary:
			_add_seen_fixture_uuid(seen_fixture_uuids, str(row.get("fixture_uuid", "")))
	var fixture_uuids := PackedStringArray()
	for fixture_uuid in seen_fixture_uuids.keys():
		fixture_uuids.append(str(fixture_uuid))
	return fixture_uuids

func _add_seen_fixture_uuid(seen_fixture_uuids: Dictionary, fixture_uuid: String) -> void:
	if fixture_uuid.strip_edges().is_empty():
		return
	seen_fixture_uuids[fixture_uuid] = true

func _build_fixture_inspection_row(fixture_uuid: String) -> Dictionary:
	var patch: Dictionary = _fixture_patch_lookup.get(fixture_uuid, {})
	var binding: Dictionary = _find_binding_for_fixture(fixture_uuid)
	var unbound: Dictionary = _find_unbound_for_fixture(fixture_uuid)
	var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid) if _scene_registry != null and not fixture_uuid.is_empty() else null
	return {
		"fixture_uuid": fixture_uuid,
		"fixture_name": _resolve_fixture_name(binding, patch, fixture_node),
		"fixture_id": _resolve_fixture_id(binding, patch, fixture_node),
		"fixture_type": _resolve_fixture_type(binding, patch, fixture_node),
		"universe": _resolve_fixture_universe(binding, patch),
		"address": _resolve_fixture_address(binding, patch),
		"binding_status": _resolve_fixture_binding_status(binding, unbound, patch),
		"binding_detail": _resolve_fixture_binding_detail(binding, unbound, patch),
	}

func _find_binding_for_fixture(fixture_uuid: String) -> Dictionary:
	for binding in _bindings:
		if binding is Dictionary and str(binding.get("fixture_uuid", "")) == fixture_uuid:
			return binding
	return {}

func _find_unbound_for_fixture(fixture_uuid: String) -> Dictionary:
	for row in _unbound:
		if row is Dictionary and str(row.get("fixture_uuid", "")) == fixture_uuid:
			return row
	return {}

func _resolve_fixture_universe(binding: Dictionary, patch: Dictionary) -> String:
	var universe: String = _first_non_empty_string(patch, ["universe", "mvr_universe"])
	if universe.is_empty():
		universe = _first_non_empty_string(binding, ["universe", "mvr_universe", "artnet_universe_id"])
	return universe

func _resolve_fixture_address(binding: Dictionary, patch: Dictionary) -> String:
	var address: String = _first_non_empty_string(patch, ["address", "mvr_address", "dmx_address"])
	if address.is_empty():
		address = _first_non_empty_string(binding, ["address", "mvr_address", "dmx_address"])
	return address

func _resolve_fixture_binding_status(binding: Dictionary, unbound: Dictionary, patch: Dictionary) -> String:
	var universe: String = _resolve_fixture_universe(binding, patch)
	var address: String = _resolve_fixture_address(binding, patch)
	var is_patched: bool = not universe.is_empty() and not address.is_empty()
	if not binding.is_empty():
		return "Patched / Bound" if is_patched else "Bound"
	if not unbound.is_empty():
		return "Patched / Unbound" if is_patched else "Unpatched / Unbound"
	if not is_patched:
		return "Unpatched"
	return "Patched / Not bound"

func _resolve_fixture_binding_detail(binding: Dictionary, unbound: Dictionary, patch: Dictionary) -> String:
	if not binding.is_empty():
		var artnet_universe: String = _first_non_empty_string(binding, ["artnet_universe_id"])
		return "Bound to Art-Net universe %s" % artnet_universe if not artnet_universe.is_empty() else "Bound to DMX controls"
	if not unbound.is_empty():
		return _format_unbound_reason(str(unbound.get("reason", "unspecified")))
	var universe: String = _resolve_fixture_universe(binding, patch)
	var address: String = _resolve_fixture_address(binding, patch)
	if universe.is_empty() or address.is_empty():
		return "Missing MVR universe or address"
	return "No DMX binding has been built for this fixture"

func _sort_fixture_inspection_rows(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = str(a.get("fixture_name", "")).to_lower()
	var b_name: String = str(b.get("fixture_name", "")).to_lower()
	if a_name == b_name:
		return str(a.get("fixture_uuid", "")) < str(b.get("fixture_uuid", ""))
	return a_name < b_name

func _format_unbound_preview_line(row: Dictionary) -> String:
	var parts: PackedStringArray = _resolve_fixture_display_parts(row)
	parts.append(_format_unbound_reason(str(row.get("reason", "unspecified"))))
	return " · ".join(parts)

func _resolve_fixture_display_parts(row: Dictionary) -> PackedStringArray:
	var fixture_uuid: String = str(row.get("fixture_uuid", ""))
	var patch: Dictionary = _fixture_patch_lookup.get(fixture_uuid, {})
	var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid) if _scene_registry != null and not fixture_uuid.is_empty() else null
	var parts := PackedStringArray()
	parts.append(_resolve_fixture_display_label(row, patch, fixture_node, fixture_uuid))

	var fixture_name: String = _resolve_fixture_name(row, patch, fixture_node)
	var fixture_id: String = _resolve_fixture_id(row, patch, fixture_node)
	if not fixture_name.is_empty() and not fixture_id.is_empty():
		parts.append("Fixture ID %s" % fixture_id)

	return parts

func _resolve_fixture_display_label(row: Dictionary, patch: Dictionary, fixture_node: Node, fixture_uuid: String) -> String:
	var fixture_name: String = _resolve_fixture_name(row, patch, fixture_node)
	if not fixture_name.is_empty():
		return fixture_name

	var fixture_id: String = _resolve_fixture_id(row, patch, fixture_node)
	if not fixture_id.is_empty():
		return "Fixture ID %s" % fixture_id

	var fixture_type: String = _resolve_fixture_type(row, patch, fixture_node)
	if not fixture_type.is_empty():
		return fixture_type

	var address_label: String = _resolve_fixture_address_label(row, patch)
	if not address_label.is_empty():
		return address_label

	return _format_fixture_uuid_fallback(fixture_uuid)

func _build_fixture_patch_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	if _loader == null or not _loader.has_method("get_fixtures_patch"):
		return lookup

	var patches: Array = _loader.get_fixtures_patch()
	for patch_value in patches:
		if patch_value is not Dictionary:
			continue
		var patch: Dictionary = patch_value
		var fixture_uuid: String = str(patch.get("fixture_uuid", ""))
		if fixture_uuid.is_empty():
			continue
		lookup[fixture_uuid] = patch
	return lookup

func _resolve_fixture_name(row: Dictionary, patch: Dictionary, fixture_node: Node) -> String:
	var fixture_name: String = _first_non_empty_string(row, ["fixture_name", "fixture_label", "name", "label"])
	if fixture_name.is_empty():
		fixture_name = _first_non_empty_string(patch, ["fixture_name", "fixture_label", "name", "label"])
	if fixture_name.is_empty() and fixture_node != null:
		fixture_name = _first_non_empty_node_meta(fixture_node, ["peraviz_fixture_name", "fixture_name", "name"])
	if fixture_name.is_empty() and fixture_node != null:
		fixture_name = _clean_fixture_node_name(fixture_node.name)
	return fixture_name

func _resolve_fixture_id(row: Dictionary, patch: Dictionary, fixture_node: Node) -> String:
	var fixture_id: String = _first_non_empty_string(row, ["fixture_id", "fixture_number", "fixture_no", "unit_number", "mvr_fixture_id"])
	if fixture_id.is_empty():
		fixture_id = _first_non_empty_string(patch, ["fixture_id", "fixture_number", "fixture_no", "unit_number", "mvr_fixture_id"])
	if fixture_id.is_empty() and fixture_node != null:
		fixture_id = _first_non_empty_node_meta(fixture_node, ["peraviz_fixture_id", "peraviz_fixture_number", "fixture_id", "fixture_number", "unit_number"])
	return fixture_id

func _resolve_fixture_type(row: Dictionary, patch: Dictionary, fixture_node: Node) -> String:
	var fixture_type: String = _first_non_empty_string(row, ["fixture_type", "type", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty():
		fixture_type = _first_non_empty_string(patch, ["fixture_type", "type", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty() and fixture_node != null:
		fixture_type = _first_non_empty_node_meta(fixture_node, ["peraviz_fixture_type", "fixture_type", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty():
		fixture_type = _gdtf_path_basename(_first_non_empty_string(row, ["gdtf_path"]))
	if fixture_type.is_empty():
		fixture_type = _gdtf_path_basename(_first_non_empty_string(patch, ["gdtf_path"]))
	return fixture_type

func _resolve_fixture_address_label(row: Dictionary, patch: Dictionary) -> String:
	var universe: String = _first_non_empty_string(row, ["universe", "mvr_universe", "artnet_universe_id"])
	if universe.is_empty():
		universe = _first_non_empty_string(patch, ["universe", "mvr_universe", "artnet_universe_id"])

	var address: String = _first_non_empty_string(row, ["address", "mvr_address", "dmx_address"])
	if address.is_empty():
		address = _first_non_empty_string(patch, ["address", "mvr_address", "dmx_address"])

	if not universe.is_empty() and not address.is_empty():
		return "Universe %s / Address %s" % [universe, address]
	if not universe.is_empty():
		return "Universe %s" % universe
	if not address.is_empty():
		return "Address %s" % address
	return ""

func _first_non_empty_string(source: Dictionary, keys: Array) -> String:
	for key in keys:
		if not source.has(key):
			continue
		var value: String = str(source.get(key, "")).strip_edges()
		if value.is_empty() or value == "-1":
			continue
		return value
	return ""

func _first_non_empty_node_meta(node: Node, keys: Array) -> String:
	for key in keys:
		if not node.has_meta(key):
			continue
		var value: String = str(node.get_meta(key, "")).strip_edges()
		if value.is_empty() or value == "-1":
			continue
		return value
	return ""

func _clean_fixture_node_name(node_name: String) -> String:
	var value: String = node_name.strip_edges()
	if value.begins_with("fixture_") and value.length() > "fixture_".length():
		value = value.substr("fixture_".length()).strip_edges()
	if value == "fixture" or value == "Fixture":
		return ""
	return value

func _gdtf_path_basename(gdtf_path: String) -> String:
	var value: String = gdtf_path.strip_edges()
	if value.is_empty():
		return ""
	return value.get_file().get_basename()

func _format_fixture_uuid_fallback(fixture_uuid: String) -> String:
	if fixture_uuid.strip_edges().is_empty():
		return "Unknown fixture"
	return "Fixture UUID %s" % fixture_uuid

func _format_unbound_reason(reason: String) -> String:
	var value: String = reason.strip_edges()
	if value.is_empty():
		return "Unspecified"
	if value == "No Dimmer/Pan/Tilt/Zoom/CMY/Gobo attributes found in mode DMX channels":
		return "No controllable Dimmer/Pan/Tilt/Zoom/CMY/Gobo attributes found in the selected DMX mode"
	return value.substr(0, 1).to_upper() + value.substr(1)

func _build_summary(universe_offset: int) -> Dictionary:
	return {
		"bound": get_bound_count(),
		"unbound": get_unbound_count(),
		"unbound_preview": get_unbound_preview(),
		"universe_offset": universe_offset,
	}
