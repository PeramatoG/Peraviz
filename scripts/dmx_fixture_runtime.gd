extends RefCounted
class_name DmxFixtureRuntime

const MAX_UNBOUND_PREVIEW: int = 8
const FORCE_COARSE_ONLY_DMX_READ: bool = false

const GoboVectorizationCacheScript = preload("res://scripts/gobo_vectorization/gobo_vectorization_cache.gd")
const ControlReaderScript = preload("res://scripts/dmx_capability_control_reader.gd")
const CapabilityNormalizerScript = preload("res://scripts/dmx_capability_normalizer.gd")
const PanTiltCapabilityHandlerScript = preload("res://scripts/dmx_capabilities/pan_tilt_capability_handler.gd")
const DimmerCapabilityHandlerScript = preload("res://scripts/dmx_capabilities/dimmer_capability_handler.gd")
const ColorWheelCapabilityHandlerScript = preload("res://scripts/dmx_capabilities/color_wheel_capability_handler.gd")
const GoboCapabilityHandlerScript = preload("res://scripts/dmx_capabilities/gobo_capability_handler.gd")
const PrismCapabilityHandlerScript = preload("res://scripts/dmx_capabilities/prism_capability_handler.gd")
const StrobeCapabilityHandlerScript = preload("res://scripts/dmx_capabilities/strobe_capability_handler.gd")

var _loader = null
var _scene_registry: SceneRegistry = null
var _bindings: Array = []
var _unbound: Array = []
var _fixture_patch_lookup: Dictionary = {}
var _fixture_nodes: Dictionary = {}
var _bound_fixture_ids: Dictionary = {}
var _fixture_channel_offsets: Dictionary = {}
var _fixture_snapshot_cache: Dictionary = {}
var _fixture_capability_hash_cache: Dictionary = {}
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
	_fixture_capability_hash_cache.clear()
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

func _collect_dmx(receiver, apply_fixture_callback: Callable) -> Dictionary:
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
		var universe_bindings: Array = _bindings_by_universe.get(universe_id, [])
		for binding in universe_bindings:
			if binding is not Dictionary:
				continue
			var result: Dictionary = _apply_binding_frame(binding, frame, apply_fixture_callback, pending_controls)
			if result.is_empty():
				continue
			fixtures_considered += 1
			updated += int(result.get("updated", 0))
			skipped += int(result.get("skipped", 0))

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

func _get_universe_interest_offsets_array(universe_id: int) -> PackedInt32Array:
	var offset_map: Dictionary = _universe_interest_offsets.get(universe_id, {})
	var offsets: Array = offset_map.keys()
	offsets.sort()
	var packed_offsets := PackedInt32Array()
	for offset in offsets:
		packed_offsets.append(int(offset))
	return packed_offsets

func _compute_universe_interest_hash(universe_id: int, frame: PackedByteArray) -> int:
	var offset_map: Dictionary = _universe_interest_offsets.get(universe_id, {})
	var hash_value: int = 2166136261
	for offset_key in offset_map.keys():
		var offset: int = int(offset_key)
		var value: int = int(frame[offset]) if offset >= 0 and offset < frame.size() else 0
		hash_value = int((hash_value ^ value) * 16777619)
		hash_value = int((hash_value ^ offset) * 16777619)
	return hash_value

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
	var handler_scripts: Dictionary = {
		"pan_tilt": {
			"script": PanTiltCapabilityHandlerScript,
			"normalizer": null,
		},
		"dimmer": {
			"script": DimmerCapabilityHandlerScript,
			"normalizer": null,
		},
		"color_wheel": {
			"script": ColorWheelCapabilityHandlerScript,
			"normalizer": null,
		},
		"gobo": {
			"script": GoboCapabilityHandlerScript,
			"normalizer": CapabilityNormalizerScript,
		},
		"prism": {
			"script": PrismCapabilityHandlerScript,
			"normalizer": null,
		},
		"strobe": {
			"script": StrobeCapabilityHandlerScript,
			"normalizer": null,
		},
	}
	return {
		"binding": binding,
		"handlers": _build_active_handlers_for_plan(binding, handler_scripts),
		"metadata": binding.get("metadata", {}),
	}

func _build_active_handlers_for_plan(binding: Dictionary, handler_scripts: Dictionary) -> Dictionary:
	var active_handlers: Dictionary = {}
	var empty_frame := PackedByteArray()
	for capability_type in handler_scripts.keys():
		var definition: Dictionary = handler_scripts.get(capability_type, {})
		var script = definition.get("script", null)
		var normalizer = definition.get("normalizer", null)
		var blocks: Array = []
		if script == null:
			continue
		if normalizer != null:
			blocks = script.collect(binding, empty_frame, ControlReaderScript, normalizer, FORCE_COARSE_ONLY_DMX_READ)
		else:
			blocks = script.collect(binding, empty_frame, ControlReaderScript, FORCE_COARSE_ONLY_DMX_READ)
		if not blocks.is_empty():
			active_handlers[capability_type] = definition
	if active_handlers.is_empty():
		return handler_scripts.duplicate(true)
	return active_handlers

