extends RefCounted
class_name DmxGoboControlsResolver

# Resolves gobo controls from legacy capability blocks or already-flattened live visual state.
static func resolve(controls: Dictionary) -> Dictionary:
	var capabilities: Dictionary = controls.get("capabilities", {})
	if capabilities is Dictionary:
		var gobo_blocks: Array = capabilities.get("gobo", [])
		if not gobo_blocks.is_empty():
			var aggregated: Dictionary = {}
			var aggregated_bindings: Array = []
			var aggregated_slots: Array = []
			var has_any_gobo: bool = false
			for item in gobo_blocks:
				if item is not Dictionary:
					continue
				var block: Dictionary = item as Dictionary
				if aggregated.is_empty():
					aggregated = block.duplicate(true)
				if bool(block.get("has_gobo", false)):
					has_any_gobo = true
				for runtime_binding in block.get("gobo_runtime_bindings", []):
					aggregated_bindings.append(runtime_binding)
				for slot_item in block.get("gobo_slots", []):
					aggregated_slots.append(slot_item)
			if not aggregated.is_empty():
				aggregated["has_gobo"] = has_any_gobo or not aggregated_bindings.is_empty()
				aggregated["gobo_runtime_bindings"] = aggregated_bindings
				aggregated["gobo_slots"] = aggregated_slots
				return aggregated
	return {
		"has_gobo": bool(controls.get("has_gobo", false)),
		"gobo_norm": float(controls.get("gobo_norm", 0.0)),
		"gobo_raw_value": int(controls.get("gobo_raw_value", 0)),
		"gobo_resolution_bits": int(controls.get("gobo_resolution_bits", 8)),
		"has_gobo_index": bool(controls.get("has_gobo_index", false)),
		"gobo_index_norm": float(controls.get("gobo_index_norm", 0.0)),
		"has_gobo_rotation": bool(controls.get("has_gobo_rotation", false)),
		"gobo_rotation_norm": float(controls.get("gobo_rotation_norm", 0.0)),
		"gobo_slots": controls.get("gobo_slots", []),
		"gobo_ranges": controls.get("gobo_ranges", []),
		"gobo_runtime_bindings": controls.get("gobo_runtime_bindings", []),
		"gobo_wheel_name": str(controls.get("gobo_wheel_name", "")),
		"gobo_wheel_number": int(controls.get("gobo_wheel_number", 0)),
	}
