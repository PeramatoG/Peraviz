extends RefCounted

const VisualSettingsMigration = preload("res://scripts/visual_settings_migration.gd")
const OpticalProjectionScript = preload("res://scripts/runtime/optical_projection_state.gd")

const BoundBeamStateScript = preload("res://scripts/beam_renderers/bound_beam_state.gd")
const RenderBindings = preload("res://scripts/runtime/render_emitter_bindings.gd")
const SurfacePolicy = preload("res://scripts/runtime/surface_light_policy.gd")

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
	var shared_users: int = 1
	var scale: float = 1.0

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
	var output_index: int
	var has_projected_surface_profile: bool = false
	var owns_realtime_surface_light: bool = false
	var surface_counter_flags: int = 0
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

class ControlGroup:
	var members: Array = []
	var material: ShaderMaterial
	var materials: Array[MaterialHandle] = []
	var dynamic: Color = Color(-1, -1, -1, -1)
	var lens_copies: int = 0

class OutputHandle:
	var index: int
	var canonical_id: int
	var surface_profile_count: int = 0
	var lights: Array[LightHandle] = []
	var materials: Array[MaterialHandle] = []

var _native: Object
var _generation: int = -1
var _outputs: Array[OutputHandle] = []
var _groups: Array = []
var _binding_records: Array = []
var _render_bindings: RefCounted = RenderBindings.new()
var _render_descriptors: Array = []
var _control_fallbacks: Dictionary = {}
var _route_signatures: Array = []
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
var _renderer_dynamic_seen: int = 0
var _diagnostic_open_surface_lights: bool = false
var _surface_counts = SurfacePolicy.Counters.new()
const MUTATION_COUNTERS: PackedStringArray = [
	"physical_dynamic_candidates", "control_group_dynamic_updates", "beam_instance_writes_avoided",
	"lens_material_writes_avoided", "actual_beam_dynamic_renderer_writes", "actual_lens_material_renderer_writes",
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
	"native_physical_us": 0, "native_reduction_us": 0, "physical_color_outputs": 0, "lens_rids_affected": 0, "lens_rids_unchanged": 0, "native_dirty_outputs": 0, "native_material_us": 0,
}

func _disconnect_handle(handle: LightHandle) -> void:
	if is_instance_valid(handle.light) and handle.visibility_callback.is_valid():
		if handle.light.visibility_changed.is_connected(handle.visibility_callback): handle.light.visibility_changed.disconnect(handle.visibility_callback)
		if handle.light.tree_entered.is_connected(handle.visibility_callback): handle.light.tree_entered.disconnect(handle.visibility_callback)
	handle.visibility_callback = Callable()

func clear() -> void:
	_render_bindings.clear(self)
	_render_descriptors = []
	_control_fallbacks = {}
	for output in _outputs:
		for handle in output.lights: _disconnect_handle(handle)
	_retire_groups()
	_binding_records = []
	_route_signatures.clear()
	_payload = {}
	if _native != null:
		_native.clear()
	_native = null
	_generation = -1
	_outputs.clear()
	_surface_counts = SurfacePolicy.Counters.new()
	_lights_by_id.clear()
	_loader = null
	_service = null
	_renderer = null

