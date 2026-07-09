extends RefCounted
class_name DmxFixtureRuntime

const MAX_UNBOUND_PREVIEW: int = 8
const FORCE_COARSE_ONLY_DMX_READ: bool = false

const GoboVectorizationCacheScript = preload("res://scripts/gobo_vectorization/gobo_vectorization_cache.gd")
const DmxGoboRangeResolverScript = preload("res://scripts/dmx_gobo_range_resolver.gd")
const SectionedVisualFrameApplierScript = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")

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

# Canonical PeravizVisualRuntime row after the leading fixture count: fixture id, channel mask, visual mask, 13 compact controls, then 9 render-ready values.
const NATIVE_VISUAL_FRAME_HEADER_COUNT: int = 3
const NATIVE_VISUAL_CHANNEL_COUNT: int = 13
const NATIVE_VISUAL_RENDER_VALUE_COUNT: int = 9
const NATIVE_COMPACT_STRIDE: int = 15
const NATIVE_RENDER_READY_STRIDE: int = NATIVE_VISUAL_FRAME_HEADER_COUNT + NATIVE_VISUAL_CHANNEL_COUNT + NATIVE_VISUAL_RENDER_VALUE_COUNT
const NATIVE_VISUAL_MASK_OFFSET: int = 2
const NATIVE_VALUES_OFFSET: int = NATIVE_VISUAL_FRAME_HEADER_COUNT
const NATIVE_RENDER_VALUES_OFFSET: int = NATIVE_VISUAL_FRAME_HEADER_COUNT + NATIVE_VISUAL_CHANNEL_COUNT

const VISUAL_CHANGE_TRANSFORM: int = 1 << 0
const VISUAL_CHANGE_DIMMER: int = 1 << 1
const VISUAL_CHANGE_COLOR: int = 1 << 2
const VISUAL_CHANGE_ZOOM: int = 1 << 3
const VISUAL_CHANGE_GOBO: int = 1 << 4
const VISUAL_CHANGE_GOBO_ROTATION: int = 1 << 5
const VISUAL_CHANGE_MATERIAL: int = 1 << 8
const VISUAL_CHANGE_BEAM_TOPOLOGY: int = 1 << 9

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
var _native_visual_runtime = null
var _native_visual_runtime_available: bool = false
var _native_bindings_count: int = 0
var _last_visual_frame_size: int = 0
var _last_visual_mask_counts: Dictionary = {}
var _native_fixture_ids_by_uuid: Dictionary = {}
var _native_fixture_uuids_by_id: Dictionary = {}
var _native_channel_values: Dictionary = {}
var _native_render_ready_values: Dictionary = {}
var _static_gobo_controls_by_fixture: Dictionary = {}
var _live_visual_gobo_controls_by_fixture: Dictionary = {}
var _live_gobo_diagnostics_by_fixture: Dictionary = {}
var _fixture_apply_plans: Dictionary = {}
var _fixture_output_buffers: Dictionary = {}
var _used_universes: Dictionary = {}
var _bindings_by_universe: Dictionary = {}
var _last_universe_counters: Dictionary = {}
var _cached_universe_frames: Dictionary = {}
var _universe_interest_offsets: Dictionary = {}
var _last_universe_interest_hashes: Dictionary = {}
var _compiled_used_universes: Dictionary = {}
var _compiled_relevant_offsets_by_universe: Dictionary = {}
var _native_setup_summary: Dictionary = {}
var _native_live_diagnostics: Dictionary = {}
var _native_live_diagnostics_logged: bool = false
var _fixture_time_tick_flags: Dictionary = {}
var _fixture_row_provider: FixtureRowProvider = null
var _time_tick_fixture_ids := PackedStringArray()
var _gobo_vectorization_cache: GoboVectorizationCache = null
var _debug_force_full_apply: bool = false
var _sectioned_visual_frame_applier: SectionedVisualFrameApplier = null
var _runtime_universe_offset: int = -1

func configure(loader, scene_registry: SceneRegistry, fixture_row_provider: FixtureRowProvider = null) -> void:
	_loader = loader
	_scene_registry = scene_registry
	_fixture_row_provider = fixture_row_provider
	_gobo_vectorization_cache = GoboVectorizationCacheScript.new()
	_initialize_native_visual_runtime()
	_sectioned_visual_frame_applier = SectionedVisualFrameApplierScript.new()
	if _native_visual_runtime != null and _native_visual_runtime.has_method("get_visual_frame_schema"):
		_sectioned_visual_frame_applier.install_schema(_native_visual_runtime.get_visual_frame_schema())

