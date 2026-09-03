extends RefCounted
class_name ShaderBeamProxyController

const META_KEY := "peraviz_shader_beam_proxy"
const STATE_META := "peraviz_shader_beam_proxy_state"
const SLICE_COUNT := 12
const RADIAL_SEGMENTS := 12

static var _shared_mesh: ArrayMesh
static var _shared_shader: Shader
static var _shared_material: ShaderMaterial
static var _topology_creations := 0
var _creations := 0
var _parameter_writes := 0
var _visibility_transitions := 0
var _texture_changes := 0
var _allocated_ids: Dictionary = {}
var _visible_ids: Dictionary = {}
var _tier_ids: Dictionary = {4: {}, 8: {}, 12: {}}

func update_for_light(light: SpotLight3D, params: Dictionary, texture: Texture2D) -> Dictionary:
	var beam_type: String = str(params.get("beam_type", "Wash")).to_lower()
	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var visible: bool = beam_type != "none" and beam_type != "glow" and intensity > float(params.get("intensity_visibility_threshold", 0.015))
	var proxy: MeshInstance3D = _get_proxy(light)
	if proxy == null and not visible:
		return {"changed": false, "parameter_write_count": 0}
	var created := false
	if proxy == null:
		proxy = _create_proxy(light)
		created = true
	var writes := 0
	if proxy.visible != visible:
		proxy.visible = visible
		_visibility_transitions += 1
		writes += 1
	if not visible:
		_set_visibility_diagnostics(light, false, 0)
		return {"changed": writes > 0, "resource_created": created, "parameter_write_count": writes}
	var beam_range: float = max(float(params.get("beam_range", 0.1)), 0.01)
	var beam_angle: float = max(float(params.get("beam_angle", 1.0)), 0.1)
	var aperture: float = max(float(params.get("lens_radius", params.get("aperture_radius", 0.0085))), 0.001)
	var radius_end: float = aperture + tan(deg_to_rad(beam_angle * 0.5)) * beam_range
	var transform_signature: Vector3 = Vector3(radius_end, beam_range, aperture)
	var state: Dictionary = proxy.get_meta(STATE_META, {})
	if state.get("transform") != transform_signature:
		proxy.position = Vector3(0.0, 0.0, -beam_range * 0.5)
		proxy.scale = Vector3(radius_end, radius_end, beam_range)
		state["transform"] = transform_signature
		writes += 1
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	writes += _set_param(proxy, state, "beam_dynamic_state", Color(beam_color.r, beam_color.g, beam_color.b, intensity))
	writes += _set_param(proxy, state, "intensity_max", intensity_max)
	writes += _set_param(proxy, state, "near_radius_ratio", clamp(aperture / radius_end, 0.0, 1.0))
	writes += _set_param(proxy, state, "gobo_rotation_deg", float(params.get("gobo_rotation_deg", 0.0)))
	writes += _set_param(proxy, state, "gobo_scale", max(float(params.get("gobo_scale", 1.0)), 0.05))
	writes += _set_param(proxy, state, "use_gobo", texture != null)
	if state.get("gobo_texture") != texture:
		proxy.set_instance_shader_parameter("gobo_texture", texture)
		state["gobo_texture"] = texture
		_texture_changes += 1
		writes += 1
	var tier: int = 12 if beam_angle <= 10.0 else (8 if beam_angle <= 25.0 else 4)
	writes += _set_param(proxy, state, "sample_tier", tier)
	state["quality_tier"] = tier
	_set_visibility_diagnostics(light, true, tier)
	proxy.set_meta(STATE_META, state)
	_parameter_writes += writes
	return {"changed": writes > 0, "resource_created": created, "parameter_write_count": writes}

func clear_for_light(light: SpotLight3D) -> void:
	var proxy := _get_proxy(light)
	if proxy != null:
		proxy.queue_free()
	light.remove_meta(META_KEY)
	var light_id := light.get_instance_id()
	_allocated_ids.erase(light_id)
	_set_visibility_diagnostics(light, false, 0)

func hide_for_light(light: SpotLight3D) -> void:
	var proxy := _get_proxy(light)
	if proxy != null and proxy.visible:
		proxy.visible = false
		_visibility_transitions += 1
		_set_visibility_diagnostics(light, false, 0)

func get_proxy(light: SpotLight3D) -> MeshInstance3D:
	return _get_proxy(light)

func counters() -> Dictionary:
	return {"allocated_shader_proxies": _allocated_ids.size(), "active_shader_proxies": _visible_ids.size(), "proxy_resource_creations": _creations, "proxy_topology_creations": _topology_creations, "proxy_topology_rebuilds": 0, "proxy_parameter_writes": _parameter_writes, "proxy_visibility_transitions": _visibility_transitions, "proxy_gobo_texture_changes": _texture_changes, "proxy_tier_4": (_tier_ids[4] as Dictionary).size(), "proxy_tier_8": (_tier_ids[8] as Dictionary).size(), "proxy_tier_12": (_tier_ids[12] as Dictionary).size()}

func _create_proxy(light: SpotLight3D) -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	proxy.name = "PeravizShaderBeamProxy"
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.mesh = _mesh()
	proxy.set_meta("peraviz_shader_beam_proxy_instance", true)
	proxy.material_override = _material()
	proxy.visible = false
	light.add_child(proxy)
	light.set_meta(META_KEY, proxy)
	_allocated_ids[light.get_instance_id()] = true
	_creations += 1
	return proxy

func _get_proxy(light: SpotLight3D) -> MeshInstance3D:
	if light == null or not light.has_meta(META_KEY):
		return null
	var proxy := light.get_meta(META_KEY) as MeshInstance3D
	return proxy if proxy != null and is_instance_valid(proxy) else null

func _set_param(proxy: MeshInstance3D, state: Dictionary, key: String, value: Variant) -> int:
	if state.get(key) == value:
		return 0
	proxy.set_instance_shader_parameter(key, value)
	state[key] = value
	return 1

func _set_visibility_diagnostics(light: SpotLight3D, visible: bool, tier: int) -> void:
	var light_id := light.get_instance_id()
	_visible_ids.erase(light_id)
	for tier_ids_item in _tier_ids.values():
		(tier_ids_item as Dictionary).erase(light_id)
	if visible:
		_visible_ids[light_id] = true
		(_tier_ids[tier] as Dictionary)[light_id] = true

static func _shader() -> Shader:
	if _shared_shader == null:
		_shared_shader = load("res://scripts/shaders/shader_beam_proxy.gdshader")
	return _shared_shader

static func _material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = _shader()
	return _shared_material

static func _mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for slice_index in range(SLICE_COUNT):
		var depth := (float(slice_index) + 0.5) / float(SLICE_COUNT)
		var base := vertices.size()
		vertices.append(Vector3(0.0, 0.0, 0.5 - depth))
		uvs.append(Vector2(0.5, 0.5))
		uv2s.append(Vector2(depth, float(slice_index)))
		for radial_index in range(RADIAL_SEGMENTS + 1):
			var angle := TAU * float(radial_index) / float(RADIAL_SEGMENTS)
			vertices.append(Vector3(cos(angle) * 0.5, sin(angle) * 0.5, 0.5 - depth))
			uvs.append(Vector2(cos(angle), sin(angle)) * 0.5 + Vector2(0.5, 0.5))
			uv2s.append(Vector2(depth, float(slice_index)))
		for radial_index in range(RADIAL_SEGMENTS):
			indices.append_array(PackedInt32Array([base, base + radial_index + 1, base + radial_index + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	_shared_mesh = ArrayMesh.new()
	_shared_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_topology_creations += 1
	return _shared_mesh
