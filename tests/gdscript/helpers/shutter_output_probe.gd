extends RefCounted

# Reads actual renderer caches/uniforms, independently of semantic shutter metadata.
static func capture(adapter: RefCounted) -> Array:
	var result: Array = []
	var temporal: bool = adapter._native.get_sizes().shutter_layers > 0
	for output in adapter._outputs:
		var row = adapter._render_bindings.rows[adapter._render_bindings.membership[output.index]]
		var handle = row.output.lights[0]
		var materials: Array = []
		for material in output.materials:
			var committed: PackedFloat32Array = adapter._native.material_values(material.rid)
			if committed.size() == 4: materials.append([material.material,material.rid,committed[3],committed.slice(0,3)])
		var footprint: Array = []
		if output.index < adapter._footprints.volumes.size():
			var volume: MeshInstance3D = adapter._footprints.volumes[output.index]
			var rid: RID = volume.material_override.get_rid()
			footprint = [volume,volume.mesh,volume.material_override,rid,adapter._native.footprint_values(rid)[3]]
		var group_material: ShaderMaterial = handle.beam.material_override as ShaderMaterial
		var group: bool = group_material != null and group_material.get_shader_parameter("use_control_group_state") == true
		var dynamic: Color = RenderingServer.material_get_param(group_material.get_rid(),"control_group_dynamic_state") if group and RenderingServer.get_rendering_device() != null else group_material.get_shader_parameter("control_group_dynamic_state") if group else handle.beam.get_instance_shader_parameter("beam_dynamic_state")
		if group and temporal and adapter._native.has_method("shutter_beam_energy"): dynamic.a = adapter._native.shutter_beam_energy(adapter._render_bindings.membership[output.index])
		result.append({"physical":adapter._native.physical_values(output.index),"beam":handle.beam,"mesh":handle.beam.mesh,"material":handle.beam.material_override,"intensity":dynamic.a,"row":adapter._render_bindings.membership[output.index],"shared_material":group,"materials":materials,"footprint":footprint})
	return result

static func check(owner: SceneTree, baseline: Array, index: int, envelope: float) -> void:
	index = owner.cell_index(index)
	var adapter: RefCounted = owner.adapter
	var held: Dictionary = baseline[index]
	owner.test.check(adapter._native.physical_values(index) == held.physical,"Shutter never mutates canonical native Color/Dimmer/photometric values")
	owner.test.check_close(adapter._native.shutter_values()[index],envelope,0.0001,"Native persistent envelope reaches the exact physical output")
	var beam: MeshInstance3D = held.beam
	owner.test.check(beam.visible == (held.intensity*envelope > 0.015),"Actual Vector Prism visibility follows its own shutter")
	if beam.visible:
		var dynamic: Color = beam.get_instance_shader_parameter("beam_dynamic_state")
		var energy: float = adapter._native.shutter_beam_energy(held.row) if held.shared_material else dynamic.a
		owner.test.check_close(energy,held.intensity*envelope,0.001,"Actual shaft instance uniform carries the presentation multiplier")
	for entry in held.materials:
		var committed: PackedFloat32Array = adapter._native.material_values(entry[1])
		owner.test.check(committed.slice(0,3) == entry[3],"Shutter preserves the existing independent material emission color")
		owner.test.check_close(committed[3],entry[2]*envelope,0.001,"Existing lens material emission receives the same envelope")
		if RenderingServer.get_rendering_device() != null:
			owner.test.check_close(float(RenderingServer.material_get_param(entry[1],"emission_energy")),entry[2]*envelope,0.001,"Actual RenderingServer lens energy matches the cached presentation")
	if not held.footprint.is_empty():
		owner.test.check_close(adapter._native.footprint_values(held.footprint[3])[3],held.footprint[4]*envelope,0.001,"Actual Custom footprint material receives the same envelope")
	if adapter._lens_batches.members.has(index):
		var location: Vector2i = adapter._lens_batches.members[index]
		var buffer: PackedFloat32Array = adapter._native.lens_buffer(location.x)
		var batch: Dictionary = adapter._lens_batches.batches[location.x]
		var scale: float = batch.entries[location.y].scale
		for component in range(3): owner.test.check_close(buffer[location.y*16+12+component],held.physical[component+1],0.0001,"Instanced lens colors remain per-physical output")
		owner.test.check_close(buffer[location.y*16+15],held.physical[7]*scale*envelope,0.001,"GPU-instanced lens custom energy remains independently modulated")

static func resources(owner: SceneTree, baseline: Array) -> void:
	for held: Dictionary in baseline:
		owner.test.check(is_instance_valid(held.beam) and held.beam.mesh == held.mesh and held.beam.material_override == held.material,"Flash retains shaft mesh/material/resource identity")
		for entry in held.materials: owner.test.check(is_instance_valid(entry[0]) and entry[0].get_rid() == entry[1],"Flash retains original prepared lens material RID")
		if not held.footprint.is_empty(): owner.test.check(held.footprint[0].mesh == held.footprint[1] and held.footprint[0].material_override == held.footprint[2],"Flash retains footprint geometry and gobo material")

static func parameters(frame: Dictionary, target: int) -> Dictionary:
	var d: PackedInt32Array = frame.get("descriptors",PackedInt32Array())
	var ints: PackedInt32Array = frame.get("integers",PackedInt32Array())
	var floats: PackedFloat32Array = frame.get("floats",PackedFloat32Array())
	for b in range(0,d.size(),5):
		if d[b] != 16: continue
		for row in range(d[b+1]):
			if ints[d[b+2]+row*10+1] == target:
				var f: int = d[b+3]+row*7
				return {"frequency":floats[f],"phase":floats[f+4],"mode":ints[d[b+2]+row*10+3],"status":ints[d[b+2]+row*10+5],"activation":ints[d[b+2]+row*10+7]}
	return {"frequency":-1.0,"phase":-1.0}
