extends RefCounted

const VisualSettingsMigration = preload("res://scripts/visual_settings_migration.gd")
const OpticalProjectionScript = preload("res://scripts/runtime/optical_projection_state.gd")

const BoundBeamStateScript = preload("res://scripts/beam_renderers/bound_beam_state.gd")

# Temporary milestone-1 renderer bridge. Native state owns composition; these
# handles only bind existing renderer objects. Delete with the batched backend.
const STRIDE: int = 12
const DIMMER: int = 1 << 1
const COLOR: int = 1 << 2
const ZOOM: int = 1 << 3
const MATERIAL: int = 1 << 8
const TOPOLOGY: int = 1 << 9

class MaterialHandle:
	var material: BaseMaterial3D
	var rid: RID
	var scale: float = 1.0
	var color: Color = Color(-1, -1, -1)
	var energy: float = -1.0

class LightHandle:
	var light: SpotLight3D
	var rid: RID
	var beam: MeshInstance3D
	var debug_axis: MeshInstance3D
	var has_gobo: bool = false
	var refresh_gobo: Callable
	# The retained renderer API requires this static, reused parameter object.
	var params: Dictionary
	var projected: bool
	var color: Color = Color.WHITE
	var energy: float = 0.0
	var projection: RefCounted
	var visible: bool = false
	var realtime_visible: bool = false
	var realtime_visibility_known: bool = false
	var realtime_requested: bool = false
	var properties_dirty: bool = true
	var suppressed: bool = false
	var initialization_failed: bool = false
	var visibility_callback: Callable
	var bound_state: RefCounted = BoundBeamStateScript.Cache.new()
	var compatibility_state: Dictionary = {}

class OutputHandle:
	var canonical_id: int
	var lights: Array[LightHandle] = []
	var materials: Array[MaterialHandle] = []

var _native: Object
var _generation: int = -1
var _outputs: Array[OutputHandle] = []
var _lights_by_id: Dictionary = {} # Setup-only lookup for cold gobo/diagnostic bridges.
var _payload: Dictionary = {}
var _loader: Node
var _service: WeakRef
var _renderer: BeamRendererBase
var _warned_unresolved: bool = false
var _warned_beam_initialization: bool = false
var _trace: bool = false
var _mode: String = "full"
var _surface_multiplier: float = 1.0
var _shaft_multiplier: float = 1.0
var _mutation_serial: int = 0
var _renderer_visibility_seen: int = 0
var _renderer_shader_seen: int = 0
var _renderer_debug_seen: int = 0
const MUTATION_COUNTERS: PackedStringArray = [
	"spot_node_visibility_writes", "spot_rid_visibility_writes", "beam_visibility_writes",
	"debug_axis_visibility_writes", "beam_shader_parameter_writes", "material_parameter_writes",
	"beam_initialization_succeeded", "beam_initialization_failed", "beam_resource_rebounds", "beam_topology_rebuilt",
	"spot_property_writes", "renderer_outputs_changed", "renderer_outputs_unchanged",
	"renderer_outputs_processed", "forced_replays", "mode_transition_replays",
	"visibility_resyncs", "projector_refresh_calls", "optics_apply_calls", "beam_initializations",
]
var _totals: Dictionary = {
	"native_compose_us": 0, "payload_conversion_us": 0, "semantic_payload_conversion_us": 0,
	"compatibility_adapter_us": 0, "renderer_mutation_us": 0,
	"native_dirty_outputs": 0,
}

func clear() -> void:
	for output in _outputs:
		for handle in output.lights:
			if is_instance_valid(handle.light) and handle.visibility_callback.is_valid():
				if handle.light.visibility_changed.is_connected(handle.visibility_callback): handle.light.visibility_changed.disconnect(handle.visibility_callback)
				if handle.light.tree_entered.is_connected(handle.visibility_callback): handle.light.tree_entered.disconnect(handle.visibility_callback)
			# The bound Callable contains this RefCounted handle; break that self-reference.
			handle.visibility_callback = Callable()
	_payload = {}
	if _native != null:
		_native.clear()
	_native = null
	_generation = -1
	_outputs.clear()
	_lights_by_id.clear()
	_loader = null
	_service = null
	_renderer = null

