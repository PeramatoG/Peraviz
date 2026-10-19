extends RefCounted

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
	var half_angle: float = 12.5
	var visible: bool = false
	var realtime_visible: bool = false
	var realtime_visibility_known: bool = false
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
var _trace: bool = false
var _mode: String = "full"
var _totals: Dictionary = {
	"native_compose_us": 0, "payload_conversion_us": 0, "semantic_payload_conversion_us": 0,
	"compatibility_adapter_us": 0, "renderer_mutation_us": 0,
	"native_dirty_outputs": 0,
}

func clear() -> void:
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

func install(loader: Node, service: RefCounted, registry: RefCounted) -> void:
	clear()
	if not ClassDB.class_exists("PeravizPresentationState"):
		push_error("Native dense presentation service is required for playback.")
		return
	_loader = loader
	# Weak ownership avoids a service -> adapter -> service reference cycle.
	_service = weakref(service)
	_renderer = loader.get("_active_beam_renderer") as BeamRendererBase
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
			output.lights.append(handle)
			_lights_by_id[light.get_instance_id()] = handle
		_outputs.append(output)
	_generation = _native.install(bindings["ids"], bindings["scales"], bindings["routes"])
	if _generation < 0:
		push_error("Dense presentation bindings were rejected.")

func is_installed() -> bool:
	return _native != null and _generation >= 0

func compose(descriptors: PackedInt32Array, integers: PackedInt32Array, values: PackedFloat32Array, trace: bool, mode: String, semantic_conversion_us: int = 0) -> bool:
	if not is_installed():
		return false
	_trace = trace
	if trace: _totals["semantic_payload_conversion_us"] += semantic_conversion_us
	if mode != _mode:
		_native.invalidate_renderer()
	_mode = mode
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
	var service: RefCounted = _service.get_ref()
	var settings: Dictionary = _loader.get("_visual_settings")
	var realtime: bool = bool(settings.get("enable_realtime_spotlights", false))
	var presentation: int = int(settings.get("beam_presentation", 1))
	for row in range(int(_payload["count"])):
		var output: OutputHandle = _outputs[indices[row * 2]]
		var mask: int = indices[row * 2 + 1]
		var base: int = row * STRIDE
		var mutation_start: int = Time.get_ticks_usec() if _trace else 0
		_apply_output(output, values, base, mask, realtime, presentation, service)
		if _trace:
			_totals["renderer_mutation_us"] += Time.get_ticks_usec() - mutation_start
	if _trace:
		var counters: Dictionary = service._visual_apply_counters
		counters["emitter_output_commit_candidates"] += int(_payload["candidates"])
		counters["emitter_output_commits_coalesced"] += int(_payload["candidates"]) - int(_payload["dirty_count"])
		counters["physical_outputs_considered"] += int(_payload["dirty_count"])
		counters["emitter_output_commits"] += int(_payload["count"])
		counters["emitter_output_commits_signature_skipped"] += int(_payload["signature_skipped"])
		counters["emitter_output_commit_usec"] += Time.get_ticks_usec() - start
		_totals["compatibility_adapter_us"] += Time.get_ticks_usec() - start
	_payload = {} # No snapshot or history survives the mutation boundary.