func install(loader: Node, service: RefCounted, registry: RefCounted, budget: SceneLoadBudget = null) -> bool:
	clear()
	if not ClassDB.class_exists("PeravizPresentationState"):
		return false
	_loader = loader
	_trace = service._performance_trace_enabled
	_mode = service._render_diagnostic_mode
	_diagnostic_open_surface_lights = service._diagnostic_open_surface_lights
	for key in MUTATION_COUNTERS: _totals[key] = 0
	# Weak ownership avoids a service -> adapter -> service reference cycle.
	_service = weakref(service)
	_renderer = loader.get("_active_beam_renderer") as BeamRendererBase
	# Renderer counters may outlive a scene. Start this generation at its own boundary.
	_renderer_visibility_seen = _renderer.renderer_visibility_writes if _renderer != null else 0
	_renderer_shader_seen = _renderer.renderer_shader_parameter_writes if _renderer != null else 0
	_renderer_debug_seen = _renderer.renderer_debug_visibility_writes if _renderer != null else 0
	_renderer_dynamic_seen = _renderer.renderer_dynamic_parameter_writes if _renderer != null else 0
	_native = ClassDB.instantiate("PeravizPresentationState")
	var bindings: Dictionary = registry.get_dense_presentation_bindings()
	_binding_records = bindings["outputs"]
	_render_descriptors = bindings.get("render_groups", [])
	_control_fallbacks = {"split_dimmer_authority": 0, "split_color_authority": 0, "split_optics": 0,
		"split_projector_gobo": 0, "split_wheel": 0, "split_scaling": 0, "split_ambiguous": 0}
	_control_fallbacks.merge(bindings.get("control_fallbacks", {}), true)
	for i in range(_binding_records.size()): _route_signatures.append([[], 0, []])
	var routes: PackedInt32Array = bindings.get("authority_routes", bindings["routes"])
	for i in range(0, routes.size(), 3):
		var signature: Array = _route_signatures[routes[i+2]]
		if routes[i] == 3: signature[1] += 1
		else: signature[0 if routes[i] == 2 else 2].append(routes[i+1])
	for signature in _route_signatures:
		signature[0].sort()
		signature[2].sort()
	for record in bindings["outputs"]:
		if budget != null and not await budget.checkpoint(): return false
		var output := OutputHandle.new()
		output.index = _outputs.size()
		output.canonical_id = int(record["beam_render_target_id"])
		_outputs.append(output)
		if service._has_projected_beam(record.get("beam_optical_profile", {})):
			_surface_counts.projected_outputs += 1
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
			handle.output_index = _outputs.size() - 1
			# Resolve static defaults, params and resources once, before live snapshots.
			if handle.projected and not light.has_meta("peraviz_beam_last_params"):
				service._apply_visual_frame_initial_light_state(loader, light, record.get("beam_optical_profile", {}), 0.0, Color.WHITE, 0.0, 0.0, 12.5, 25.0, 0.0, 0.0)
			handle.realtime_visibility_known = false
			handle.params = light.get_meta("peraviz_beam_last_params", {})
			_refresh_surface_profile_count(handle)
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
	_generation = _native.install(bindings["ids"], bindings["scales"], bindings["routes"])
	if budget != null:
		await budget.checkpoint(true)
		budget.phase = "control_group_resources"
	_install_groups()
	if budget != null:
		await budget.checkpoint(true)
		budget.phase = "aggregate_resources"
	if not _install_render_bindings(): return false
	if budget != null:
		await budget.checkpoint(true)
		budget.phase = "final_runtime_install"
	_sync_presentation_policy()
	if _mode != "full": _suppress_presentation_handles()
	var summary: Dictionary = {"physical_outputs": _outputs.size(), "control_groups": _totals["presentation_control_groups"],
		"grouped_outputs": _totals["grouped_physical_outputs"], "individual_outputs": _totals["individual_physical_outputs"],
		"largest_control_group": _totals["largest_group"]}
	summary.merge(_native.get_sizes())
	summary.merge(bindings.get("render_diagnostics", {}))
	var settings: Dictionary = _loader.get("_visual_settings")
	summary["renderer_class"] = _renderer.get_script().resource_path if _renderer != null else "none"
	summary["rendering_method"] = RenderingServer.get_current_rendering_method()
	summary["beam_presentation"] = settings.get("beam_presentation", 1)
	summary["realtime_spotlights"] = settings.get("enable_realtime_spotlights", false)
	summary["debug_optics"] = settings.get("beam_debug_optics", false)
	summary["render_diagnostic_mode"] = _mode
	summary["diagnostic_open_surface_lights"] = _diagnostic_open_surface_lights
	summary.merge(_control_fallbacks)
	summary.merge(_render_bindings.counts(self))
	if not _outputs.is_empty(): print("[peraviz-render-groups] ", JSON.stringify(summary))
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
	return _accept_payload()