func install(loader: Node, service: RefCounted, registry: RefCounted) -> bool:
	clear()
	if not ClassDB.class_exists("PeravizPresentationState"):
		return false
	_loader = loader
	_trace = service._performance_trace_enabled
	_mode = service._render_diagnostic_mode
	for key in MUTATION_COUNTERS: _totals[key] = 0
	# Weak ownership avoids a service -> adapter -> service reference cycle.
	_service = weakref(service)
	_renderer = loader.get("_active_beam_renderer") as BeamRendererBase
	# Renderer counters may outlive a scene. Start this generation at its own boundary.
	_renderer_visibility_seen = _renderer.renderer_visibility_writes if _renderer != null else 0
	_renderer_shader_seen = _renderer.renderer_shader_parameter_writes if _renderer != null else 0
	_renderer_debug_seen = _renderer.renderer_debug_visibility_writes if _renderer != null else 0
	_native = ClassDB.instantiate("PeravizPresentationState")
	var bindings: Dictionary = registry.get_dense_presentation_bindings()
	for record in bindings["outputs"]:
		var output := OutputHandle.new()
		output.canonical_id = int(record["beam_render_target_id"])
		for entry in record.get("lens_material_targets", []):
			var material: BaseMaterial3D = entry.get("material") if entry is Dictionary else entry as BaseMaterial3D
			if material == null:
				continue
			var handle := MaterialHandle.new()
			handle.material = material
			handle.rid = material.get_rid()
			handle.scale = service._material_emission_scale(entry)
			output.materials.append(handle)
		for light in record.get("emitter_anchors", []):
			if not is_instance_valid(light):
				continue
			var handle := LightHandle.new()
			handle.light = light
			handle.rid = light.get_instance()
			handle.projection = OpticalProjectionScript.resolve(light)
			handle.projected = service._has_projected_beam(record.get("beam_optical_profile", {}))
			# Resolve static defaults, params and resources once, before live snapshots.
			if handle.projected and not light.has_meta("peraviz_beam_last_params"):
				service._apply_visual_frame_initial_light_state(loader, light, record.get("beam_optical_profile", {}), 0.0, Color.WHITE, 0.0, 0.0, 12.5, 25.0, 0.0, 0.0)
			handle.realtime_visibility_known = false
			handle.params = light.get_meta("peraviz_beam_last_params", {})
			handle.beam = loader._get_beam_resource_for_light(light)
			handle.debug_axis = light.get_meta("peraviz_beam_debug_axis") as MeshInstance3D if light.has_meta("peraviz_beam_debug_axis") else null
			handle.has_gobo = light.has_meta("peraviz_gobo_texture") and light.get_meta("peraviz_gobo_texture") != null
			if loader.has_method("_refresh_native_gobo_presentation"):
				handle.refresh_gobo = Callable(loader, "_refresh_native_gobo_presentation").bind(light)
			# Structural visibility changes only at binding/mode boundaries. A hidden
			# Node also stops Godot forwarding ancestor transforms to a suppressed RID.
			_set_structural_visibility(handle, _mode == "full")
			_set_spot_rid(handle, false)
			if is_instance_valid(handle.beam): handle.bound_state = BoundBeamStateScript.resolve(handle.beam)
			handle.visibility_callback = Callable(self, "_restore_spot_visibility").bind(handle)
			light.visibility_changed.connect(handle.visibility_callback)
			light.tree_entered.connect(handle.visibility_callback)
			output.lights.append(handle)
			_lights_by_id[light.get_instance_id()] = handle
		_outputs.append(output)
	_generation = _native.install(bindings["ids"], bindings["scales"], bindings["routes"])
	_sync_presentation_policy()
	if _mode != "full": _suppress_presentation_handles()
	return _generation >= 0

func is_installed() -> bool:
	return _native != null and _generation >= 0

func compose(descriptors: PackedInt32Array, integers: PackedInt32Array, values: PackedFloat32Array, trace: bool, mode: String, semantic_conversion_us: int = 0) -> bool:
	if not is_installed():
		return false
	_trace = trace
	if trace: _totals["semantic_payload_conversion_us"] += semantic_conversion_us
	if mode != _mode:
		if trace: _totals["mode_transition_replays"] += 1
		_mode = mode
		_sync_presentation_policy()
		if _mode != "full": _suppress_presentation_handles()
		_native.invalidate_renderer()
	_payload = {} # Release the borrowed packed buffers before native writes (no COW churn).
	_payload = _native.compose(_generation, descriptors, integers, values, trace)
	if not bool(_payload.get("valid", false)):
		push_error("Dense presentation rejected an invalid snapshot.")
		return false
	if int(_payload.get("unresolved_rows", 0)) > 0 and not _warned_unresolved:
		_warned_unresolved = true
		push_warning("Dense presentation has unresolved renderer control rows in this binding generation.")
	if trace:
		_totals["last_dirty_outputs"] = int(_payload["dirty_count"])
		_totals["native_compose_us"] += int(_payload["native_compose_us"])
		_totals["payload_conversion_us"] += int(_payload["payload_conversion_us"])
		_totals["native_dirty_outputs"] += int(_payload["dirty_count"])
	return true