func rebuild(universe_offset: int) -> Dictionary:
	_runtime_universe_offset = universe_offset
	_bindings.clear()
	_unbound.clear()
	_fixture_patch_lookup.clear()
	_fixture_nodes.clear()
	_bound_fixture_ids.clear()
	_fixture_channel_offsets.clear()
	_fixture_snapshot_cache.clear()
	_fixture_capability_state_cache.clear()
	_last_visual_frame_size = 0
	_last_visual_mask_counts.clear()
	if _native_visual_runtime != null:
		_native_visual_runtime.clear()
	_native_fixture_ids_by_uuid.clear()
	_native_fixture_uuids_by_id.clear()
	_native_channel_values.clear()
	_native_render_ready_values.clear()
	_static_gobo_controls_by_fixture.clear()
	_live_visual_gobo_controls_by_fixture.clear()
	_live_gobo_diagnostics_by_fixture.clear()
	_fixture_apply_plans.clear()
	_fixture_output_buffers.clear()
	_used_universes.clear()
	_bindings_by_universe.clear()
	_last_universe_counters.clear()
	_cached_universe_frames.clear()
	_universe_interest_offsets.clear()
	_last_universe_interest_hashes.clear()
	_compiled_used_universes.clear()
	_compiled_relevant_offsets_by_universe.clear()
	_native_setup_summary.clear()
	_native_live_diagnostics.clear()
	_native_live_diagnostics_logged = false
	_fixture_time_tick_flags.clear()
	_time_tick_fixture_ids = PackedStringArray()

	if not _native_visual_runtime_available:
		push_error("PeravizVisualRuntime is required for live DMX visualization but is not available.")
		return {
			"bound": 0,
			"unbound": 0,
			"unbound_preview": PackedStringArray(),
		}

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
		_static_gobo_controls_by_fixture[fixture_uuid] = _build_static_gobo_controls(binding)
		_live_visual_gobo_controls_by_fixture[fixture_uuid] = _build_cached_live_gobo_controls(_static_gobo_controls_by_fixture[fixture_uuid])
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

func _initialize_native_visual_runtime() -> void:
	_native_visual_runtime_available = ClassDB.class_exists("PeravizVisualRuntime")
	if not _native_visual_runtime_available:
		_native_visual_runtime = null
		return
	_native_visual_runtime = ClassDB.instantiate("PeravizVisualRuntime")
	_native_visual_runtime_available = _native_visual_runtime != null

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

func is_native_visual_runtime_available() -> bool:
	return _native_visual_runtime_available and _native_visual_runtime != null

func get_time_tick_fixture_ids() -> PackedStringArray:
	if is_native_visual_runtime_available():
		return PackedStringArray()
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

func _collect_dmx(receiver, _apply_fixture_callback: Callable, loader: Node = null, light_apply_service: FixtureLightApplyService = null, frame_delta_sec: float = 0.0) -> Dictionary:
	if not _native_visual_runtime_available or _native_visual_runtime == null:
		push_error("PeravizVisualRuntime is required for live DMX visualization but is not available.")
		return {"updated": 0, "skipped": 0, "universes_changed": 0, "fixtures_considered": 0, "controls": [], "native_visual_runtime_available": false}
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
	var submitted_universes: int = 0
	for universe_key in changed_frames.keys():
		var universe_id: int = int(universe_key)
		if not _compiled_used_universes.has(universe_id):
			continue
		var frame_entry: Dictionary = changed_frames.get(universe_key, {})
		var frame: PackedByteArray = frame_entry.get("data", PackedByteArray())
		if frame.is_empty():
			continue
		_cached_universe_frames[universe_id] = frame
		_last_universe_counters[universe_id] = {
			"counter": int(frame_entry.get("counter", -1)),
			"content_hash": int(frame_entry.get("content_hash", -1)),
			"interest_hash": -1,
			"interest_offsets": _compiled_relevant_offsets_by_universe.get(universe_id, PackedInt32Array()),
		}
		_native_visual_runtime.submit_universe_frame(universe_id, frame)
		submitted_universes += 1

	var visual_frame: Dictionary = _native_visual_runtime.consume_latest_visual_frame()
	var visual_descriptors: PackedInt32Array = visual_frame.get("descriptors", PackedInt32Array())
	var visual_integers: PackedInt32Array = visual_frame.get("integers", PackedInt32Array())
	var visual_floats: PackedFloat32Array = visual_frame.get("floats", PackedFloat32Array())
	_last_visual_frame_size = visual_descriptors.size() + visual_integers.size() + visual_floats.size()
	if _last_visual_frame_size > 0:
		var compact_result: Dictionary = {}
		if loader == null or light_apply_service == null:
			push_error("PeravizVisualRuntime requires the visual-frame light applier for live DMX playback.")
			return {"updated": updated, "skipped": skipped, "universes_changed": changed_frames.size(), "fixtures_considered": fixtures_considered, "controls": pending_controls}
		compact_result = _sectioned_visual_frame_applier.apply_snapshot(visual_frame, loader, light_apply_service, frame_delta_sec, self, _native_fixture_uuids_by_id, _fixture_nodes)
		_last_visual_mask_counts = compact_result.get("visual_mask_counts", {})
		fixtures_considered += int(compact_result.get("fixtures_considered", 0))
		updated += int(compact_result.get("updated", 0))
		skipped += int(compact_result.get("skipped", 0))
		_native_live_diagnostics = compact_result.duplicate(true)
		_log_native_live_diagnostics_once()

	return {
		"updated": updated,
		"skipped": skipped,
		"universes_changed": changed_frames.size(),
		"fixtures_considered": fixtures_considered,
		"controls": pending_controls,
		"native_visual_runtime_available": _native_visual_runtime_available,
		"native_bindings_count": _native_bindings_count,
		"visual_frame_size": _last_visual_frame_size,
		"visual_mask_counts": _last_visual_mask_counts.duplicate(false),
		"visual_apply_counters": light_apply_service.get_visual_apply_counters() if light_apply_service != null else {},
		"native_stats": _native_visual_runtime.get_stats() if _native_visual_runtime != null and _native_visual_runtime.has_method("get_stats") else {},
		"native_setup_summary": _native_setup_summary.duplicate(true),
		"native_live_diagnostics": _native_live_diagnostics.duplicate(true),
		"universes_submitted_to_native": submitted_universes,
	}

