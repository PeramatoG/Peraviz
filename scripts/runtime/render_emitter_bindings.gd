extends RefCounted

# Setup/resource ownership only. Native code classifies optics and accumulates every live contribution.
const INDIVIDUAL: int = 0
const AGGREGATED: int = 1

class RenderRow:
	var id: int
	var presentation_class: int = INDIVIDUAL
	var members: PackedInt32Array
	var output: RefCounted

var rows: Array[RenderRow] = []
var membership: PackedInt32Array = PackedInt32Array()
var _aggregates: Array = []

func clear(adapter: RefCounted) -> void:
	for output in _aggregates:
		for handle in output.lights:
			adapter._disconnect_handle(handle)
			if is_instance_valid(handle.light):
				if adapter._renderer != null: adapter._renderer.cleanup_beam(handle.light)
				handle.light.free()
	_aggregates.clear()
	rows.clear()
	membership = PackedInt32Array()

func install(adapter: RefCounted, descriptors: Array) -> bool:
	clear(adapter)
	membership.resize(adapter._outputs.size())
	membership.fill(-1)
	var indices: Dictionary = {}
	for output in adapter._outputs: indices[output.canonical_id] = output.index
	var settings: Dictionary = adapter._loader.get("_visual_settings")
	var enabled: bool = adapter._renderer != null and adapter._renderer.has_method("bind_control_group") and int(settings.get("beam_presentation", 1)) == 1 and not bool(settings.get("enable_realtime_spotlights", false)) and not bool(settings.get("beam_debug_optics", false)) and not adapter._diagnostic_open_surface_lights
	for descriptor in descriptors:
		if not enabled or int(descriptor.get("presentation_class", INDIVIDUAL)) != AGGREGATED: continue
		var members := PackedInt32Array()
		var safe: bool = is_instance_valid(descriptor.get("anchor"))
		for canonical in descriptor["physical_ids"]:
			if not indices.has(canonical): safe = false; break
			var index: int = indices[canonical]
			if membership[index] >= 0 or adapter._outputs[index].lights.size() != 1: safe = false; break
			var light = adapter._outputs[index].lights[0]
			if not light.projected or light.has_gobo or (is_instance_valid(light.debug_axis) and light.debug_axis.visible): safe = false; break
			if not members.is_empty() and adapter._route_signatures[index][2] != adapter._route_signatures[members[0]][2]: safe = false; break
			members.append(index)
		if not safe or members.size() < 3: continue
		var output: RefCounted = adapter._create_aggregate_output(descriptor, int(members[0]))
		if output == null: continue
		_aggregates.append(output)
		var row := RenderRow.new()
		row.id = rows.size() + 1
		row.presentation_class = AGGREGATED
		row.members = members
		row.output = output
		for index in members:
			membership[index] = rows.size()
			# Setup-only retirement; aggregate zero-crossings never revisit these members.
			for handle in adapter._outputs[index].lights:
				adapter._hide_bound_node(handle.beam, &"beam_visibility_writes")
				adapter._hide_bound_node(handle.debug_axis, &"debug_axis_visibility_writes")
				adapter._set_spot_rid(handle, false)
		rows.append(row)
	for output in adapter._outputs:
		if membership[output.index] >= 0: continue
		var row := RenderRow.new()
		row.id = rows.size() + 1
		row.members = PackedInt32Array([output.index])
		row.output = output
		membership[output.index] = rows.size()
		rows.append(row)
	var classes := PackedInt32Array()
	for row in rows: classes.append(row.presentation_class)
	return adapter._native.install_render_rows(membership, classes)

func aggregate_outputs() -> Array:
	return _aggregates

# Resource counts are sampled only at binding/trace boundaries, never by a live SceneTree scan.
func counts(adapter: RefCounted) -> Dictionary:
	var counts: Dictionary = {"render_groups": rows.size(), "aggregated_groups": _aggregates.size(), "aggregated_members": 0,
		"individual": 0, "largest_render_group": 0, "physical_projected_outputs": 0,
		"allocated_member_shafts": 0, "visible_member_shafts": 0, "aggregate_shaft_resources": 0,
		"visible_aggregate_shafts": 0, "total_visible_vector_prism_shafts": 0}
	for row in rows:
		counts["largest_render_group"] = maxi(int(counts["largest_render_group"]), row.members.size())
		if row.presentation_class == AGGREGATED: counts["aggregated_members"] += row.members.size()
		else: counts["individual"] += 1
	for output in adapter._outputs:
		for handle in output.lights:
			if handle.projected: counts["physical_projected_outputs"] += 1
			if is_instance_valid(handle.beam):
				counts["allocated_member_shafts"] += 1
				if handle.beam.is_visible_in_tree(): counts["visible_member_shafts"] += 1
	for output in _aggregates:
		for handle in output.lights:
			if is_instance_valid(handle.beam):
				counts["aggregate_shaft_resources"] += 1
				if handle.beam.is_visible_in_tree(): counts["visible_aggregate_shafts"] += 1
	counts["total_visible_vector_prism_shafts"] = counts["visible_member_shafts"] + counts["visible_aggregate_shafts"]
	return counts