func apply() -> void:
	if _payload.is_empty() or int(_payload.get("generation", -1)) != _generation:
		return
	if _mode == "transforms-only":
		_payload = {}
		return
	var start: int = Time.get_ticks_usec() if _trace else 0
	var indices: PackedInt32Array = _payload["indices_masks"]
	var values: PackedFloat32Array = _payload["values"]
	var settings: Dictionary = _loader.get("_visual_settings")
	_surface_multiplier = VisualSettingsMigration.surface_multiplier(settings)
	_shaft_multiplier = maxf(float(settings.get("beam_multiplier", 20.0)), 0.0) / 20.0
	var realtime: bool = bool(settings.get("enable_realtime_spotlights", false))
	var presentation: int = int(settings.get("beam_presentation", 1))
	var changed: int = 0
	# One clock pair for the complete mutation pass; never one clock per output.
	var mutation_start: int = Time.get_ticks_usec() if _trace else 0
	for row in range(int(_payload["count"])):
		var before: int = _mutation_serial
		_apply_output(_outputs[indices[row * 2]], values, row * STRIDE, indices[row * 2 + 1], realtime, presentation)
		if _trace and _mutation_serial != before: changed += 1
	if _trace:
		_totals["renderer_mutation_us"] += Time.get_ticks_usec() - mutation_start
		var service: RefCounted = _service.get_ref()
		var counters: Dictionary = service._visual_apply_counters
		counters["emitter_output_commit_candidates"] += int(_payload["candidates"])
		counters["emitter_output_commits_coalesced"] += int(_payload["candidates"]) - int(_payload["dirty_count"])
		counters["physical_outputs_considered"] += int(_payload["dirty_count"])
		counters["emitter_output_commits"] += int(_payload["count"])
		counters["emitter_output_commits_signature_skipped"] += int(_payload["signature_skipped"])
		counters["emitter_output_commit_usec"] += Time.get_ticks_usec() - start
		_totals["renderer_outputs_processed"] += int(_payload["dirty_count"])
		_totals["renderer_outputs_changed"] += changed
		_totals["renderer_outputs_unchanged"] += int(_payload["dirty_count"]) - changed
		_totals["compatibility_adapter_us"] += Time.get_ticks_usec() - start
	_payload = {}