func _log_native_live_diagnostics_once() -> void:
	if _native_live_diagnostics_logged:
		return
	var skip_diagnostics: Dictionary = _native_live_diagnostics.get("skip_diagnostics", {})
	if int(skip_diagnostics.get("rows_generated", 0)) <= 0:
		return
	_native_live_diagnostics_logged = true
	print("[native-dpt-live] rows=%d unknown_fixture=%d missing_scene_fixture=%d legacy_bound_rejections=%d invalid_payload=%d pan=%d/%d/%d tilt=%d/%d/%d dimmer=%d/%d/%d first_failures=%s" % [
		int(skip_diagnostics.get("rows_generated", 0)),
		int(skip_diagnostics.get("unknown_fixture_id", 0)),
		int(skip_diagnostics.get("missing_scene_fixture", 0)),
		int(skip_diagnostics.get("legacy_bound_map_rejections", 0)),
		int(skip_diagnostics.get("invalid_schema_payload", 0)),
		int(skip_diagnostics.get("pan_requested", 0)),
		int(skip_diagnostics.get("pan_mutated", 0)),
		int(skip_diagnostics.get("pan_failed", 0)),
		int(skip_diagnostics.get("tilt_requested", 0)),
		int(skip_diagnostics.get("tilt_mutated", 0)),
		int(skip_diagnostics.get("tilt_failed", 0)),
		int(skip_diagnostics.get("dimmer_requested", 0)),
		int(skip_diagnostics.get("dimmer_mutated", 0)),
		int(skip_diagnostics.get("dimmer_failed", 0)),
		str(skip_diagnostics.get("first_failures", [])),
	])


func _consume_dirty_universe_frames(receiver) -> Dictionary:
	var changed_frames: Dictionary = {}
	var dirty_universes: PackedInt32Array = receiver.get_dirty_universes()
	for universe_id in dirty_universes:
		if not _compiled_used_universes.has(int(universe_id)):
			continue
		var frame: PackedByteArray = receiver.consume_universe(int(universe_id))
		if frame.is_empty():
			continue
		var previous_state: Variant = _last_universe_counters.get(int(universe_id), {})
		var previous_counter: int = -1
		if previous_state is Dictionary:
			previous_counter = int((previous_state as Dictionary).get("counter", -1))
		changed_frames[int(universe_id)] = {
			"data": frame,
			"counter": previous_counter + 1,
			"content_hash": _compute_snapshot_hash(frame),
			"interest_hash": -1,
		}
	return changed_frames

func _collect_changed_universe_frames_compat(receiver) -> Dictionary:
	var changed_frames: Dictionary = {}
	for universe_key in _compiled_used_universes.keys():
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
	if _loader == null or not _loader.has_method("compile_visual_runtime_scene"):
		_native_bindings_count = 0
		return
	var compiled_scene: Dictionary = _loader.compile_visual_runtime_scene(_runtime_universe_offset)
	_register_compiled_runtime_submission_metadata(compiled_scene)
	_register_native_renderer_manifest(compiled_scene.get("renderer_manifest", []))
	if _loader.has_method("_register_native_runtime_targets"):
		_loader._register_native_runtime_targets(compiled_scene.get("renderer_manifest", []))
	if _loader.has_method("_get_native_target_registry_summary"):
		_native_setup_summary["target_registry"] = _loader._get_native_target_registry_summary()
	_native_bindings_count = int(compiled_scene.get("property_count", 0))
	if _native_visual_runtime.has_method("install_compiled_scene"):
		_native_visual_runtime.install_compiled_scene(compiled_scene)
	if _sectioned_visual_frame_applier != null and _native_visual_runtime.has_method("get_visual_frame_schema"):
		_sectioned_visual_frame_applier.install_schema(_native_visual_runtime.get_visual_frame_schema())
	_report_native_setup_summary()

