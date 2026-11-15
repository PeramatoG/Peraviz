extends Node3D

const BEVEL: float = 0.68
var view_camera: Camera3D
var patches: Array[Dictionary] = []
var _face_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _hover_material: StandardMaterial3D
var _ring: MeshInstance3D
var _compass_labels: Array[Label3D] = []
var _cardinal_directions := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
var _cardinal_names := ["N", "E", "S", "W"]

func build() -> void:
	_face_material = _material(Color("dedede"))
	_edge_material = _material(Color("9ca1a8"))
	_hover_material = _material(preload("res://scripts/ui/ui_palette.gd").AMBER)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.TRANSPARENT
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 0.6
	light.shadow_enabled = false
	add_child(light)
	view_camera = Camera3D.new()
	view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	view_camera.size = 4.6
	view_camera.near = 0.05
	view_camera.far = 20.0
	view_camera.current = true
	add_child(view_camera)
	for x in [-1,0,1]:
		for y in [-1,0,1]:
			for z in [-1,0,1]:
				if x == 0 and y == 0 and z == 0: continue
				_add_patch(Vector3(x,y,z))
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.55
	torus.rings = 48
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.position.y = -1.3
	_ring.material_override = _edge_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	for i in range(4):
		var label := _label(_cardinal_names[i], Color("aab0b8"), 25)
		label.position = _cardinal_directions[i] * 1.8 + Vector3.DOWN * 1.3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 3
		label.outline_modulate = Color.BLACK
		add_child(label)
		_compass_labels.append(label)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

# Beveled geometry provides actual 6 face, 12 edge and 8 corner render/hit surfaces.
func _add_patch(direction: Vector3) -> void:
	var normal := direction.normalized()
	var axes: Array[int] = []
	for axis in range(3):
		if direction[axis] != 0: axes.append(axis)
	var vertices := PackedVector3Array()
	if axes.size() == 1:
		var u := Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.UP
		var v := normal.cross(u)
		vertices = PackedVector3Array([normal-u*BEVEL-v*BEVEL,normal+u*BEVEL-v*BEVEL,normal+u*BEVEL+v*BEVEL,normal-u*BEVEL+v*BEVEL])
	elif axes.size() == 2:
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		var free := Vector3.ZERO
		a[axes[0]] = direction[axes[0]]
		b[axes[1]] = direction[axes[1]]
		free[3-axes[0]-axes[1]] = BEVEL
		vertices = PackedVector3Array([a+b*BEVEL-free,a*BEVEL+b-free,a*BEVEL+b+free,a+b*BEVEL+free])
	else:
		vertices = PackedVector3Array([Vector3(direction.x,direction.y*BEVEL,direction.z*BEVEL),Vector3(direction.x*BEVEL,direction.y,direction.z*BEVEL),Vector3(direction.x*BEVEL,direction.y*BEVEL,direction.z)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var normals := PackedVector3Array()
	for i in range(vertices.size()): normals.append(normal)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3]) if vertices.size() == 4 else PackedInt32Array([0,1,2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _face_material if axes.size() == 1 else _edge_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var center := Vector3.ZERO
	for point in vertices: center += point / float(vertices.size())
	patches.append({"direction":normal,"vertices":vertices,"center":center,"instance":instance,"face":axes.size()==1})
	if axes.size() == 1:
		var title: String = "RIGHT" if direction.x > 0 else "LEFT"
		if direction.y != 0: title = "TOP" if direction.y > 0 else "BOTTOM"
		if direction.z != 0: title = "FRONT" if direction.z > 0 else "BACK"
		var label := _label(title, Color("17191c"), 32)
		label.position = normal * 1.015
		label.basis = Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP)
		add_child(label)

func _label(text_value: String, color: Color, font_size_value: int) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = font_size_value
	label.pixel_size = 0.01
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	return label

func orient(basis: Basis) -> void:
	view_camera.global_transform = Transform3D(basis, basis.z * 6.0)

func hover(direction: Vector3, compass: bool = false) -> void:
	for patch in patches:
		patch.instance.material_override = _hover_material if patch.direction.is_equal_approx(direction) else (_face_material if patch.face else _edge_material)
	_ring.material_override = _hover_material if compass else _edge_material

func show_compass(enabled: bool) -> void:
	_ring.visible = enabled
	for label in _compass_labels: label.visible = enabled

# Picking intersects the very triangles used for rendering, with no physics world work.
func hit_direction(point: Vector2) -> Vector3:
	var origin := view_camera.project_ray_origin(point)
	var end := origin + view_camera.project_ray_normal(point) * 20.0
	var nearest: float = INF
	var direction := Vector3.ZERO
	for patch in patches:
		var vertices: PackedVector3Array = patch.vertices
		for triangle in range(vertices.size()-2):
			var hit: Variant = Geometry3D.segment_intersects_triangle(origin,end,vertices[0],vertices[triangle+1],vertices[triangle+2])
			if hit is Vector3 and origin.distance_squared_to(hit) < nearest:
				nearest = origin.distance_squared_to(hit)
				direction = patch.direction
	return direction

func compass_hit(point: Vector2) -> Vector3:
	if not _ring.visible: return Vector3.ZERO
	var origin := view_camera.project_ray_origin(point)
	var ray := view_camera.project_ray_normal(point)
	if absf(ray.y) < 0.001: return Vector3.ZERO
	var t: float = (-1.3-origin.y)/ray.y
	if t < 0: return Vector3.ZERO
	var hit := origin + ray*t
	var radius := Vector2(hit.x,hit.z).length()
	if radius < 1.35 or radius > 2.05: return Vector3.ZERO
	return Vector3(hit.x,0,hit.z).normalized()

func patch_center(direction: Vector3) -> Vector2:
	for patch in patches:
		if patch.direction.is_equal_approx(direction.normalized()): return view_camera.unproject_position(patch.center)
	return Vector2(-1000,-1000)
