extends RefCounted

# Cold resource admission only; no GDTF/DMX interpretation or per-flash resource discovery.
static func install(adapter: RefCounted) -> void:
	var objects := PackedInt64Array()
	var thresholds := PackedFloat64Array()
	objects.resize(adapter._render_bindings.rows.size())
	thresholds.resize(objects.size())
	thresholds.fill(0.015)
	var group_materials: Array = []
	group_materials.resize(objects.size())
	var settings: Dictionary = adapter._loader.get("_visual_settings")
	var vector: bool = int(settings.get("beam_presentation",1)) == 1
	for index in range(objects.size()):
		var row = adapter._render_bindings.rows[index]
		if vector and row.output.lights.size() == 1:
			var handle = row.output.lights[0]
			if is_instance_valid(handle.beam):
				objects[index] = handle.beam.get_instance_id()
				var material: ShaderMaterial = handle.beam.material_override as ShaderMaterial
				if material != null and material.get_shader_parameter("use_control_group_state") == true:
					group_materials[index] = material.get_rid()
			thresholds[index] = float(handle.params.get("intensity_visibility_threshold",0.015))
	var lights := PackedInt64Array()
	var owners := PackedInt32Array()
	for output in adapter._outputs:
		for handle in output.lights:
			if is_instance_valid(handle.light) and handle.owns_realtime_surface_light:
				lights.append(handle.light.get_instance_id())
				owners.append(output.index)
	adapter._native.install_shutter_resources(adapter._generation,objects,thresholds,group_materials,lights,owners)