func _report_native_setup_summary() -> void:
	var summary: Dictionary = _native_setup_summary.duplicate(true)
	var dpt_count: int = int(summary.get("dimmer_property_count", 0)) + int(summary.get("pan_property_count", 0)) + int(summary.get("tilt_property_count", 0))
	print("[native-dpt-setup] mvr_fixture_patches=%d gdtf_files_opened=%d selected_modes=%d dmxchannels=%d dmxchannel_records=%d logical_channels=%d channel_functions=%d dimmer_programs=%d pan_programs=%d tilt_programs=%d compiled_properties=%d used_universes=%s relevant_offsets=%s manifest_fixtures=%d installed_native_properties=%d" % [
		int(summary.get("mvr_fixture_patches", summary.get("scene_fixture_count", 0))),
		int(summary.get("gdtf_files_opened", 0)),
		int(summary.get("selected_modes_found", 0)),
		int(summary.get("dmxchannels_found", 0)),
		int(summary.get("dmxchannel_records_found", 0)),
		int(summary.get("logical_channels_found", 0)),
		int(summary.get("channel_functions_found", 0)),
		int(summary.get("dimmer_program_count", 0)),
		int(summary.get("pan_program_count", 0)),
		int(summary.get("tilt_program_count", 0)),
		int(_native_bindings_count),
		str(summary.get("used_universes", {})),
		str(summary.get("relevant_offsets_by_universe", {})),
		int(summary.get("manifest_fixture_count", 0)),
		int(summary.get("installed_native_properties", _native_bindings_count)),
	])
	if int(summary.get("mvr_fixture_patches", summary.get("scene_fixture_count", 0))) > 0 and dpt_count == 0:
		push_error("Native Dimmer/Pan/Tilt runtime installed zero properties for patched fixtures; live DMX visualization will not produce DPT rows.")

func _register_compiled_runtime_submission_metadata(compiled_scene: Dictionary) -> void:
	_compiled_used_universes.clear()
	_compiled_relevant_offsets_by_universe.clear()
	var used_universes: Dictionary = compiled_scene.get("used_universes", {})
	for universe_key in used_universes.keys():
		_compiled_used_universes[int(str(universe_key))] = true
	var relevant_offsets: Dictionary = compiled_scene.get("relevant_offsets_by_universe", {})
	for universe_key in relevant_offsets.keys():
		var packed := PackedInt32Array()
		for offset in relevant_offsets.get(universe_key, []):
			packed.append(int(offset))
		_compiled_relevant_offsets_by_universe[int(str(universe_key))] = packed
	_native_setup_summary = compiled_scene.get("setup_summary", {}).duplicate(true)

func _register_native_renderer_manifest(renderer_manifest: Array) -> void:
	for item in renderer_manifest:
		if item is not Dictionary:
			continue
		var row: Dictionary = item
		var fixture_id: int = int(row.get("fixture_id", 0))
		var fixture_uuid: String = str(row.get("fixture_uuid", ""))
		if fixture_id <= 0 or fixture_uuid.is_empty():
			continue
		_native_fixture_ids_by_uuid[fixture_uuid] = fixture_id
		_native_fixture_uuids_by_id[fixture_id] = fixture_uuid
		if not _native_channel_values.has(fixture_uuid):
			_native_channel_values[fixture_uuid] = {}
		var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid) if _scene_registry != null else null
		if fixture_node != null:
			_fixture_nodes[fixture_uuid] = fixture_node
			_bound_fixture_ids[fixture_uuid] = true
			if _loader != null and _loader.has_method("_prepare_fixture_node_cache"):
				_loader._prepare_fixture_node_cache(fixture_uuid)

func _append_native_bindings_for_fixture(native_bindings: Array, binding: Dictionary) -> void:
	var fixture_uuid: String = str(binding.get("fixture_uuid", ""))
	var fixture_id: int = int(_native_fixture_ids_by_uuid.get(fixture_uuid, 0))
	if fixture_id <= 0:
		return
	_register_native_fixture_render_params(fixture_id, binding)
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_PAN, "pan_channel_index_0", "pan_fine_channel_index_0", "pan_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_TILT, "tilt_channel_index_0", "tilt_fine_channel_index_0", "tilt_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_DIMMER, "dimmer_channel_index_0", "dimmer_fine_channel_index_0", "dimmer_ultra_fine_channel_index_0")
	_append_native_zoom_binding(native_bindings, binding, fixture_id)
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_CYAN, "cyan_channel_index_0", "cyan_fine_channel_index_0", "cyan_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_MAGENTA, "magenta_channel_index_0", "magenta_fine_channel_index_0", "magenta_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_YELLOW, "yellow_channel_index_0", "yellow_fine_channel_index_0", "yellow_ultra_fine_channel_index_0")
	_append_native_gobo_bindings(native_bindings, binding, fixture_id)
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_PRISM, "prism_channel_index_0", "prism_fine_channel_index_0", "prism_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_PRISM_ROTATION, "prism_rotation_channel_index_0", "prism_rotation_fine_channel_index_0", "prism_rotation_ultra_fine_channel_index_0")
	_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_STROBE, "strobe_channel_index_0", "strobe_fine_channel_index_0", "strobe_ultra_fine_channel_index_0")

