extends RefCounted

# Cold resource admission only. Native final render rows supply every live value.
# Preserve the legacy loop for small scenes and all unsupported optical/resource policies.
static func install(adapter: RefCounted) -> void:
	var objects := PackedInt64Array()
	var thresholds := PackedFloat64Array()
	objects.resize(adapter._render_bindings.rows.size())
	thresholds.resize(objects.size())
	thresholds.fill(0.015)
	var settings: Dictionary = adapter._loader.get("_visual_settings")
	var supported: bool = OS.get_environment("PERAVIZ_NATIVE_BEAM_APPLY") != "0" and adapter._renderer != null and adapter._renderer.has_method("supports_native_dynamic") and not adapter._diagnostic_open_surface_lights and not bool(settings.get("beam_debug_optics", false)) and not bool(settings.get("enable_realtime_spotlights", false)) and int(settings.get("beam_presentation", 1)) == 1
	var candidates: Array = []
	for row_index in range(adapter._render_bindings.rows.size()):
		var row = adapter._render_bindings.rows[row_index]
		for handle in row.output.lights: handle.native_candidate = false
		if not supported or row.presentation_class != 0 or row.output.lights.size() != 1: continue
		if not adapter._groups.is_empty() and adapter._groups[row.output.index] != null: continue
		var handle = row.output.lights[0]
		if not handle.projected or handle.has_gobo or handle.light.light_projector != null: continue
		if not adapter._renderer.supports_native_dynamic(handle.light, handle.beam): continue
		objects[row_index] = handle.beam.get_instance_id()
		thresholds[row_index] = float(handle.params.get("intensity_visibility_threshold", 0.015))
		candidates.append(handle)
	# Admission keeps the existing 115-row reference scene entirely on its established path.
	if candidates.size() < 128:
		adapter._native.clear_beams()
		return
	if adapter._native.install_beams(adapter._generation, objects, thresholds):
		for handle in candidates: handle.native_candidate = true
