extends Node3D

const OVERLAY_META := &"peraviz_selection_overlay"
var _selection: SceneSelection
var _overlays: Dictionary = {}
var _sources: Dictionary = {}
var _links: Dictionary = {}
var _visibility_callbacks: Dictionary = {}
var _material: ShaderMaterial

func configure(state: SceneSelection) -> void:
	_selection = state
	_material = ShaderMaterial.new()
	_material.shader = preload("res://scripts/shaders/selection_fill.gdshader")
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://scripts/shaders/selection_outline.gdshader")
	_material.next_pass = outline
	_selection.changed.connect(_refresh)
	_refresh()

# Selection alone walks subtrees. Source material/overlay properties and visual-child
# admission stay intact; engine transform notifications follow articulation.
func _refresh() -> void:
	var wanted: Dictionary = {}
	for id in _selection.ids:
		var node := _selection.node_for(id)
		if node != null: _collect(node, wanted)
	for key in _overlays.keys():
		if not wanted.has(key): _remove(key)
	for key in wanted:
		var source: MeshInstance3D = wanted[key]
		if _overlays.has(key):
			var existing: MeshInstance3D = _overlays[key]
			if is_instance_valid(existing): existing.mesh = source.mesh
			continue
		var overlay := MeshInstance3D.new()
		overlay.name = "SelectionHighlight"
		overlay.set_meta(OVERLAY_META, true)
		overlay.mesh = source.mesh
		overlay.material_override = _material
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		overlay.layers = source.layers
		add_child(overlay)
		overlay.global_transform = source.global_transform
		if source.skin != null:
			overlay.skin = source.skin
			var skeleton := source.get_node_or_null(source.skeleton)
			if skeleton != null: overlay.skeleton = overlay.get_path_to(skeleton)
		# A nonvisual link preserves native lens admission's no-visual-children rule.
		var link := RemoteTransform3D.new()
		link.name = "SelectionTransformLink"
		link.set_meta(OVERLAY_META, true)
		source.add_child(link)
		link.remote_path = link.get_path_to(overlay)
		_overlays[key] = overlay
		_sources[key] = weakref(source)
		_links[key] = weakref(link)
		var visibility_callback: Callable = _sync_visibility.bind(key)
		_visibility_callbacks[key] = visibility_callback
		source.visibility_changed.connect(visibility_callback)
		source.tree_exiting.connect(_remove.bind(key), CONNECT_ONE_SHOT)
		_sync_visibility(key)

func _remove(key: int) -> void:
	if not _overlays.has(key): return
	var source: MeshInstance3D = _sources[key].get_ref()
	if is_instance_valid(source):
		if source.visibility_changed.is_connected(_visibility_callbacks[key]): source.visibility_changed.disconnect(_visibility_callbacks[key])
		if source.tree_exiting.is_connected(_remove.bind(key)): source.tree_exiting.disconnect(_remove.bind(key))
	var link: RemoteTransform3D = _links[key].get_ref()
	if is_instance_valid(link):
		link.remote_path = NodePath()
		link.get_parent().remove_child(link)
		link.queue_free()
	var overlay: MeshInstance3D = _overlays[key]
	if is_instance_valid(overlay):
		overlay.hide()
		# Retire renderer bindings while shared materials are still alive.
		overlay.mesh = null
		overlay.material_override = null
		remove_child(overlay)
		overlay.queue_free()
	_overlays.erase(key)
	_sources.erase(key)
	_links.erase(key)
	_visibility_callbacks.erase(key)

func _sync_visibility(key: int) -> void:
	if not _overlays.has(key): return
	var source: MeshInstance3D = _sources[key].get_ref()
	var overlay: MeshInstance3D = _overlays[key]
	if is_instance_valid(overlay): overlay.visible = is_instance_valid(source) and source.is_visible_in_tree()

func _collect(node: Node, wanted: Dictionary) -> void:
	if node is Light3D or node.has_meta(OVERLAY_META): return
	if node is MeshInstance3D and node.mesh != null:
		wanted[node.get_instance_id()] = node
	for child in node.get_children(): _collect(child, wanted)

func _exit_tree() -> void:
	for key in _overlays.keys(): _remove(key)

func refresh_meshes() -> void:
	_refresh()