# Registers zoom while excluding gobo wheel offsets that can be misreported as zoom bytes.
func _append_native_zoom_binding(native_bindings: Array, binding: Dictionary, fixture_id: int) -> void:
	var reserved_gobo_offsets: Dictionary = _gobo_wheel_channel_indices(binding)
	var coarse_index: int = int(binding.get("zoom_channel_index_0", -1))
	var fine_index: int = int(binding.get("zoom_fine_channel_index_0", -1))
	var ultra_fine_index: int = int(binding.get("zoom_ultra_fine_channel_index_0", -1))
	if reserved_gobo_offsets.has(coarse_index):
		return
	if reserved_gobo_offsets.has(fine_index):
		fine_index = -1
	if reserved_gobo_offsets.has(ultra_fine_index):
		ultra_fine_index = -1
	_append_native_channel_binding_indices(native_bindings, binding, fixture_id, NATIVE_CHANNEL_ZOOM, coarse_index, fine_index, ultra_fine_index)

# Collects gobo wheel selector, index, and rotation offsets that must not drive non-gobo attributes.
func _gobo_wheel_channel_indices(binding: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for item in binding.get("gobo_wheels", []):
		if item is not Dictionary:
			continue
		var wheel: Dictionary = item
		for key in ["channel_index_0", "fine_channel_index_0", "ultra_fine_channel_index_0", "index_channel_index_0", "index_fine_channel_index_0", "index_ultra_fine_channel_index_0", "rotation_channel_index_0", "rotation_fine_channel_index_0", "rotation_ultra_fine_channel_index_0"]:
			var offset: int = int(wheel.get(key, -1))
			if offset >= 0:
				out[offset] = true
	return out

# Registers the single gobo selector/index/rotation wheel currently carried by the native frame.
func _append_native_gobo_bindings(native_bindings: Array, binding: Dictionary, fixture_id: int) -> void:
	var gobo_wheel: Dictionary = _native_gobo_source_wheel(binding)
	if int(binding.get("gobo1_channel_index_0", -1)) >= 0:
		_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO, "gobo1_channel_index_0", "gobo1_fine_channel_index_0", "gobo1_ultra_fine_channel_index_0")
	elif int(binding.get("gobo_channel_index_0", -1)) >= 0:
		_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO, "gobo_channel_index_0", "gobo_fine_channel_index_0", "gobo_ultra_fine_channel_index_0")
	elif not gobo_wheel.is_empty():
		_append_native_channel_binding_indices(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO, int(gobo_wheel.get("channel_index_0", -1)), int(gobo_wheel.get("fine_channel_index_0", -1)), int(gobo_wheel.get("ultra_fine_channel_index_0", -1)))

	if int(binding.get("gobo_index_channel_index_0", -1)) >= 0:
		_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO_INDEX, "gobo_index_channel_index_0", "gobo_index_fine_channel_index_0", "gobo_index_ultra_fine_channel_index_0")
	elif not gobo_wheel.is_empty():
		_append_native_channel_binding_indices(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO_INDEX, int(gobo_wheel.get("index_channel_index_0", -1)), int(gobo_wheel.get("index_fine_channel_index_0", -1)), int(gobo_wheel.get("index_ultra_fine_channel_index_0", -1)))

	if int(binding.get("gobo_rotation_channel_index_0", -1)) >= 0:
		_append_native_channel_binding(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO_ROTATION, "gobo_rotation_channel_index_0", "gobo_rotation_fine_channel_index_0", "gobo_rotation_ultra_fine_channel_index_0")
	elif not gobo_wheel.is_empty():
		_append_native_channel_binding_indices(native_bindings, binding, fixture_id, NATIVE_CHANNEL_GOBO_ROTATION, int(gobo_wheel.get("rotation_channel_index_0", -1)), int(gobo_wheel.get("rotation_fine_channel_index_0", -1)), int(gobo_wheel.get("rotation_ultra_fine_channel_index_0", -1)))

