extends MeshInstance3D

# Renderer resource only. OpticalProjectionState owns every optical calculation.
const META: StringName = &"peraviz_custom_footprint"
const SHADER = preload("res://scripts/shaders/custom_footprint.gdshader")
var visibility_callback: Callable
var projection: RefCounted
var max_range: float = 40.0
var parameter_updates: int = 0
var culled: bool = false
var _geometry_revision: int = -1
var _profile_revision: int = -1
var _source_id: int = -1
var _softness: float = -1.0
var _range_applied: float = -1.0
var _world: Transform3D
var _known_world: bool = false
var _bounds: AABB
var _bounds_known: bool = false
var _material: ShaderMaterial
static var _volume: ArrayMesh

func _init() -> void:
	name = "PeravizCustomFootprint"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true # Camera occlusion of a volume face is not receiver occlusion.
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	mesh = volume_mesh()
	set_notify_transform(true)

static func volume_mesh() -> ArrayMesh:
	if _volume != null: return _volume
	# Closed square pyramid, Godot clockwise outward winding. Only exit faces render, also when
	# the camera is inside; one fragment per covered pixel, no fullscreen quad.
	var corners := PackedVector3Array([Vector3.ZERO, Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1)])
	var vertices := PackedVector3Array()
	for index in [0,2,1, 0,3,2, 0,4,3, 0,1,4, 1,3,4, 1,2,3]: vertices.append(corners[index])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_volume = ArrayMesh.new()
	_volume.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _volume

func configure(state: RefCounted, range_m: float) -> void:
	if projection != state:
		_geometry_revision = -1
		_profile_revision = -1
		_source_id = -1
	projection = state
	max_range = clampf(range_m, 0.1, 500.0)
	sync()

func sync() -> void:
	if projection == null or not projection.configured or not is_inside_tree(): return
	if _geometry_revision != projection.geometry_revision or _range_applied != max_range:
		_geometry_revision = projection.geometry_revision
		_range_applied = max_range
		var tangent: float = tan(deg_to_rad(projection.half_angle_deg))
		# Footprint range is independent of the atmospheric shaft's cutoff.
		scale = Vector3(tangent * max_range, tangent * max_range, max_range)
		_material.set_shader_parameter("aperture_tangent", tangent)
		_material.set_shader_parameter("projection_range", max_range)
		parameter_updates += 1
	if _profile_revision != projection.profile_revision:
		_profile_revision = projection.profile_revision
		_material.set_shader_parameter("profile_parameters", projection.radial_profile.signature)
		_material.set_shader_parameter("profile_feather_start", projection.radial_profile.feather_start)
		parameter_updates += 1
	if _softness != projection.footprint_softness:
		_softness = projection.footprint_softness
		_material.set_shader_parameter("edge_softness", _softness)
		parameter_updates += 1
	var source: Texture2D = projection.pattern_texture
	var source_id: int = source.get_instance_id() if source != null else 0
	if _source_id != source_id:
		_source_id = source_id
		_material.set_shader_parameter("has_artwork", source != null)
		_material.set_shader_parameter("pattern_texture", source)
		var aspect := Vector2.ONE
		if source != null:
			var size := source.get_size()
			aspect = size / maxf(size.x, size.y)
		_material.set_shader_parameter("artwork_aspect", aspect)
		parameter_updates += 1
	_sync_world()
	_update_bounds()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and projection != null and is_inside_tree(): _sync_world()

func _sync_world() -> void:
	var anchor := get_parent() as Node3D
	if anchor == null: return
	var world := anchor.global_transform
	if _known_world and world.is_equal_approx(_world): return
	_world = world
	_known_world = true
	_material.set_shader_parameter("world_to_projector", world.affine_inverse())
	_material.set_shader_parameter("projector_origin", world.origin)
	parameter_updates += 1
	_update_bounds()

func set_receiver_bounds(bounds: AABB, known: bool) -> void:
	# Setup/edit boundary only: conservative scene-bounds broad phase, not a
	# collider-dependent center ray. Depth/frustum masks do the fine selection.
	_bounds = bounds
	_bounds_known = known
	_update_bounds()

func _update_bounds() -> void:
	culled = _bounds_known and not (global_transform * mesh.get_aabb()).intersects(_bounds.grow(0.01))
	visible = not culled
