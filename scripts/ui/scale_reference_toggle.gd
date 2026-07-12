extends RefCounted

const SCALE_REFERENCE_CUBE_SIZE_M: float = 1.0

var _owner: Node3D
var _toggle: CheckButton
var _cube: MeshInstance3D

func configure(owner: Node3D, topbar_row: HBoxContainer, load_button: Button) -> void:
	_owner = owner
	if topbar_row == null or _toggle != null:
		return
	_toggle = CheckButton.new()
	_toggle.name = "ScaleReferenceToggle"
	_toggle.text = "1 m cube"
	_toggle.tooltip_text = "Show a 1 m x 1 m x 1 m reference cube at the scene origin"
	topbar_row.add_child(_toggle)
	var insert_index: int = max(load_button.get_index() + 1, 0) if load_button != null else 0
	topbar_row.move_child(_toggle, insert_index)
	_toggle.toggled.connect(_on_toggled)

func _on_toggled(enabled: bool) -> void:
	if enabled:
		_ensure_cube()
	else:
		_hide_cube()

func _ensure_cube() -> void:
	if _owner == null:
		return
	if _cube == null:
		_cube = MeshInstance3D.new()
		_cube.name = "ScaleReferenceCube1m"
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * SCALE_REFERENCE_CUBE_SIZE_M
		_cube.mesh = mesh
		_cube.position = Vector3(0.0, SCALE_REFERENCE_CUBE_SIZE_M * 0.5, 0.0)
		_cube.material_override = _create_material()
		_owner.add_child(_cube)
	_cube.visible = true

func _hide_cube() -> void:
	if _cube != null:
		_cube.visible = false

func _create_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.65, 1.0, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material