# Finds the first wheel with a selectable DMX channel for the current fixture binding.
func _first_selectable_gobo_wheel(binding: Dictionary) -> Dictionary:
	var wheels: Array = binding.get("gobo_wheels", [])
	for item in wheels:
		if item is not Dictionary:
			continue
		var wheel: Dictionary = item
		if int(wheel.get("channel_index_0", -1)) >= 0 or int(wheel.get("fine_channel_index_0", -1)) >= 0 or int(wheel.get("ultra_fine_channel_index_0", -1)) >= 0:
			return wheel
	return {}

# Resolves the single gobo wheel currently represented by the fixed native visual frame.
func _native_gobo_source_wheel(binding: Dictionary) -> Dictionary:
	var wheels: Array = binding.get("gobo_wheels", [])
	if wheels.is_empty():
		return {}
	var primary_wheel_number: int = int(binding.get("gobo_wheel_number", 0))
	if int(binding.get("gobo1_channel_index_0", -1)) >= 0 or int(binding.get("gobo_channel_index_0", -1)) >= 0:
		for item in wheels:
			if item is not Dictionary:
				continue
			var wheel: Dictionary = item
			var wheel_number: int = int(wheel.get("wheel_number", 0))
			if (primary_wheel_number > 0 and wheel_number == primary_wheel_number) or (primary_wheel_number <= 0 and wheel_number == 1):
				return wheel
	return _first_selectable_gobo_wheel(binding)


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
	_append_native_channel_binding_indices(native_bindings, binding, fixture_id, channel_type, int(binding.get(coarse_key, -1)), int(binding.get(fine_key, -1)), int(binding.get(ultra_fine_key, -1)))

func _append_native_channel_binding_indices(native_bindings: Array, binding: Dictionary, fixture_id: int, channel_type: int, coarse_index: int, fine_index: int, ultra_fine_index: int) -> void:
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


func get_live_visual_gobo_controls_for_fixture(fixture_uuid: String) -> Dictionary:
	return (_live_visual_gobo_controls_by_fixture.get(fixture_uuid, {}) as Dictionary).duplicate(false)

func get_static_gobo_controls_for_fixture(fixture_uuid: String) -> Dictionary:
	return (_static_gobo_controls_by_fixture.get(fixture_uuid, {}) as Dictionary).duplicate(false)

func get_live_gobo_diagnostics_for_fixture(fixture_uuid: String) -> Dictionary:
	return (_live_gobo_diagnostics_by_fixture.get(fixture_uuid, {}) as Dictionary).duplicate(false)


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
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_DIMMER, NATIVE_CHANNEL_DIMMER, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_DIMMER])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_PAN, NATIVE_CHANNEL_PAN, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_PAN])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_TILT, NATIVE_CHANNEL_TILT, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_TILT])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_ZOOM, NATIVE_CHANNEL_ZOOM, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_ZOOM])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_CYAN, NATIVE_CHANNEL_CYAN, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_CYAN])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_MAGENTA, NATIVE_CHANNEL_MAGENTA, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_MAGENTA])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_YELLOW, NATIVE_CHANNEL_YELLOW, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_YELLOW])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_GOBO, NATIVE_CHANNEL_GOBO, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_GOBO])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_GOBO_INDEX, NATIVE_CHANNEL_GOBO_INDEX, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_GOBO_INDEX])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_GOBO_ROTATION, NATIVE_CHANNEL_GOBO_ROTATION, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_GOBO_ROTATION])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_PRISM, NATIVE_CHANNEL_PRISM, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_PRISM])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_PRISM_ROTATION, NATIVE_CHANNEL_PRISM_ROTATION, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_PRISM_ROTATION])
	_store_compact_channel_value(values, changed_mask, NATIVE_COMPACT_STROBE, NATIVE_CHANNEL_STROBE, compact[base + NATIVE_VALUES_OFFSET + NATIVE_COMPACT_STROBE])
	_native_channel_values[fixture_uuid] = values

func _store_render_ready_fixture_values(fixture_uuid: String, compact: PackedFloat32Array, base: int, stride: int) -> void:
	if stride < NATIVE_RENDER_READY_STRIDE:
		_native_render_ready_values.erase(fixture_uuid)
		return
	_native_render_ready_values[fixture_uuid] = PackedFloat32Array([
		compact[base + NATIVE_RENDER_VALUES_OFFSET],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 1],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 2],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 3],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 4],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 5],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 6],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 7],
		compact[base + NATIVE_RENDER_VALUES_OFFSET + 8],
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
	_merge_static_gobo_controls(output, get_static_gobo_controls_for_fixture(fixture_uuid))
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

# Builds the setup-time live gobo bridge shell from cached static wheel metadata.
func _build_cached_live_gobo_controls(static_controls: Dictionary) -> Dictionary:
	var controls: Dictionary = {
		"capabilities": {},
		"changed_capability_types": {"gobo": true},
	}
	_merge_static_gobo_controls(controls, static_controls)
	return controls