# Production calculation stays native; only compact rows and independent domains return.
func consume_runtime(runtime: Object, schema_generation: int, poll_only: bool = false) -> Dictionary:
	_payload = {}
	var boundary_start: int = Time.get_ticks_usec() if _trace else 0
	var snapshot: Dictionary = _native.consume_runtime(runtime, _generation, schema_generation, _trace, poll_only)
	if snapshot.get("pending", false): return snapshot
	_payload = snapshot.get("presentation", {})
	if _trace and not _payload.is_empty():
		var boundary_us: int = Time.get_ticks_usec() - boundary_start
		_totals["native_boundary_us"] = int(_totals.get("native_boundary_us", 0)) + boundary_us
		var measured_us: int = 0
		for key in ["native_material_us", "payload_conversion_us"]: measured_us += int(_payload.get(key, 0))
		if not _payload.get("native_async", false):
			for key in ["native_evaluation_us", "native_compose_us"]: measured_us += int(_payload.get(key, 0))
		_totals["boundary_overhead_us"] = int(_totals.get("boundary_overhead_us", 0)) + maxi(0, boundary_us - measured_us)
	snapshot.erase("presentation")
	snapshot["native_presentation"] = bool(snapshot.get("valid", false)) and _accept_payload()
	return snapshot

func _accept_payload() -> bool:
	if not bool(_payload.get("valid", false)):
		push_error("Dense presentation rejected an invalid snapshot.")
		return false
	if int(_payload.get("unresolved_rows", 0)) > 0 and not _warned_unresolved:
		_warned_unresolved = true
		push_warning("Dense presentation has unresolved renderer control rows in this binding generation.")
	if _trace:
		_totals["physical_dynamic_candidates"] += int(_payload.get("physical_dynamic_candidates", 0))
		var material_writes: int = int(_payload.get("lens_material_writes", 0))
		_totals["actual_lens_material_renderer_writes"] += material_writes
		_totals["lens_material_writes_avoided"] += int(_payload.get("lens_writes_avoided", 0))
		_record_mutation(&"material_parameter_writes", material_writes)
		for key in ["native_parallel_tasks", "native_worker_cpu_us", "native_task_wall_us", "native_coordination_us", "native_worker_failures", "native_serial_fallbacks", "native_serial_probes", "native_policy_backoffs", "native_completed_latency_us", "native_consumed_latency_us", "main_thread_publication_us", "native_evaluation_us", "intermediate_bytes_avoided", "intermediate_bytes_copied", "native_physical_us", "native_reduction_us", "physical_color_outputs", "lens_rids_affected", "lens_rids_unchanged"]: _totals[key] = int(_totals.get(key, 0)) + int(_payload.get(key, 0))
		_totals["native_workers_used"] = maxi(int(_totals.get("native_workers_used", 0)), int(_payload.get("native_workers_used", 0)))
		_totals["native_material_us"] += int(_payload.get("native_material_us", 0))
		_totals["renderer_mutation_us"] += int(_payload.get("native_material_us", 0))
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
		var render_row = _render_bindings.rows[indices[row * 2]]
		if render_row.presentation_class == 0:
			var group: ControlGroup = _groups[render_row.output.index] if not _groups.is_empty() else null
			if group != null: _apply_control_material(group, values, row * STRIDE)
		_apply_output(render_row.output, values, row * STRIDE, indices[row * 2 + 1], realtime, presentation)
		if _trace and _mutation_serial != before: changed += 1
	if _trace and _payload.has("candidates"):
		_totals["renderer_mutation_us"] += Time.get_ticks_usec() - mutation_start
		var service: RefCounted = _service.get_ref()
		var counters: Dictionary = service._visual_apply_counters
		counters["emitter_output_commit_candidates"] += int(_payload["candidates"])
		counters["emitter_output_commits_coalesced"] += int(_payload["candidates"]) - int(_payload["dirty_count"])
		counters["physical_outputs_considered"] += int(_payload["dirty_count"])
		counters["emitter_output_commits"] += int(_payload["count"])
		counters["emitter_output_commits_signature_skipped"] += int(_payload["signature_skipped"])
		counters["emitter_output_commit_usec"] += Time.get_ticks_usec() - start
		_totals["renderer_outputs_processed"] += int(_payload["count"])
		_totals["renderer_outputs_changed"] += changed
		_totals["renderer_outputs_unchanged"] += int(_payload["count"]) - changed
		_totals["compatibility_adapter_us"] += Time.get_ticks_usec() - start
	_payload = {}

