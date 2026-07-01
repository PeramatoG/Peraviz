extends SceneTree

const ResolverScript = preload("res://scripts/dmx_gobo_controls_resolver.gd")
const RuntimeScript = preload("res://scripts/dmx_fixture_runtime.gd")

# Runs live visual-frame gobo resolver regressions in a headless Godot process.
func _init() -> void:
	var failures: Array[String] = []
	_test_live_controls_preserve_top_level_bindings(failures)
	_test_legacy_capability_blocks_still_aggregate(failures)
	_test_live_runtime_uses_single_native_gobo_wheel(failures)
	_test_zoom_binding_ignores_gobo_wheel_fine_offset(failures)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("DmxGoboControlsResolver regression checks passed.")
	quit(0)

# Verifies live visual-frame controls are not wiped when capabilities are intentionally empty.
func _test_live_controls_preserve_top_level_bindings(failures: Array[String]) -> void:
	var controls: Dictionary = {
		"capabilities": {},
		"has_gobo": true,
		"gobo_norm": 0.5,
		"gobo_raw_value": 128,
		"gobo_resolution_bits": 8,
		"gobo_slots": [
			{"slot_index": 1, "image_path": "res://tests/fixtures/gobo-slot.png"},
		],
		"gobo_ranges": [
			{"slot_index": 1, "dmx_from": 64, "dmx_to": 127},
		],
		"gobo_runtime_bindings": [
			{
				"slot_index": 1,
				"texture_path": "res://tests/fixtures/gobo-slot.png",
				"slots": [{"slot_index": 1, "image_path": "res://tests/fixtures/gobo-slot.png"}],
			},
		],
	}
	var resolved: Dictionary = ResolverScript.resolve(controls)
	if not bool(resolved.get("has_gobo", false)):
		failures.append("Live gobo controls lost has_gobo=true when capabilities.gobo was empty.")
	if (resolved.get("gobo_runtime_bindings", []) as Array).is_empty():
		failures.append("Live gobo controls lost top-level gobo_runtime_bindings when capabilities.gobo was empty.")
	if (resolved.get("gobo_slots", []) as Array).is_empty():
		failures.append("Live gobo controls lost top-level gobo_slots when capabilities.gobo was empty.")

# Verifies legacy capability blocks keep aggregating for non-live callers.
func _test_legacy_capability_blocks_still_aggregate(failures: Array[String]) -> void:
	var controls: Dictionary = {
		"capabilities": {
			"gobo": [
				{
					"has_gobo": true,
					"gobo_slots": [{"slot_index": 2, "image_path": "res://tests/fixtures/legacy-slot.png"}],
					"gobo_runtime_bindings": [{"slot_index": 2, "slots": [{"slot_index": 2}]}],
				},
			],
		},
	}
	var resolved: Dictionary = ResolverScript.resolve(controls)
	if not bool(resolved.get("has_gobo", false)):
		failures.append("Legacy capability gobo controls no longer aggregate has_gobo=true.")
	if (resolved.get("gobo_runtime_bindings", []) as Array).size() != 1:
		failures.append("Legacy capability gobo controls did not aggregate runtime bindings.")
	if (resolved.get("gobo_slots", []) as Array).size() != 1:
		failures.append("Legacy capability gobo controls did not aggregate slots.")

# Verifies one packed native gobo selector does not compose all cached fixture wheels together.
func _test_live_runtime_uses_single_native_gobo_wheel(failures: Array[String]) -> void:
	var runtime = RuntimeScript.new()
	var binding: Dictionary = {
		"gobo1_channel_index_0": 10,
		"gobo_wheel_number": 1,
		"gobo_wheels": [
			{
				"wheel_number": 1,
				"wheel_name": "Gobo 1",
				"channel_index_0": 10,
				"ranges": [{"slot_index": 1, "dmx_from": 1, "dmx_to": 255}],
				"slots": [{"slot_index": 1, "image_path": "res://tests/fixtures/gobo-one.png"}],
			},
			{
				"wheel_number": 2,
				"wheel_name": "Gobo 2",
				"channel_index_0": 20,
				"ranges": [{"slot_index": 2, "dmx_from": 1, "dmx_to": 255}],
				"slots": [{"slot_index": 2, "image_path": "res://tests/fixtures/gobo-two.png"}],
			},
		],
	}
	var controls: Dictionary = {
		"has_gobo": true,
		"gobo_norm": 0.5,
		"gobo_raw_value": 128,
		"gobo_resolution_bits": 8,
	}
	runtime._merge_static_gobo_controls(controls, runtime._build_static_gobo_controls(binding))
	var runtime_bindings: Array = runtime._build_live_visual_gobo_runtime_bindings(controls)
	if runtime_bindings.size() != 1:
		failures.append("Live native gobo selector should resolve exactly one source wheel, not compose multiple wheels.")
		return
	var resolved_wheel: Dictionary = runtime_bindings[0] as Dictionary
	if int(resolved_wheel.get("wheel_number", 0)) != 1:
		failures.append("Live native gobo selector resolved wheel %d instead of the packed source wheel 1." % int(resolved_wheel.get("wheel_number", 0)))

# Verifies gobo wheel channels cannot be packed as zoom fine bytes and collapse the beam angle.
func _test_zoom_binding_ignores_gobo_wheel_fine_offset(failures: Array[String]) -> void:
	var runtime = RuntimeScript.new()
	var native_bindings: Array = []
	var binding: Dictionary = {
		"artnet_universe_id": 0,
		"zoom_channel_index_0": 30,
		"zoom_fine_channel_index_0": 40,
		"gobo_wheels": [
			{
				"wheel_number": 2,
				"wheel_name": "Gobo 2",
				"channel_index_0": 40,
			},
		],
	}
	runtime._append_native_zoom_binding(native_bindings, binding, 7)
	if native_bindings.size() != 1:
		failures.append("Zoom binding with a valid coarse channel should still be registered when only its fine byte overlaps a gobo wheel.")
		return
	var zoom_binding: Dictionary = native_bindings[0] as Dictionary
	if int(zoom_binding.get("channel_type", -1)) != 4:
		failures.append("Sanitized zoom binding used the wrong native channel type.")
	if int(zoom_binding.get("start_address", -1)) != 30:
		failures.append("Sanitized zoom binding did not keep the zoom coarse address.")
	if int(zoom_binding.get("fine_address", -1)) != -1:
		failures.append("Sanitized zoom binding kept a gobo wheel offset as zoom fine address.")
	if int(zoom_binding.get("bit_depth", 0)) != 8:
		failures.append("Sanitized zoom binding should fall back to 8-bit zoom after removing the gobo overlap.")