# Updates only numeric live gobo values on the cached bridge dictionary.
func _update_cached_live_gobo_controls(controls: Dictionary, values: Dictionary) -> void:
	var gobo_value: Dictionary = values.get(NATIVE_CHANNEL_GOBO, {})
	var gobo_index_value: Dictionary = values.get(NATIVE_CHANNEL_GOBO_INDEX, {})
	var gobo_rotation_value: Dictionary = values.get(NATIVE_CHANNEL_GOBO_ROTATION, {})
	controls["has_gobo"] = bool(controls.get("has_gobo", false)) or not gobo_value.is_empty()
	controls["gobo_norm"] = float(gobo_value.get("norm", controls.get("gobo_norm", 0.0)))
	controls["gobo_raw_value"] = int(gobo_value.get("raw", round(clamp(float(controls.get("gobo_norm", 0.0)), 0.0, 1.0) * 255.0)))
	controls["has_gobo_index"] = bool(controls.get("has_gobo_index", false)) or not gobo_index_value.is_empty()
	controls["gobo_index_norm"] = float(gobo_index_value.get("norm", controls.get("gobo_index_norm", -1.0)))
	controls["has_gobo_rotation"] = bool(controls.get("has_gobo_rotation", false)) or not gobo_rotation_value.is_empty()
	controls["gobo_rotation_norm"] = float(gobo_rotation_value.get("norm", controls.get("gobo_rotation_norm", 0.0)))

# Caches static gobo wheel and slot metadata used by the live visual bridge.
func _build_static_gobo_controls(binding: Dictionary) -> Dictionary:
	var gobo_slots: Array = binding.get("gobo1_slots", binding.get("gobo_slots", []))
	var gobo_ranges: Array = binding.get("gobo1_ranges", binding.get("gobo_ranges", []))
	var gobo_wheels: Array = binding.get("gobo_wheels", [])
	var source_wheel: Dictionary = _native_gobo_source_wheel(binding)
	return {
		"has_gobo": not gobo_slots.is_empty() or not gobo_ranges.is_empty() or not gobo_wheels.is_empty() or int(binding.get("gobo_channel_index_0", -1)) >= 0 or int(binding.get("gobo1_channel_index_0", -1)) >= 0,
		"has_gobo_index": int(binding.get("gobo_index_channel_index_0", -1)) >= 0 or int(source_wheel.get("index_channel_index_0", -1)) >= 0,
		"has_gobo_rotation": int(binding.get("gobo_rotation_channel_index_0", -1)) >= 0 or int(source_wheel.get("rotation_channel_index_0", -1)) >= 0,
		"gobo_slots": gobo_slots,
		"gobo_ranges": gobo_ranges,
		"gobo_wheel_name": str(binding.get("gobo1_wheel_name", binding.get("gobo_wheel_name", ""))),
		"gobo_wheel_number": int(binding.get("gobo_wheel_number", 0)),
		"gobo_wheels": gobo_wheels,
		"gobo_runtime_bindings": binding.get("gobo_runtime_bindings", []),
		"live_gobo_source_wheel_number": int(source_wheel.get("wheel_number", int(binding.get("gobo_wheel_number", 0)))),
		"live_gobo_source_wheel_name": str(source_wheel.get("wheel_name", binding.get("gobo1_wheel_name", binding.get("gobo_wheel_name", "")))),
	}

# Copies cached static gobo metadata into a live controls dictionary without recomputing it.
func _merge_static_gobo_controls(target: Dictionary, static_controls: Dictionary) -> void:
	if static_controls.is_empty():
		return
	for key in ["gobo_slots", "gobo_ranges", "gobo_wheel_name", "gobo_wheel_number", "gobo_wheels", "gobo_runtime_bindings", "live_gobo_source_wheel_number", "live_gobo_source_wheel_name"]:
		target[key] = static_controls.get(key, target.get(key, []))
	target["has_gobo"] = bool(target.get("has_gobo", false)) or bool(static_controls.get("has_gobo", false))
	target["has_gobo_index"] = bool(target.get("has_gobo_index", false)) or bool(static_controls.get("has_gobo_index", false))
	target["has_gobo_rotation"] = bool(target.get("has_gobo_rotation", false)) or bool(static_controls.get("has_gobo_rotation", false))