func _apply_output(output: OutputHandle, v: PackedFloat32Array, b: int, mask: int, realtime: bool, presentation: int, service: RefCounted) -> void:
	var color := Color(v[b+1], v[b+2], v[b+3], 1.0)
	var force: bool = (mask & TOPOLOGY) != 0
	if mask & (DIMMER | COLOR | MATERIAL):
		for material in output.materials:
			var energy: float = v[b+7] * material.scale
			if force or material.color != color:
				RenderingServer.material_set_param(material.rid, "emission", color)
				material.color = color
				if _trace: service._visual_apply_counters["material_parameters_written"] += 1
			if force or not is_equal_approx(material.energy, energy):
				RenderingServer.material_set_param(material.rid, "emission_energy_multiplier", energy)
				material.energy = energy
				if _trace: service._visual_apply_counters["material_parameters_written"] += 1
	for handle in output.lights:
		if not is_instance_valid(handle.light):
			continue
		handle.color = color
		handle.energy = v[b+5] if v[b+5] > 0.0 else v[b+4]
		handle.half_angle = v[b+8]
		var was_active: bool = handle.visible
		handle.visible = v[b+11] > 0.0 and handle.energy > 0.0 and handle.projected
		if handle.has_gobo and was_active != handle.visible and handle.refresh_gobo.is_valid():
			handle.refresh_gobo.call()
		if not handle.projected:
			if is_instance_valid(handle.beam): handle.beam.visible = false
			continue
		var requires_spot: bool = handle.visible and (handle.light.light_projector != null or presentation in [0, 2])
		var enabled: bool = handle.visible and _mode == "full" and (realtime or requires_spot)
		var writes: int = 0
		if enabled:
			if force or not is_equal_approx(handle.light.light_energy, handle.energy):
				handle.light.light_energy = handle.energy
				writes += 1
			if force or not is_equal_approx(handle.light.spot_angle, handle.half_angle):
				handle.light.spot_angle = handle.half_angle
				writes += 1
			if force or handle.light.light_color != color:
				handle.light.light_color = color
				writes += 1
		handle.light.visible = v[b+11] > 0.0 if _mode == "full" else true
		var rid_visible: bool = handle.visible and (enabled or requires_spot)
		if not handle.realtime_visibility_known or handle.realtime_visible != rid_visible:
			RenderingServer.instance_set_visible(handle.rid, rid_visible)
			handle.realtime_visible = rid_visible
			handle.realtime_visibility_known = true
			if _trace: service._visual_apply_counters["light_visibility_calls"] += 1
		if _trace: service._visual_apply_counters["light_properties_written"] += writes
		if _mode != "full":
			if is_instance_valid(handle.debug_axis): handle.debug_axis.visible = false
			if is_instance_valid(handle.beam): handle.beam.visible = false
			continue
		# Preserve existing renderer implementation and static params; no target lookup.
		handle.params["normalized_dimmer"] = clampf(v[b], 0.0, 1.0)
		handle.params["beam_color"] = color
		handle.params["beam_intensity"] = v[b+6]
		handle.params["scaled_intensity"] = v[b+6]
		handle.params["beam_angle"] = v[b+9]
		handle.params["intensity_max"] = 50.0
		if v[b+6] <= float(handle.params.get("intensity_visibility_threshold", 0.015)) and is_instance_valid(handle.debug_axis):
			handle.debug_axis.visible = false
		if _renderer != null:
			if mask & (ZOOM | TOPOLOGY):
				_renderer.apply_beam_optics(handle.light, handle.params)
				# A structural optics/gobo operation may replace the existing beam resource.
				handle.beam = _renderer.get_beam_resource(handle.light)
			var result: int = _renderer.update_bound_intensity(handle.light, handle.beam, handle.params)
			if result == BeamRendererBase.INTENSITY_UNRESOLVED:
				_renderer.update_beam(handle.light, handle.params)
				handle.beam = _renderer.get_beam_resource(handle.light)
			if _trace:
				service._visual_apply_counters["beams_considered"] += 1
				service._visual_apply_counters["beam_shader_parameters_written"] += _renderer.get_last_parameter_write_count()
				service._visual_apply_counters["beam_dynamic_changed" if result == BeamRendererBase.INTENSITY_CHANGED else "beam_dynamic_unchanged"] += 1

# Cold bridge for gobo projector code; never used by the dense per-output loop.
func light_state(light: SpotLight3D) -> Dictionary:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	if handle == null:
		return {}
	handle.compatibility_state["energy"] = handle.energy
	handle.compatibility_state["angle"] = handle.half_angle
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
	var result: Dictionary = _totals.duplicate()
	if _native != null: result.merge(_native.get_sizes())
	return result

# Only the once-per-report trace sampler resets these bounded interval counters.
func consume_diagnostics() -> Dictionary:
	var result: Dictionary = diagnostics()
	for key in ["semantic_payload_conversion_us", "native_compose_us", "payload_conversion_us", "compatibility_adapter_us", "renderer_mutation_us", "native_dirty_outputs"]:
		_totals[key] = 0
	var service: RefCounted = _service.get_ref() if _service != null else null
	if service != null:
		var beams: int = 0
		var spots: int = 0
		for output in _outputs:
			for handle in output.lights:
				beams += 1 if is_instance_valid(handle.beam) and handle.beam.visible else 0
				spots += 1 if handle.realtime_visible else 0
		service._visual_apply_counters["beam_visible_count"] = beams
		service._visual_apply_counters["spotlight_visible_count"] = spots
	return result

# Setup/control-boundary refresh after a renderer, settings or gobo resource replacement.
func rebind_light(light: SpotLight3D) -> void:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	if handle != null:
		handle.realtime_visibility_known = false
		handle.params = light.get_meta("peraviz_beam_last_params", {})
		handle.beam = _loader._get_beam_resource_for_light(light)
		handle.debug_axis = light.get_meta("peraviz_beam_debug_axis") as MeshInstance3D if light.has_meta("peraviz_beam_debug_axis") else null
		handle.has_gobo = light.has_meta("peraviz_gobo_texture") and light.get_meta("peraviz_gobo_texture") != null

func refresh_renderer() -> void:
	if not is_installed(): return
	_renderer = _loader.get("_active_beam_renderer") as BeamRendererBase
	for output in _outputs:
		for handle in output.lights:
			if is_instance_valid(handle.light): rebind_light(handle.light)
	_native.invalidate_renderer()
	compose(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), _trace, _mode)
	apply()

# Cold renderer callbacks report RID visibility back to the pre-bound compatibility handle.
func synchronize_visibility(light: SpotLight3D, visible: bool) -> void:
	var handle: LightHandle = _lights_by_id.get(light.get_instance_id())
	if handle != null:
		handle.realtime_visible = visible
		handle.realtime_visibility_known = true
