extends RefCounted

const Volume = preload("res://scripts/beam_renderers/custom_footprint_volume.gd")
const Policy = preload("res://scripts/runtime/surface_light_policy.gd")
const ReceiverWatch = preload("res://scripts/runtime/footprint_receiver_watch.gd")
var volumes: Array[MeshInstance3D] = []
var _receivers: Array[WeakRef] = []
var _watches: Array[Node3D] = []
var _receiver_bounds: AABB
var _bounds_known: bool = false
var _receivers_pending: bool = false
var _receiver_setup: bool = false
var _warned_backend: bool = false
var _supported: bool = false

func clear(native: Object) -> void:
	_clear_volumes(native)
	for watch in _watches:
		if is_instance_valid(watch): watch.free()
	_watches.clear()
	_receivers.clear()
	_receiver_setup = false
	_receivers_pending = false
	_bounds_known = false

func _clear_volumes(native: Object) -> void:
	if native != null: native.clear_footprints()
	for volume in volumes:
		if not is_instance_valid(volume): continue
		_retire_volume(volume)
	volumes.clear()

func install(adapter: RefCounted) -> bool:
	# Revoke borrowed native RIDs before retiring any presentation resources.
	adapter._native.clear_footprints()
	var retained: Dictionary = {}
	for volume in volumes:
		if not is_instance_valid(volume): continue
		if volume.visibility_callback.is_valid() and volume.visibility_changed.is_connected(volume.visibility_callback):
			volume.visibility_changed.disconnect(volume.visibility_callback)
		retained[volume.get_parent().get_instance_id()] = volume
	volumes.clear()
	if not _receiver_setup:
		_receiver_setup = true
		if adapter._loader.get("_has_loaded_bounds") == true:
			_receiver_bounds = adapter._loader.get("_loaded_bounds")
			_bounds_known = true
		var scene_root: Node = adapter._loader.get("proxies_root")
		if scene_root != null: _subscribe_receivers(scene_root)
		# The application ground is outside imported Proxies and is still a
		# receiver. Excluding it can incorrectly cull valid open footprints.
		var ground := adapter._loader.get_node_or_null("Ground") as MeshInstance3D
		if ground != null:
			var bounds: AABB = ground.global_transform * ground.get_aabb()
			_receiver_bounds = _receiver_bounds.merge(bounds) if _bounds_known else bounds
			_bounds_known = true
			_subscribe_receivers(ground)
	var settings: Dictionary = adapter._loader.get("_visual_settings")
	var custom: bool = Policy.custom(settings)
	_supported = RenderingServer.get_current_rendering_method() == "forward_plus" and adapter._renderer != null and adapter._renderer.has_method("refresh_surface_profile")
	if custom and not _supported and not adapter._outputs.is_empty() and not _warned_backend:
		_warned_backend = true
		push_warning("Custom Footprints requires Forward+ and shared Vector Prism optics. Surface projection is disabled; select Native Footprints for this renderer.")
	var rids: Array = []
	var instances: Array = []
	var owners := PackedInt32Array()
	var scales := PackedFloat32Array()
	var routes := PackedInt32Array()
	for output in adapter._outputs:
		for handle in output.lights:
			var light: SpotLight3D = handle.light
			if not is_instance_valid(light): continue
			var backend_changed: bool = Policy.custom_light(light) != custom
			light.set_meta(Policy.BACKEND_META, "custom" if custom else "native")
			# This clears stale texture/shadow-mask state before any held replay.
			if (custom or backend_changed) and adapter._renderer != null and adapter._renderer.has_method("refresh_surface_profile"):
				adapter._renderer.refresh_surface_profile(light)
			if (custom or backend_changed) and handle.refresh_gobo.is_valid(): handle.refresh_gobo.call()
			if not custom or not handle.projected or not handle.projection.configured: continue
			if not _supported: continue
			var volume: MeshInstance3D = retained.get(light.get_instance_id())
			if volume == null:
				volume = Volume.new()
				light.add_child(volume)
				light.set_meta(Volume.META, volume)
			else: retained.erase(light.get_instance_id())
			volume.configure(handle.projection, float(settings.get("footprint_max_range", 40.0)))
			volumes.append(volume)
			volume.set_receiver_bounds(_receiver_bounds, _bounds_known)
			routes.append_array(PackedInt32Array([output.index, rids.size()]))
			rids.append(volume.material_override.get_rid())
			instances.append(volume.get_instance())
			owners.append(output.index)
			scales.append(maxf(float(settings.get("footprint_multiplier", 1.0)), 0.0))
	for volume in retained.values(): _retire_volume(volume)
	if not adapter._native.install_footprints(adapter._generation, rids, instances, owners, scales, routes): return false
	for index in range(volumes.size()):
		var volume: MeshInstance3D = volumes[index]
		volume.visibility_callback = _visibility_changed.bind(adapter._native, index, volume)
		volume.visibility_changed.connect(volume.visibility_callback)
		_visibility_changed(adapter._native, index, volume)
	return true

func _retire_volume(volume: MeshInstance3D) -> void:
	var anchor := volume.get_parent()
	if anchor != null: anchor.remove_meta(Volume.META)
	volume.free()

func _visibility_changed(native: Object, index: int, volume: MeshInstance3D) -> void:
	native.set_footprint_visible(index, volume.is_visible_in_tree())

func counts() -> Dictionary:
	var culled: int = 0
	var updates: int = 0
	for volume in volumes:
		if not is_instance_valid(volume): continue
		culled += 1 if volume.culled else 0
		updates += volume.parameter_updates
	return {"custom_footprint_supported": _supported, "custom_projector_resources": volumes.size(), "culled_custom_footprints": culled,
		"custom_projector_parameter_updates": updates}

# One setup traversal of scenery only. Do not subscribe fixtures, lenses, shafts
# or mechanical axes: Pan/Tilt invalidates the affected projector's transform.
func _subscribe_receivers(node: Node) -> void:
	if node is SpotLight3D or node.has_meta("peraviz_fixture_uuid") or str(node.get_meta("peraviz_type", "")) in ["fixture", "fixture_geometry"]: return
	if node is MeshInstance3D:
		_receivers.append(weakref(node))
		var watch := ReceiverWatch.new()
		watch.owner_ref = weakref(self)
		node.add_child(watch)
		_watches.append(watch)
		return
	for child in node.get_children(): _subscribe_receivers(child)

func receivers_moved() -> void:
	if _receivers_pending: return
	_receivers_pending = true
	# Suspend broad-phase rejection until the coalesced edit-boundary refresh.
	for volume in volumes: volume.set_receiver_bounds(_receiver_bounds, false)
	call_deferred("_refresh_receivers")

func _refresh_receivers() -> void:
	if not _receivers_pending: return
	_receivers_pending = false
	for receiver_ref in _receivers:
		var receiver: MeshInstance3D = receiver_ref.get_ref()
		if receiver == null: continue
		var bounds: AABB = receiver.global_transform * receiver.get_aabb()
		# Monotonic conservative bounds include the original imported scene and
		# moved scenery. No fixture-by-scene search and no physics-collider need.
		_receiver_bounds = _receiver_bounds.merge(bounds) if _bounds_known else bounds
		_bounds_known = true
	for volume in volumes: volume.set_receiver_bounds(_receiver_bounds, _bounds_known)