func _apply_output(output: OutputHandle, v: PackedFloat32Array, b: int, mask: int, realtime: bool, presentation: int) -> void:
	var color := Color(v[b+1], v[b+2], v[b+3], 1.0)
	if mask & (DIMMER | COLOR | MATERIAL):
		for material in output.materials:
			var energy: float = v[b+7] * material.scale
			if material.color != color:
				RenderingServer.material_set_param(material.rid, "emission", color)
				material.color = color
				_record_mutation(&"material_parameter_writes")
			if not is_equal_approx(material.energy, energy):
				RenderingServer.material_set_param(material.rid, "emission_energy_multiplier", energy)
				material.energy = energy
				_record_mutation(&"material_parameter_writes")
	for handle in output.lights:
		if not is_instance_valid(handle.light): continue
		handle.color = color
		handle.energy = v[b+5] if v[b+5] > 0.0 else v[b+4]
		if mask & (ZOOM | TOPOLOGY):
			handle.params["beam_angle"] = v[b+9]
			handle.projection.configure(handle.params, handle.light.get_meta("peraviz_gobo_texture") as Texture2D if handle.light.has_meta("peraviz_gobo_texture") else null)
		var was_active: bool = handle.visible
		handle.visible = v[b+11] > 0.0 and handle.energy > 0.0 and handle.projected
		# Suppressed snapshots only update held scalar state and emissive materials.
		if _mode != "full" or not handle.projected:
			if not handle.suppressed:
				_hide_bound_node(handle.beam, &"beam_visibility_writes")
				_hide_bound_node(handle.debug_axis, &"debug_axis_visibility_writes")
				handle.suppressed = true
				if handle.has_gobo and handle.refresh_gobo.is_valid():
					handle.refresh_gobo.call()
					_record_event(&"projector_refresh_calls")
			_apply_spot(handle, realtime, presentation)
			continue
		var resuming: bool = handle.suppressed
		handle.suppressed = false
		if handle.has_gobo and (was_active != handle.visible or resuming) and handle.refresh_gobo.is_valid():
			handle.refresh_gobo.call()
			_record_event(&"projector_refresh_calls")
		_apply_spot(handle, realtime, presentation)
		if resuming: _set_structural_visibility(handle, true)
		handle.params["normalized_dimmer"] = clampf(v[b], 0.0, 1.0)
		handle.params["beam_color"] = color
		handle.params["beam_intensity"] = v[b+6] * _shaft_multiplier
		handle.params["scaled_intensity"] = v[b+6] * _shaft_multiplier
		handle.params["beam_angle"] = v[b+9]
		handle.params["intensity_max"] = 50.0
		if v[b+6] * _shaft_multiplier <= float(handle.params.get("intensity_visibility_threshold", 0.015)):
			_hide_bound_node(handle.debug_axis, &"debug_axis_visibility_writes")
		if _renderer == null: continue
		if mask & (ZOOM | TOPOLOGY):
			handle.initialization_failed = false
			var previous_mesh: Mesh = handle.beam.mesh if is_instance_valid(handle.beam) else null
			_renderer.apply_beam_optics(handle.light, handle.params)
			_bind_beam_resource(handle, _renderer.get_beam_resource(handle.light))
			if is_instance_valid(handle.beam) and handle.beam.mesh != previous_mesh: _record_mutation(&"beam_topology_rebuilt")
			_record_event(&"optics_apply_calls")
		var result: int = _renderer.update_bound_intensity(handle.light, handle.beam, handle.params, handle.bound_state)
		if result == BeamRendererBase.INTENSITY_UNRESOLVED and not handle.initialization_failed:
			_record_event(&"beam_initializations")
			_renderer.update_beam(handle.light, handle.params)
			_bind_beam_resource(handle, _renderer.get_beam_resource(handle.light))
			var ready: bool = is_instance_valid(handle.beam) and _renderer.is_beam_dynamic_ready(handle.light)
			_record_event(&"beam_initialization_succeeded" if ready else &"beam_initialization_failed")
			handle.initialization_failed = not ready
			if not ready and not _warned_beam_initialization:
				_warned_beam_initialization = true
				push_error("Dense presentation beam initialization failed; renderer resource is not ready.")
		_capture_renderer_mutations()
		if _trace:
			var counters: Dictionary = _service.get_ref()._visual_apply_counters
			counters["beams_considered"] += 1
			match result:
				BeamRendererBase.INTENSITY_CHANGED: counters["beam_dynamic_changed"] += 1
				BeamRendererBase.INTENSITY_UNCHANGED: counters["beam_dynamic_unchanged"] += 1
				BeamRendererBase.INTENSITY_UNRESOLVED: counters["beam_dynamic_unresolved"] += 1

# During full playback the Node supports beam children; only the RID follows DMX.
func _apply_spot(handle: LightHandle, realtime: bool, presentation: int) -> int:
	var before: int = _mutation_serial
	var enabled: bool = false
	if _mode == "full" and handle.visible:
		enabled = (realtime or handle.light.light_projector != null or presentation in [0, 2] or (presentation == 1 and handle.projection.smooth_profile_enabled and handle.projected)) and _surface_multiplier > 0.0
	if not enabled and _surface_multiplier <= 0.0 and handle.light.light_energy != 0.0:
		handle.light.light_energy = 0.0
		_record_mutation(&"spot_property_writes")
	if enabled:
		if handle.properties_dirty or not is_equal_approx(handle.light.light_energy, handle.energy * _surface_multiplier):
			handle.light.light_energy = handle.energy * _surface_multiplier
			_record_mutation(&"spot_property_writes")
		if handle.properties_dirty or not is_equal_approx(handle.light.spot_angle, handle.projection.half_angle_deg):
			handle.light.spot_angle = handle.projection.half_angle_deg
			_record_mutation(&"spot_property_writes")
		if handle.properties_dirty or handle.light.light_color != handle.color:
			handle.light.light_color = handle.color
			_record_mutation(&"spot_property_writes")
		handle.properties_dirty = false
	handle.realtime_requested = enabled
	_set_spot_rid(handle, enabled and handle.light.is_visible_in_tree())
	return _mutation_serial - before