func _build_fixture_output_buffer(binding: Dictionary) -> Dictionary:
	return {
		"capabilities": {
			"pan_tilt": [],
			"dimmer": [],
			"color_wheel": [],
			"gobo": [],
			"prism": [],
			"strobe": [],
		},
		"metadata": binding.get("metadata", {}),
	}

func _build_controls_for_plan(fixture_plan: Dictionary, frame: PackedByteArray, fixture_uuid: String) -> Dictionary:
	var output: Dictionary = _fixture_output_buffers.get(fixture_uuid, _build_fixture_output_buffer(fixture_plan.get("binding", {})))
	_fixture_output_buffers[fixture_uuid] = output
	var capabilities: Dictionary = output.get("capabilities", {})
	_clear_capability_output(capabilities)
	var handlers: Dictionary = fixture_plan.get("handlers", {})
	_append_capability_from_plan(capabilities, "pan_tilt", fixture_plan, handlers, frame)
	_append_capability_from_plan(capabilities, "dimmer", fixture_plan, handlers, frame)
	_append_capability_from_plan(capabilities, "color_wheel", fixture_plan, handlers, frame)
	_append_capability_from_plan(capabilities, "gobo", fixture_plan, handlers, frame)
	_append_capability_from_plan(capabilities, "prism", fixture_plan, handlers, frame)
	_append_capability_from_plan(capabilities, "strobe", fixture_plan, handlers, frame)
	var changed_capability_types: Dictionary = _filter_unchanged_capabilities(fixture_uuid, capabilities)
	output["changed_capability_types"] = changed_capability_types
	output["metadata"] = fixture_plan.get("metadata", output.get("metadata", {}))
	return output

func _filter_unchanged_capabilities(fixture_uuid: String, capabilities: Dictionary) -> Dictionary:
	var previous_hashes: Dictionary = _fixture_capability_hash_cache.get(fixture_uuid, {})
	var next_hashes: Dictionary = {}
	var changed_capability_types: Dictionary = {}
	for capability_type in ["pan_tilt", "dimmer", "color_wheel", "gobo", "prism", "strobe"]:
		var bucket: Array = capabilities.get(capability_type, [])
		var bucket_hash: int = _hash_capability_bucket(bucket)
		next_hashes[capability_type] = bucket_hash
		if not previous_hashes.has(capability_type) or int(previous_hashes.get(capability_type, 0)) != bucket_hash:
			changed_capability_types[capability_type] = true
		elif not bucket.is_empty():
			bucket.clear()
	_fixture_capability_hash_cache[fixture_uuid] = next_hashes
	return changed_capability_types

func _hash_capability_bucket(bucket: Array) -> int:
	var hash_value: int = 2166136261
	for item in bucket:
		if item is not Dictionary:
			continue
		var row: Dictionary = item
		var keys: Array = row.keys()
		keys.sort()
		for key in keys:
			hash_value = int((hash_value ^ hash(key)) * 16777619)
			hash_value = int((hash_value ^ hash(row.get(key))) * 16777619)
	return hash_value

func _clear_capability_output(capabilities: Dictionary) -> void:
	for capability_type in ["pan_tilt", "dimmer", "color_wheel", "gobo", "prism", "strobe"]:
		if not capabilities.has(capability_type):
			capabilities[capability_type] = []
		else:
			(capabilities[capability_type] as Array).clear()

func _append_capability_from_plan(capabilities: Dictionary, capability_type: String, fixture_plan: Dictionary, handlers: Dictionary, frame: PackedByteArray) -> void:
	if not handlers.has(capability_type):
		return
	var handler_plan: Dictionary = handlers.get(capability_type, {})
	var script = handler_plan.get("script", null)
	if script == null:
		return
	var blocks: Array = []
	var normalizer = handler_plan.get("normalizer", null)
	if normalizer != null:
		blocks = script.collect(fixture_plan.get("binding", {}), frame, ControlReaderScript, normalizer, FORCE_COARSE_ONLY_DMX_READ)
	else:
		blocks = script.collect(fixture_plan.get("binding", {}), frame, ControlReaderScript, FORCE_COARSE_ONLY_DMX_READ)
	_append_capabilities(capabilities, capability_type, blocks)

func _apply_fixture_with_compatibility_adapter(apply_fixture_callback: Callable, fixture_uuid: String, controls: Dictionary, pending_controls: Array = []) -> void:
	# Temporary compatibility adapter for incremental migration.
	# Old callback contract receives (fixture_uuid, controls).
	# New contract may receive a precompiled output envelope.
	if apply_fixture_callback.is_null():
		pending_controls.append({"fixture_uuid": fixture_uuid, "controls": controls.duplicate(true)})
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
	])

func _append_capabilities(capabilities: Dictionary, capability_type: String, blocks: Array) -> void:
	if blocks.is_empty():
		return
	if not capabilities.has(capability_type):
		capabilities[capability_type] = []
	var bucket: Array = capabilities.get(capability_type, [])
	for block in blocks:
		if block is Dictionary:
			bucket.append(block)
	capabilities[capability_type] = bucket

func _has_any_capability(controls: Dictionary) -> bool:
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
