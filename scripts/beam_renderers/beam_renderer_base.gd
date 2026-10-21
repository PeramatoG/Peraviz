extends RefCounted

class_name BeamRendererBase

var _last_visibility_write_count: int = 0
# Constant-size cumulative call counts; the adapter only exports them when tracing.
var renderer_visibility_writes: int = 0
var renderer_shader_parameter_writes: int = 0
var renderer_dynamic_parameter_writes: int = 0
var renderer_debug_visibility_writes: int = 0

const INTENSITY_UNRESOLVED: int = 0
const INTENSITY_UNCHANGED: int = 1
const INTENSITY_CHANGED: int = 2

func configure(_view_camera: Camera3D, _settings: Dictionary) -> void:
	pass

func ensure_beam(_light: SpotLight3D) -> void:
	pass

func update_beam(_light: SpotLight3D, _params: Dictionary) -> void:
	pass

func is_beam_dynamic_ready(_light: SpotLight3D) -> bool:
	return false

func update_beam_intensity(_light: SpotLight3D, _params: Dictionary) -> int:
	return INTENSITY_UNRESOLVED

func get_last_parameter_write_count() -> int:
	return 0

func apply_beam_optics(_light: SpotLight3D, _params: Dictionary) -> Dictionary:
	return {"applied": false, "failure_reason": "renderer does not implement BeamOptics"}

func get_beam_optics_state(_light: SpotLight3D) -> Dictionary:
	return {}

func get_beam_resource(_light: SpotLight3D) -> MeshInstance3D:
	return null

func cleanup_beam(_light: SpotLight3D) -> void:
	pass

# Drops scene-specific resource caches after the owner retires its emitter nodes.
func reset_scene_state() -> void:
	pass

# Compatibility backends may reuse their existing implementation for uncommon modes.
func update_bound_intensity(light: SpotLight3D, _beam: MeshInstance3D, params: Dictionary, _bound: RefCounted = null) -> int:
	_last_visibility_write_count = 0
	return update_beam_intensity(light, params)

# Counts calls to the visibility setter, independently of dynamic shader writes.
func get_last_visibility_write_count() -> int:
	return _last_visibility_write_count

# Beam Nodes are their own visibility authority; no parallel direct RID visibility.
func _set_bound_visibility(node: Node3D, visible: bool) -> void:
	if node.visible != visible:
		node.visible = visible
		renderer_visibility_writes += 1

func _set_debug_visibility(node: Node3D, visible: bool) -> void:
	if node.visible != visible:
		node.visible = visible
		renderer_debug_visibility_writes += 1

func _set_bound_shader_parameter(beam: MeshInstance3D, key: StringName, value: Variant) -> void:
	beam.set_instance_shader_parameter(key, value)
	renderer_shader_parameter_writes += 1

func _set_bound_material_parameter(material: ShaderMaterial, key: StringName, value: Variant) -> void:
	material.set_shader_parameter(key, value)
	renderer_shader_parameter_writes += 1