func _set_spot_rid(handle: LightHandle, visible: bool) -> void:
	if not handle.realtime_visibility_known or handle.realtime_visible != visible:
		RenderingServer.instance_set_visible(handle.rid, visible)
		_record_mutation(&"spot_rid_visibility_writes")
	handle.realtime_visible = visible
	handle.realtime_visibility_known = true

# Godot sends its own instance visibility before this signal. Repair only a conflict.
func _restore_spot_visibility(handle: LightHandle) -> void:
	var node_visible: bool = handle.light.is_visible_in_tree()
	handle.realtime_visible = node_visible
	handle.realtime_visibility_known = true
	_set_spot_rid(handle, node_visible and handle.realtime_requested)
	if _trace: _totals["visibility_resyncs"] += 1

# Called only at binding and diagnostic-mode boundaries, never for DMX intensity.
func _set_structural_visibility(handle: LightHandle, visible: bool) -> void:
	if handle.light.visible != visible:
		handle.light.visible = visible
		_record_mutation(&"spot_node_visibility_writes")

func _suppress_presentation_handles() -> void:
	for output in _outputs:
		if _mode == "transforms-only":
			for material in output.materials:
				if material.energy != 0.0:
					RenderingServer.material_set_param(material.rid, "emission_energy_multiplier", 0.0)
					material.energy = 0.0
					_record_mutation(&"material_parameter_writes")
		for handle in output.lights:
			handle.realtime_requested = false
			_set_spot_rid(handle, false)
			_hide_bound_node(handle.beam, &"beam_visibility_writes")
			_hide_bound_node(handle.debug_axis, &"debug_axis_visibility_writes")
			_set_structural_visibility(handle, false)
			handle.suppressed = true
			if handle.has_gobo and handle.refresh_gobo.is_valid():
				handle.refresh_gobo.call()
				_record_event(&"projector_refresh_calls")

func _hide_bound_node(node: Node3D, counter: StringName) -> void:
	if is_instance_valid(node) and node.visible:
		node.visible = false
		_record_mutation(counter)

func _bind_beam_resource(handle: LightHandle, beam: MeshInstance3D) -> void:
	if handle.beam != beam:
		handle.initialization_failed = false
		_record_event(&"beam_resource_rebounds")
	handle.beam = beam
	if is_instance_valid(beam): handle.bound_state = BoundBeamStateScript.resolve(beam)

func _capture_renderer_mutations() -> void:
	if _renderer == null: return
	_record_mutation(&"beam_visibility_writes", _renderer.renderer_visibility_writes - _renderer_visibility_seen)
	_record_mutation(&"beam_shader_parameter_writes", _renderer.renderer_shader_parameter_writes - _renderer_shader_seen)
	_record_mutation(&"debug_axis_visibility_writes", _renderer.renderer_debug_visibility_writes - _renderer_debug_seen)
	_renderer_visibility_seen = _renderer.renderer_visibility_writes
	_renderer_shader_seen = _renderer.renderer_shader_parameter_writes
	_renderer_debug_seen = _renderer.renderer_debug_visibility_writes

# Boundary/cache events are diagnostics, not renderer-visible mutations.
func _record_event(counter: StringName) -> void:
	if _trace: _totals[counter] = int(_totals.get(counter,0)) + 1

func _record_mutation(counter: StringName, count: int = 1) -> void:
	if count <= 0: return
	_mutation_serial += count
	if not _trace: return
	_totals[counter] = int(_totals.get(counter, 0)) + count
	var service: RefCounted = _service.get_ref() if _service != null else null
	if service == null: return
	var counters: Dictionary = service._visual_apply_counters
	match counter:
		&"material_parameter_writes": counters["material_parameters_written"] += count
		&"spot_rid_visibility_writes": counters["light_visibility_calls"] += count
		&"spot_property_writes": counters["light_properties_written"] += count
		&"beam_visibility_writes": counters["beam_visibility_transitions"] += count
		&"beam_shader_parameter_writes": counters["beam_shader_parameters_written"] += count

