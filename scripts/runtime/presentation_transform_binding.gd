extends RefCounted

# Presentation-only bridge. Mechanical geometry and local Optical Projection State
# keep their existing authorities; the carrier owns only the mechanical world pose.
var source: Node3D
var anchor: SpotLight3D
var carrier: Node3D
var physical_output_id: int
var output_index: int
var emitter_local_transform: Transform3D
var last_applied_world_transform: Transform3D
var active_index: int = -1
var shaft_active: bool = false
var projector_active: bool = false
var diagnostic_active: bool = false
var pending_trace: bool = false
var detached: bool = false
var _original_parent: Node
var _original_index: int

func install(light: SpotLight3D, canonical_id: int, dense_index: int, detach: bool) -> void:
	anchor = light
	physical_output_id = canonical_id
	output_index = dense_index
	_original_parent = light.get_parent()
	_original_index = light.get_index()
	source = light.get_parent_node_3d()
	emitter_local_transform = light.transform
	last_applied_world_transform = source.global_transform if source != null else Transform3D.IDENTITY
	detached = detach
	if not detach: return
	# Keep local optical transforms untouched (roll, lens offset, parity, Zoom).
	# Reparent within the same owner subtree; deletion still follows the fixture.
	var previous_owner: Node = light.owner
	carrier = Node3D.new()
	carrier.name = "PresentationTransformCarrier"
	carrier.set_meta("peraviz_presentation_transform_carrier", true)
	_original_parent.add_child(carrier)
	carrier.top_level = true
	carrier.global_transform = last_applied_world_transform
	light.reparent(carrier, false)
	light.owner = previous_owner

# The caller visits active bindings only. Godot's standard transform tolerance
# prevents redundant writes while preserving the current mechanical pose.
func synchronize() -> bool:
	if not detached or not is_instance_valid(carrier): return false
	if source != null and not is_instance_valid(source): return false
	var world: Transform3D = source.global_transform if source != null else Transform3D.IDENTITY
	if world.is_equal_approx(last_applied_world_transform): return false
	carrier.global_transform = world
	last_applied_world_transform = world
	return true

func release() -> void:
	if is_instance_valid(carrier):
		if is_instance_valid(anchor) and is_instance_valid(_original_parent):
			var previous_owner: Node = anchor.owner
			anchor.reparent(_original_parent, false)
			_original_parent.move_child(anchor, mini(_original_index, _original_parent.get_child_count() - 1))
			anchor.owner = previous_owner
		carrier.free()
	carrier = null
	anchor = null
	source = null
	_original_parent = null