func _apply_output(output: OutputHandle, v: PackedFloat32Array, b: int, mask: int, realtime: bool, presentation: int) -> void:
	var color := Color(v[b+1], v[b+2], v[b+3], 1.0)
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
	handle.owns_realtime_surface_light = _mode == "full" and handle.projected and _surface_multiplier > 0.0 and SurfacePolicy.owns_realtime_light(realtime, presentation, handle.light.light_projector != null, _diagnostic_open_surface_lights, handle.has_projected_surface_profile)
	if _mode == "full" and handle.visible:
		enabled = handle.owns_realtime_surface_light
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
	_update_surface_counts(handle)

func _refresh_surface_profile_count(handle: LightHandle) -> void:
	var resolved: bool = handle.projected and handle.projection.has_projected_surface_profile
	if resolved == handle.has_projected_surface_profile: return
	var output := _outputs[handle.output_index]
	var previous: bool = output.surface_profile_count > 0
	output.surface_profile_count += 1 if resolved else -1
	if previous != (output.surface_profile_count > 0):
		_surface_counts.surface_profiles += 1 if output.surface_profile_count > 0 else -1
	handle.has_projected_surface_profile = resolved

func _update_surface_counts(handle: LightHandle) -> void:
	var flags: int = SurfacePolicy.OWNED if handle.owns_realtime_surface_light else 0
	if handle.realtime_visible:
		flags |= SurfacePolicy.ACTIVE
		if handle.has_gobo or handle.light.light_projector != null:
			flags |= SurfacePolicy.PROJECTOR
			if handle.light.light_projector != null: flags |= SurfacePolicy.PROJECTOR_TEXTURE
			if handle.light.shadow_enabled: flags |= SurfacePolicy.SHADOWED_PROJECTOR
		else:
			flags |= SurfacePolicy.OPEN
			if not handle.light.shadow_enabled: flags |= SurfacePolicy.OPEN_SHADOWLESS
	_surface_counts.update(handle.surface_counter_flags, flags)
	handle.surface_counter_flags = flags

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
	for output in _outputs + _render_bindings.aggregate_outputs():
		for handle in output.lights:
			handle.realtime_requested = false
			handle.owns_realtime_surface_light = false
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
	if _trace: _totals["actual_beam_dynamic_renderer_writes"] += _renderer.renderer_dynamic_parameter_writes - _renderer_dynamic_seen
	_renderer_dynamic_seen = _renderer.renderer_dynamic_parameter_writes
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
	_surface_multiplier = VisualSettingsMigration.surface_multiplier(settings)
	return _apply_spot(handle, bool(settings.get("enable_realtime_spotlights", false)), int(settings.get("beam_presentation", 1)))

# Mode changes replay held native state immediately, even without another DMX packet.
func _sync_presentation_policy() -> void:
	if _native != null:
		var writes: int = _native.set_materials_enabled(_mode != "transforms-only")
		_record_mutation(&"material_parameter_writes", writes)
		if _trace: _totals["actual_lens_material_renderer_writes"] += writes
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
	var physical: PackedFloat32Array = _native.physical_values(handle.output_index)
	if not physical.is_empty():
		handle.color = Color(physical[1], physical[2], physical[3])
		handle.energy = physical[5] if physical[5] > 0.0 else physical[4]
		handle.visible = physical[11] > 0.0 and handle.energy > 0.0 and handle.projected
	handle.compatibility_state["energy"] = handle.energy
	var render_row: int = _render_bindings.membership[handle.output_index]
	handle.compatibility_state["angle"] = physical[8] if _render_bindings.rows[render_row].presentation_class == 1 else handle.projection.half_angle_deg
	handle.compatibility_state["color"] = handle.color
	handle.compatibility_state["visible"] = handle.visible
	handle.compatibility_state["applied_realtime_visible"] = handle.realtime_visible
	return handle.compatibility_state

func active_ids() -> Dictionary:
	var ids: Dictionary = {}
	for output in _outputs:
		for handle in output.lights:
			var physical: PackedFloat32Array = _native.physical_values(handle.output_index)
			if physical[11] > 0.0: ids[handle.light.get_instance_id()] = true
	return ids

