extends SceneTree

const BoundBeamStateScript = preload("res://scripts/beam_renderers/bound_beam_state.gd")

const Harness = preload("res://tests/gdscript/helpers/dense_mutation_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const WRITE_KEYS: PackedStringArray = ["spot_node_visibility_writes", "spot_rid_visibility_writes", "beam_visibility_writes", "debug_axis_visibility_writes", "beam_shader_parameter_writes", "material_parameter_writes"]
var test = TestCase.new()

class Bindings extends RefCounted:
	var loader: Node
	func get_dense_presentation_bindings() -> Dictionary:
		return loader.get_dense_presentation_bindings()

func _initialize() -> void:
	call_deferred("run")

func apply(service: RefCounted, frame: Dictionary) -> void:
	service.begin_visual_snapshot()
	test.check(service.compose_dense_snapshot(frame["descriptors"],frame["integers"],frame["floats"]) > 0, "Dense batch is accepted")
	service.end_visual_snapshot()

func check_zero(diagnostics: Dictionary, keys: PackedStringArray, message: String) -> void:
	for key in keys: test.check(int(diagnostics.get(key,-1)) == 0, message+": "+key)

func run() -> void:
	var loader := Harness.new()
	loader.output_count = 1095
	loader._visual_settings["enable_realtime_spotlights"] = false
	get_root().add_child(loader)
	await process_frame
	var service = Service.new()
	loader.dense_service = service
	service.set_performance_trace_enabled(true)
	var bindings := Bindings.new()
	bindings.loader = loader
	test.check(service.install_dense_presentation(loader,bindings), "Dense installation succeeds")
	test.check(service.is_dense_presentation_active(), "Dense installation is explicitly active")
	var adapter: RefCounted = service._dense_adapter
	var first: Dictionary = loader.frame(0.7,0.2)
	apply(service,first)
	adapter.consume_diagnostics()
	var before_notifications: int = loader.notification_count()
	var sizes: Dictionary = adapter.diagnostics()
	apply(service,first)
	var identical: Dictionary = adapter.consume_diagnostics()
	check_zero(identical,WRITE_KEYS,"Identical 1095-output replay has zero renderer writes")
	test.check(identical["renderer_outputs_changed"] == 0 and identical["renderer_outputs_processed"] == 0 and identical["native_dirty_outputs"] == 1095,"Physical no-ops emit no renderer rows while retaining exact native dirty accounting")
	test.check(loader.notification_count() == before_notifications,"Unchanged playback sends no Node visibility notification")
	for i in range(1095):
		test.check(adapter._outputs[i].canonical_id == 40000+i,"Every independent output identity survives")
		test.check(not adapter._outputs[i].lights[0].realtime_visible,"Disabled realtime RID stays disabled while beams are active")

	# One changed output must not dirty any other independent output.
	var single: Dictionary = {"descriptors": PackedInt32Array([3,1,0,0,0]),"integers": PackedInt32Array([1,20500,4]),"floats": PackedFloat32Array([0.9,0.8,0.7,1.0])}
	apply(service,single)
	var changed: Dictionary = adapter.consume_diagnostics()
	test.check(changed["renderer_outputs_changed"] == 1 and changed["last_dirty_outputs"] == 1,"One output changes independently")
	test.check(changed["material_parameter_writes"] == 1,"Color change writes only that material color")
	check_zero(changed,PackedStringArray(["spot_node_visibility_writes","spot_rid_visibility_writes","beam_visibility_writes"]),"Color changes do not change visibility")
	# Dark -> active must not let Node visibility reactivate a disabled SpotLight RID.
	apply(service,loader.frame(0.0,0.2))
	apply(service,first)
	test.check(loader.notification_count() == before_notifications,"DMX blackout/reactivation never toggles the structural light Node")
	for output in adapter._outputs: test.check(not output.lights[0].realtime_visible,"Light RID remains disabled after blackout/reactivation")

	# A gobo-required light is active in full and must still be disabled in no-beams.
	var texture := GradientTexture2D.new()
	loader.anchors[0].set_meta("peraviz_gobo_texture",texture)
	service.rebind_dense_light(loader.anchors[0])
	loader._refresh_native_gobo_presentation(loader.anchors[0])
	test.check(adapter._outputs[0].lights[0].realtime_visible,"Full mode enables a gobo-required light")
	adapter.consume_diagnostics()
	service.set_render_diagnostic_mode("no-beams")
	var entered: Dictionary = adapter.consume_diagnostics()
	test.check(entered["mode_transition_replays"] == 1,"Entering no-beams replays once without a new packet")
	test.check(entered["beam_shader_parameter_writes"] == 0 and entered["material_parameter_writes"] == 0,"Entering no-beams does not rewrite beam uniforms or unrelated materials")
	var projector_refreshes: int = loader.projector_refreshes
	for iteration in range(30): apply(service,loader.frame(float(iteration%7)/7.0,float(iteration%13)/13.0))
	var suppressed: Dictionary = adapter.consume_diagnostics()
	check_zero(suppressed,PackedStringArray(["spot_node_visibility_writes","spot_rid_visibility_writes","beam_visibility_writes","debug_axis_visibility_writes","beam_shader_parameter_writes","spot_property_writes","optics_apply_calls","beam_initializations"]),"Changing suppressed outputs never touch light/beam renderer objects")
	test.check(suppressed["material_parameter_writes"] > 0 and suppressed["native_dirty_outputs"] >= 1095*30,"Native held state and apertures remain active in no-beams")
	test.check(loader.projector_refreshes == projector_refreshes,"Suppressed color/dimmer changes do not refresh projector objects")
	for output in adapter._outputs:
		test.check(not output.lights[0].beam.visible and not output.lights[0].light.visible and not output.lights[0].realtime_visible,"Suppressed beam and realtime light stay hidden")

	# Return using only the mode setter. No fresh semantic snapshot is submitted.
	service.set_render_diagnostic_mode("full")
	var resumed: Dictionary = adapter.consume_diagnostics()
	test.check(resumed["mode_transition_replays"] == 1,"Returning full replays once without fresh DMX")
	var held: Dictionary = loader.anchors[10].get_meta("peraviz_beam_last_params")
	test.check(is_equal_approx(float(held["normalized_dimmer"]),float(29%7)/7.0) and is_equal_approx(float(held["beam_color"].r),float(29%13)/13.0),"Returning full restores the latest held values")
	test.check(adapter._outputs[0].lights[0].realtime_visible and loader.anchors[0].light_projector == texture,"Returning full restores gobo-required RID ownership")
	apply(service,loader.frame(float(29%7)/7.0,float(29%13)/13.0))
	check_zero(adapter.consume_diagnostics(),WRITE_KEYS,"Replay settles after the transition")
	var after: Dictionary = adapter.diagnostics()
	for key in ["state_capacity","dirty_capacity","native_buffer_bytes","packed_buffer_bytes"]:
		test.check(after[key] == sizes[key],"Native and bridge storage remains bounded: "+key)
	test.check(service._snapshot_output_commits.is_empty() and service._target_states.is_empty(),"No Dictionary state owner returns")

	service.set_render_diagnostic_mode("transforms-only")
	adapter.consume_diagnostics()
	for output in adapter._outputs:
		test.check(not output.lights[0].light.visible, "Transforms-only stops hidden light transform forwarding")
	apply(service, first)
	check_zero(adapter.consume_diagnostics(), WRITE_KEYS, "Transforms-only keeps renderer objects untouched")
	service.set_render_diagnostic_mode("full")
	adapter.consume_diagnostics()

	# An ancestor visibility notification must repair a cached-false RID, then settle.
	var light = loader.anchors[1]
	var notification_start: int = light.visibility_notifications
	light.visible = false
	light.visible = true
	var repair: Dictionary = adapter.consume_diagnostics()
	test.check(light.visibility_notifications == notification_start+2,"Godot propagates actual Node visibility transitions")
	test.check(repair["spot_rid_visibility_writes"] == 1 and not adapter._outputs[1].lights[0].realtime_visible,"A Godot visibility notification cannot overwrite cached disabled RID state")

	service.reset_scene_state()
	for anchor in loader.anchors: loader.renderer.cleanup_beam(anchor)
	loader.free()
	service = null
	await process_frame
	await check_initial_suppression("no-beams")
	await check_initial_suppression("transforms-only")
	await check_bound_renderer(false)
	await check_bound_renderer(true)
	var failed_service = Service.new()
	failed_service._dense_required = true # Model a required installation that failed.
	test.check(failed_service.compose_dense_snapshot(PackedInt32Array(),PackedInt32Array(),PackedFloat32Array()) < 0, "Required missing dense adapter cannot silently use legacy state")
	test.check(not failed_service.is_dense_presentation_active() and failed_service._target_states.is_empty(), "Failed dense installation remains inactive with no legacy state owner")
	test.finish(self)

func check_bound_renderer(vector: bool) -> void:
	var loader := Harness.new()
	loader.output_count = 1
	loader.vector_prism = vector
	get_root().add_child(loader)
	await process_frame
	var light: SpotLight3D = loader.anchors[0]
	var params: Dictionary = loader._build_cached_beam_params(light,25.0,Color(0.2,0.4,0.8),0.5,10.0,0.03,{})
	loader.renderer.update_beam(light,params)
	var beam: MeshInstance3D = loader.renderer.get_beam_resource(light)
	var bound: RefCounted = BoundBeamStateScript.resolve(beam)
	loader.renderer.update_bound_intensity(light,beam,params,bound)
	var writes: int = loader.renderer.renderer_shader_parameter_writes
	var visibility: int = loader.renderer.renderer_visibility_writes
	var result: int = loader.renderer.update_bound_intensity(light,beam,params,bound)
	test.check(result == BeamRendererBase.INTENSITY_UNCHANGED,"Identical bound prism state returns UNCHANGED, vector="+str(vector))
	test.check(writes == loader.renderer.renderer_shader_parameter_writes and visibility == loader.renderer.renderer_visibility_writes,"Identical bound state does not call renderer setters")
	test.check(loader.renderer.update_beam_intensity(light,params) == BeamRendererBase.INTENSITY_UNCHANGED, "Cold and bound entry points share applied state")
	params["scaled_intensity"] = 0.0
	loader.renderer.update_bound_intensity(light,beam,params,bound)
	params["beam_color"] = Color(0.9,0.1,0.5)
	writes = loader.renderer.renderer_shader_parameter_writes
	visibility = loader.renderer.renderer_visibility_writes
	result = loader.renderer.update_bound_intensity(light,beam,params,bound)
	test.check(result == BeamRendererBase.INTENSITY_UNCHANGED and writes == loader.renderer.renderer_shader_parameter_writes and visibility == loader.renderer.renderer_visibility_writes,"Hidden prism changes are held without rendering work")
	loader.renderer.cleanup_beam(light)
	loader.free()
	await process_frame

# Launch-time diagnostic policy must apply before the first semantic snapshot.
func check_initial_suppression(mode: String) -> void:
	var loader := Harness.new()
	loader.output_count = 1
	get_root().add_child(loader)
	await process_frame
	var service = Service.new()
	loader.dense_service = service
	service.set_render_diagnostic_mode(mode)
	var bindings := Bindings.new()
	bindings.loader = loader
	test.check(service.install_dense_presentation(loader,bindings), "Dense installation succeeds")
	test.check(not loader.anchors[0].visible, "Initial diagnostic mode hides structural light: "+mode)
	apply(service,loader.frame(0.5,0.2))
	test.check(not loader.anchors[0].visible and not service._dense_adapter._outputs[0].lights[0].realtime_visible, "Initial suppressed snapshot cannot enable a light")
	service.set_render_diagnostic_mode("full")
	test.check(loader.anchors[0].visible and loader.renderer.get_beam_resource(loader.anchors[0]).visible, "Initial diagnostic mode can resume held full state")
	service.reset_scene_state()
	loader.renderer.cleanup_beam(loader.anchors[0])
	loader.free()
	service = null
	await process_frame
