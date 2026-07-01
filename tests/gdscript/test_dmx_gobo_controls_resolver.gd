extends SceneTree

const ResolverScript = preload("res://scripts/dmx_gobo_controls_resolver.gd")

# Runs live visual-frame gobo resolver regressions in a headless Godot process.
func _init() -> void:
	var failures: Array[String] = []
	_test_live_controls_preserve_top_level_bindings(failures)
	_test_legacy_capability_blocks_still_aggregate(failures)
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