func diagnostics() -> Dictionary:
	_capture_renderer_mutations()
	var result: Dictionary = _totals.duplicate()
	result["render_diagnostic_mode"] = _mode
	result["surface_lights"] = _surface_counts.snapshot()
	result["diagnostic_open_surface_lights"] = _diagnostic_open_surface_lights
	if _native != null: result.merge(_native.get_sizes())
	result.merge(_render_bindings.counts(self))
	result["control_groups"] = _totals.get("presentation_control_groups", _outputs.size())
	result.merge(_control_fallbacks)
	return result

# Only the once-per-report trace sampler resets these bounded interval counters.
func consume_diagnostics() -> Dictionary:
	var result: Dictionary = diagnostics()
	_surface_counts.reset_interval()
	for key in MUTATION_COUNTERS: _totals[key] = 0
	for key in ["native_boundary_us", "boundary_overhead_us", "semantic_payload_conversion_us", "native_compose_us", "payload_conversion_us", "compatibility_adapter_us", "renderer_mutation_us", "native_dirty_outputs", "native_material_us", "native_parallel_tasks", "native_workers_used", "native_worker_cpu_us", "native_task_wall_us", "native_coordination_us", "native_worker_failures", "native_serial_fallbacks", "native_serial_probes", "native_policy_backoffs", "native_completed_latency_us", "native_consumed_latency_us", "main_thread_publication_us", "native_evaluation_us", "intermediate_bytes_avoided", "intermediate_bytes_copied", "native_physical_us", "native_reduction_us", "physical_color_outputs", "lens_rids_affected", "lens_rids_unchanged"]:
		_totals[key] = 0
	var service: RefCounted = _service.get_ref() if _service != null else null
	if service != null:
		var beams: int = 0
		var spots: int = 0
		for output in _outputs:
			for handle in output.lights:
				beams += 1 if is_instance_valid(handle.beam) and handle.beam.is_visible_in_tree() else 0
				spots += 1 if handle.realtime_visible and handle.light.is_visible_in_tree() else 0
		beams += int(_render_bindings.counts(self)["visible_aggregate_shafts"])
		service._visual_apply_counters["beam_visible_count"] = beams
		service._visual_apply_counters["spotlight_visible_count"] = spots
	return result

# Setup/control-boundary refresh after a renderer, settings or gobo resource replacement.
func rebind_light(light: SpotLight3D, rebuild_groups: bool = true) -> void:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	var aggregated: bool = handle != null and handle.output_index < _render_bindings.membership.size() and _render_bindings.rows[_render_bindings.membership[handle.output_index]].presentation_class == 1
	if rebuild_groups and handle != null and (aggregated or (handle.output_index < _groups.size() and _groups[handle.output_index] != null)):
		refresh_renderer()
		return
	if handle != null:
		handle.params = light.get_meta("peraviz_beam_last_params", {})
		_refresh_surface_profile_count(handle)
		var beam: MeshInstance3D = _loader._get_beam_resource_for_light(light)
		if beam != handle.beam: handle.suppressed = false
		_bind_beam_resource(handle, beam)
		handle.debug_axis = light.get_meta("peraviz_beam_debug_axis") as MeshInstance3D if light.has_meta("peraviz_beam_debug_axis") else null
		handle.has_gobo = light.has_meta("peraviz_gobo_texture") and light.get_meta("peraviz_gobo_texture") != null
		_update_surface_counts(handle)
	_capture_renderer_mutations()

func refresh_renderer() -> void:
	if not is_installed(): return
	_capture_renderer_mutations()
	_render_bindings.clear(self)
	_retire_groups()
	var renderer: BeamRendererBase = _loader.get("_active_beam_renderer") as BeamRendererBase
	if renderer != _renderer:
		_renderer = renderer
		_renderer_visibility_seen = renderer.renderer_visibility_writes if renderer != null else 0
		_renderer_shader_seen = renderer.renderer_shader_parameter_writes if renderer != null else 0
		_renderer_debug_seen = renderer.renderer_debug_visibility_writes if renderer != null else 0
		_renderer_dynamic_seen = renderer.renderer_dynamic_parameter_writes if renderer != null else 0
	for output in _outputs:
		for handle in output.lights:
			if is_instance_valid(handle.light):
				rebind_light(handle.light, false)
				handle.realtime_visibility_known = false
				handle.properties_dirty = true
				handle.bound_state.invalidate()
			handle.initialization_failed = false
	_install_groups()
	if not _install_render_bindings(): return
	if _trace: _totals["forced_replays"] += 1
	_native.invalidate_renderer()
	compose(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), _trace, _mode)
	apply()

