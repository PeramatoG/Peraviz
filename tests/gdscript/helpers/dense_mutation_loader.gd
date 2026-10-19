extends "res://tests/gdscript/helpers/coalescing_loader.gd"

class ProbeLight extends SpotLight3D:
	var visibility_notifications: int = 0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED: visibility_notifications += 1

var _active_beam_renderer: BeamRendererBase
var dense_service: RefCounted
var vector_prism: bool = false
var projector_refreshes: int = 0

func _ready() -> void:
	if vector_prism:
		renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd").new()
	_active_beam_renderer = renderer
	for index in range(output_count):
		var anchor := ProbeLight.new()
		anchors.append(anchor)
		add_child(anchor)
		renderer.ensure_beam(anchor)
		var record: Dictionary = _output(40000 + index, anchor, true)
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		record["lens_material_targets"] = [{"material": material, "beam_optical_profile": {"emission_lumen_scale": 1.0}}]
		outputs.append(record)

func _refresh_native_gobo_presentation(light: SpotLight3D) -> void:
	projector_refreshes += 1
	var active: bool = dense_service._render_diagnostic_mode == "full" and bool(dense_service._light_desired_for(light).get("visible", false))
	var texture: Texture2D = light.get_meta("peraviz_gobo_texture") if active and light.has_meta("peraviz_gobo_texture") else null
	if light.light_projector != texture: light.light_projector = texture
	# Match the production callback that previously entered the competing visibility writer.
	dense_service._apply_desired_light_state(self, light)

func notification_count() -> int:
	var count: int = 0
	for anchor in anchors: count += anchor.visibility_notifications
	return count

func get_dense_presentation_bindings() -> Dictionary:
	var ids := PackedInt32Array()
	var scales := PackedFloat32Array()
	var routes := PackedInt32Array()
	for index in range(outputs.size()):
		ids.append(40000 + index)
		scales.append(1.0)
		routes.append_array(PackedInt32Array([2,10000+index,index,3,20000+index,index]))
	return {"ids": ids, "scales": scales, "routes": routes, "outputs": outputs}

func frame(level: float, red: float) -> Dictionary:
	var integers := PackedInt32Array()
	var floats := PackedFloat32Array()
	integers.resize(output_count * 6)
	floats.resize(output_count * 9)
	for index in range(output_count):
		var ib: int = index * 3
		var fb: int = index * 5
		integers[ib] = 1
		integers[ib+1] = 10000+index
		integers[ib+2] = 2
		floats[fb] = level
		floats[fb+1] = level*20
		floats[fb+2] = level*16
		floats[fb+3] = level*20
		floats[fb+4] = level*4
		ib = output_count*3+index*3
		fb = output_count*5+index*4
		integers[ib] = 1
		integers[ib+1] = 20000+index
		integers[ib+2] = 4
		floats[fb] = red
		floats[fb+1] = float(index)/float(output_count)
		floats[fb+2] = 0.7
		floats[fb+3] = 1.0
	return {"descriptors": PackedInt32Array([2,output_count,0,0,0,3,output_count,output_count*3,output_count*5,0]), "integers": integers, "floats": floats}