# Cold gobo helpers use this entry instead of the old Node/RID visibility writers.
func apply_light_state(light: SpotLight3D) -> int:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	if handle == null: return -1
	var settings: Dictionary = _loader.get("_visual_settings")
	return _apply_spot(handle, bool(settings.get("enable_realtime_spotlights", false)), int(settings.get("beam_presentation", 1)))

# Mode changes replay held native state immediately, even without another DMX packet.
func _sync_presentation_policy() -> void:
	if _loader.has_method("_set_native_presentation_enabled"):
		_loader._set_native_presentation_enabled(_mode == "full")

func set_mode(mode: String) -> void:
	if mode == _mode or not is_installed(): return
	if _trace: _totals["mode_transition_replays"] += 1
	_mode = mode
	_sync_presentation_policy()
	if _mode != "full": _suppress_presentation_handles()
	_native.invalidate_renderer()
	compose(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), _trace, mode)
	apply()

# Cold bridge for gobo projector code; never used by the dense per-output loop.
func light_state(light: SpotLight3D) -> Dictionary:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	if handle == null:
		return {}
	handle.compatibility_state["energy"] = handle.energy
	handle.compatibility_state["angle"] = handle.projection.half_angle_deg
	handle.compatibility_state["color"] = handle.color
	handle.compatibility_state["visible"] = handle.visible
	handle.compatibility_state["applied_realtime_visible"] = handle.realtime_visible
	return handle.compatibility_state

func active_ids() -> Dictionary:
	var ids: Dictionary = {}
	for output in _outputs:
		for handle in output.lights:
			if handle.visible: ids[handle.light.get_instance_id()] = true
	return ids

func diagnostics() -> Dictionary:
	_capture_renderer_mutations()
	var result: Dictionary = _totals.duplicate()
	result["render_diagnostic_mode"] = _mode
	if _native != null: result.merge(_native.get_sizes())
	return result

# Only the once-per-report trace sampler resets these bounded interval counters.
func consume_diagnostics() -> Dictionary:
	var result: Dictionary = diagnostics()
	for key in MUTATION_COUNTERS: _totals[key] = 0
	for key in ["semantic_payload_conversion_us", "native_compose_us", "payload_conversion_us", "compatibility_adapter_us", "renderer_mutation_us", "native_dirty_outputs"]:
		_totals[key] = 0
	var service: RefCounted = _service.get_ref() if _service != null else null
	if service != null:
		var beams: int = 0
		var spots: int = 0
		for output in _outputs:
			for handle in output.lights:
				beams += 1 if is_instance_valid(handle.beam) and handle.beam.is_visible_in_tree() else 0
				spots += 1 if handle.realtime_visible and handle.light.is_visible_in_tree() else 0
		service._visual_apply_counters["beam_visible_count"] = beams
		service._visual_apply_counters["spotlight_visible_count"] = spots
	return result

# Setup/control-boundary refresh after a renderer, settings or gobo resource replacement.
func rebind_light(light: SpotLight3D) -> void:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	if handle != null:
		handle.params = light.get_meta("peraviz_beam_last_params", {})
		var beam: MeshInstance3D = _loader._get_beam_resource_for_light(light)
		if beam != handle.beam: handle.suppressed = false
		_bind_beam_resource(handle, beam)
		handle.debug_axis = light.get_meta("peraviz_beam_debug_axis") as MeshInstance3D if light.has_meta("peraviz_beam_debug_axis") else null
		handle.has_gobo = light.has_meta("peraviz_gobo_texture") and light.get_meta("peraviz_gobo_texture") != null
	_capture_renderer_mutations()

func refresh_renderer() -> void:
	if not is_installed(): return
	_capture_renderer_mutations()
	var renderer: BeamRendererBase = _loader.get("_active_beam_renderer") as BeamRendererBase
	if renderer != _renderer:
		_renderer = renderer
		_renderer_visibility_seen = renderer.renderer_visibility_writes if renderer != null else 0
		_renderer_shader_seen = renderer.renderer_shader_parameter_writes if renderer != null else 0
		_renderer_debug_seen = renderer.renderer_debug_visibility_writes if renderer != null else 0
	for output in _outputs:
		for handle in output.lights:
			if is_instance_valid(handle.light):
				rebind_light(handle.light)
				handle.realtime_visibility_known = false
				handle.properties_dirty = true
				handle.bound_state.invalidate()
			handle.initialization_failed = false
	if _trace: _totals["forced_replays"] += 1
	_native.invalidate_renderer()
	compose(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), _trace, _mode)
	apply()