# Retires every setup-generation resource reference, including renderer-only replacement.
func _retire_groups() -> void:
	for representative in range(_groups.size()):
		var group: ControlGroup = _groups[representative]
		if group == null or group.members[0] != representative: continue
		for index in group.members:
			for light in _outputs[index].lights:
				if _renderer != null and _renderer.has_method("unbind_control_group"):
					_renderer.unbind_control_group(light.beam)
	_groups.clear()
	for output in _outputs:
		for material in output.materials:
			material.shared_users = 1

# Native IDs prove control authority. This cold pass additionally proves actual resource compatibility.
func _install_groups() -> void:
	_groups.resize(_outputs.size())
	_groups.fill(null)
	var representatives := PackedInt32Array()
	representatives.resize(_outputs.size())
	representatives.fill(-1)
	var candidates: Dictionary = {}
	var settings: Dictionary = _loader.get("_visual_settings")
	var can_share: bool = _renderer != null and _renderer.has_method("bind_control_group") and not _diagnostic_open_surface_lights and not bool(settings.get("enable_realtime_spotlights", false)) and not bool(settings.get("beam_debug_optics", false))
	for index in range(_outputs.size()):
		var id: int = int(_binding_records[index].get("presentation_control_group", 0))
		if can_share and id > 0:
			if not candidates.has(id): candidates[id] = []
			candidates[id].append(index)
	var grouped: int = 0
	var largest: int = 1 if not _outputs.is_empty() else 0
	var shared_lenses: int = 0
	var shared_beams: int = 0
	for members in candidates.values():
		if members.size() < 2: continue
		var beams: Array = []
		var safe: bool = true
		for index in members:
			if _outputs[index].lights.size() != 1: safe = false; break
			var light: LightHandle = _outputs[index].lights[0]
			if not light.projected or light.has_gobo or not is_instance_valid(light.beam): safe = false; break
			if is_instance_valid(light.debug_axis) and light.debug_axis.visible: safe = false; break
			if light.params.get("intensity_visibility_threshold", 0.015) != 0.015: safe = false; break
			if _route_signatures[index] != _route_signatures[members[0]]: safe = false; break
			if _route_signatures[index][0].size() != 1: safe = false; break
			beams.append(light.beam)
		if not safe: continue
		var material: ShaderMaterial = _renderer.bind_control_group(beams)
		if material == null: continue
		var group := ControlGroup.new()
		group.members = members
		group.material = material
		var lens_cache: Dictionary = {}
		for index in members:
			representatives[index] = int(members[0])
			_groups[index] = group
			var entries: Array = _binding_records[index].get("lens_material_targets", [])
			for lens_index in range(_outputs[index].materials.size()):
				var handle: MaterialHandle = _outputs[index].materials[lens_index]
				handle.shared_users = 1
				var entry: Variant = entries[lens_index]
				var source: Material = entry.get("source_material") if entry is Dictionary else null
				# Unknown materials remain distinct subgroups; source identity preserves static appearance.
				var key: Array = [source, handle.scale]
				if source is BaseMaterial3D and source.next_pass == null and entry.get("mesh") != null and entry["mesh"].material_override == null and lens_cache.has(key):
					var shared: MaterialHandle = lens_cache[key]
					shared.shared_users += 1
					handle.material = shared.material
					handle.rid = shared.rid
					entry["material"] = shared.material
					entry["mesh"].set_surface_override_material(int(entry["surface"]), shared.material)
					group.lens_copies += 1
				else:
					group.materials.append(handle)
					if source is BaseMaterial3D and source.next_pass == null and entry.get("mesh") != null and entry["mesh"].material_override == null: lens_cache[key] = handle
			grouped += 1
		largest = maxi(largest, members.size())
		shared_beams += 1
		if group.lens_copies > 0: shared_lenses += 1
	if not _native.install_groups(representatives):
		# A rejected actual binding must leave a fully independent renderer path.
		_retire_groups()
		_groups.resize(_outputs.size())
		_groups.fill(null)
		representatives.fill(-1)
		_native.install_groups(representatives)
		grouped = 0
		shared_beams = 0
		shared_lenses = 0
		largest = 1 if not _outputs.is_empty() else 0
	_totals["physical_outputs"] = _outputs.size()
	_totals["presentation_control_groups"] = _outputs.size() - grouped + shared_beams
	_totals["grouped_physical_outputs"] = grouped
	_totals["individual_physical_outputs"] = _outputs.size() - grouped
	_totals["largest_group"] = largest
	_totals["shared_beam_material_groups"] = shared_beams
	_totals["shared_lens_material_groups"] = shared_lenses