# Resolves runtime gobo bindings from the native-packed selector and cached wheel metadata.
func _build_live_visual_gobo_runtime_bindings(controls: Dictionary) -> Array:
	var wheels: Array = controls.get("gobo_wheels", [])
	var raw_8bit: int = int(controls.get("gobo_raw_value", round(clamp(float(controls.get("gobo_norm", 0.0)), 0.0, 1.0) * 255.0)))
	if wheels.is_empty():
		var primary_ranges: Array = controls.get("gobo_ranges", [])
		var primary_slots: Array = controls.get("gobo_slots", [])
		var primary_range: Dictionary = DmxGoboRangeResolverScript.resolve_active_range(raw_8bit, primary_ranges) if not primary_ranges.is_empty() else {}
		var primary_slot_index: int = int(primary_range.get("slot_index", -1))
		if primary_slot_index <= 0:
			return []
		return [{
			"raw_8bit": raw_8bit,
			"slot_index": primary_slot_index,
			"slots": primary_slots,
			"ranges": primary_ranges,
			"wheel_number": int(controls.get("gobo_wheel_number", 0)),
			"wheel_name": str(controls.get("gobo_wheel_name", "")),
			"behavior": int(primary_range.get("behavior", 0)),
		}]
	var index_norm: float = clamp(float(controls.get("gobo_index_norm", -1.0)), 0.0, 1.0) if bool(controls.get("has_gobo_index", false)) else -1.0
	var out: Array = []
	for item in _live_visual_gobo_source_wheels(controls):
		if item is not Dictionary:
			continue
		var wheel: Dictionary = item
		var slots: Array = wheel.get("slots", [])
		if slots.is_empty():
			slots = controls.get("gobo_slots", [])
		var ranges: Array = wheel.get("ranges", [])
		if ranges.is_empty():
			ranges = controls.get("gobo_ranges", [])
		var active_range: Dictionary = DmxGoboRangeResolverScript.resolve_active_range(raw_8bit, ranges) if not ranges.is_empty() else {}
		var slot_index: int = int(active_range.get("slot_index", -1))
		if slot_index <= 0:
			continue
		out.append({
			"raw_8bit": raw_8bit,
			"slot_index": slot_index,
			"slots": slots,
			"ranges": ranges,
			"wheel_number": int(wheel.get("wheel_number", controls.get("gobo_wheel_number", 0))),
			"wheel_name": str(wheel.get("wheel_name", controls.get("gobo_wheel_name", ""))),
			"behavior": int(active_range.get("behavior", 0)),
			"supports_index": bool(wheel.get("supports_index", false)),
			"supports_rotation": bool(wheel.get("supports_rotation", false)),
			"supports_shake": bool(wheel.get("supports_shake", false)),
			"index_norm": index_norm,
			"has_index_physical_limits": bool(wheel.get("has_index_physical_limits", false)),
			"index_physical_min": float(wheel.get("index_physical_min", 0.0)),
			"index_physical_max": float(wheel.get("index_physical_max", 0.0)),
		})
	return out

# Returns only the wheel whose selector is packed into the current native gobo channel.
func _live_visual_gobo_source_wheels(controls: Dictionary) -> Array:
	var wheels: Array = controls.get("gobo_wheels", [])
	if wheels.is_empty():
		return []
	var source_number: int = int(controls.get("live_gobo_source_wheel_number", 0))
	var source_name: String = str(controls.get("live_gobo_source_wheel_name", ""))
	for item in wheels:
		if item is not Dictionary:
			continue
		var wheel: Dictionary = item
		if source_number > 0 and int(wheel.get("wheel_number", 0)) == source_number:
			return [wheel]
		if source_number <= 0 and not source_name.is_empty() and str(wheel.get("wheel_name", "")) == source_name:
			return [wheel]
	for item in wheels:
		if item is Dictionary:
			return [item]
	return []

func _build_live_gobo_diagnostics(controls: Dictionary, static_controls: Dictionary, visual_mask: int) -> Dictionary:
	return {
		"mask_received": true,
		"visual_change_gobo": (visual_mask & VISUAL_CHANGE_GOBO) != 0,
		"visual_change_gobo_rotation": (visual_mask & VISUAL_CHANGE_GOBO_ROTATION) != 0,
		"controls_found": not controls.is_empty(),
		"has_gobo": bool(controls.get("has_gobo", false)),
		"gobo_slot_count": (controls.get("gobo_slots", []) as Array).size(),
		"gobo_range_count": (controls.get("gobo_ranges", []) as Array).size(),
		"runtime_binding_count": (controls.get("gobo_runtime_bindings", []) as Array).size(),
		"static_wheel_count": (static_controls.get("gobo_wheels", []) as Array).size(),
		"live_gobo_source_wheel_number": int(controls.get("live_gobo_source_wheel_number", 0)),
		"live_gobo_source_wheel_name": str(controls.get("live_gobo_source_wheel_name", "")),
		"raw_gobo_value": int(controls.get("gobo_raw_value", -1)),
	}

func _build_fixture_output_buffer(binding: Dictionary) -> Dictionary:
	var output: Dictionary = {
		"compact_values": _build_empty_compact_controls(),
		"capabilities": {},
		"metadata": binding.get("metadata", {}),
	}
	_merge_static_gobo_controls(output, _build_static_gobo_controls(binding))
	return output

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