# Shared Control Groups still perform one material write, even across separated individual shafts.
func _apply_control_material(group: ControlGroup, v: PackedFloat32Array, b: int) -> void:
	var dynamic := Color(v[b+1], v[b+2], v[b+3], v[b+6] * _shaft_multiplier)
	if dynamic == group.dynamic: return
	group.dynamic = dynamic
	group.material.set_shader_parameter("control_group_dynamic_state", dynamic)
	_record_mutation(&"beam_shader_parameter_writes")
	if _trace:
		_totals["control_group_dynamic_updates"] += 1
		_totals["actual_beam_dynamic_renderer_writes"] += 1
		_totals["beam_instance_writes_avoided"] += group.members.size() - 1

# Setup once per renderer generation; lenses retain independent native physical routes.
func _install_render_bindings() -> bool:
	if not _render_bindings.install(self, _render_descriptors): return false
	var rids: Array = []
	var owners := PackedInt32Array()
	var scales := PackedFloat32Array()
	var routes := PackedInt32Array()
	var indices: Dictionary = {}
	for output in _outputs:
		for material in output.materials:
			if not indices.has(material.rid):
				indices[material.rid] = rids.size()
				rids.append(material.rid)
				owners.append(output.index)
				scales.append(material.scale)
			routes.append_array(PackedInt32Array([output.index, int(indices[material.rid])]))
	return _native.install_materials(rids, owners, scales, routes)

# Setup consumes native optical descriptors; this never classifies geometry or mixes live pixels.
func _create_aggregate_output(descriptor: Dictionary, representative: int) -> OutputHandle:
	var parent: Node3D = descriptor["anchor"] as Node3D
	if parent == null: return null
	var light := SpotLight3D.new()
	light.name = "PeravizAggregateEmitter"
	light.position = descriptor["origin"]
	var direction: Vector3 = descriptor["direction"]
	light.basis = Basis.looking_at(direction, Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD)
	light.light_energy = 0.0
	light.light_cull_mask = 0
	light.shadow_enabled = false
	parent.add_child(light)
	var params: Dictionary = _outputs[representative].lights[0].params.duplicate(true)
	params["lens_radius"] = float(descriptor["aperture_radius"])
	params["render_near_radius_m"] = float(descriptor["aperture_radius"])
	params["official_beam_radius_m"] = float(descriptor["aperture_radius"])
	params["beam_angle"] = float(descriptor["beam_angle"])
	params["field_angle"] = float(descriptor["field_angle"])
	params["scaled_intensity"] = 0.0
	params["beam_intensity"] = 0.0
	params["normalized_dimmer"] = 0.0
	light.set_meta("peraviz_beam_last_params", params)
	_renderer.update_beam(light, params)
	var output := OutputHandle.new()
	output.index = -1
	var handle := LightHandle.new()
	handle.light = light
	handle.rid = light.get_instance()
	handle.projected = true
	handle.output_index = representative
	handle.params = params
	handle.projection = OpticalProjectionScript.resolve(light)
	handle.beam = _renderer.get_beam_resource(light)
	if is_instance_valid(handle.beam): handle.bound_state = BoundBeamStateScript.resolve(handle.beam)
	handle.visibility_callback = Callable(self, "_restore_spot_visibility").bind(handle)
	light.visibility_changed.connect(handle.visibility_callback)
	light.tree_entered.connect(handle.visibility_callback)
	_set_spot_rid(handle, false)
	output.lights.append(handle)
	return output
