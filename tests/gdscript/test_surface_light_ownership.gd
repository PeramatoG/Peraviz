extends SceneTree

const Harness = preload("res://tests/gdscript/helpers/dense_mutation_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Policy = preload("res://scripts/runtime/surface_light_policy.gd")
const State = preload("res://scripts/runtime/optical_projection_state.gd")
const Projector = preload("res://scripts/fixture_gobo_projector.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

class Bindings extends RefCounted:
	var loader: Node
	func get_dense_presentation_bindings() -> Dictionary:
		return loader.get_dense_presentation_bindings()

class TraceOwner extends Node:
	var _fixture_light_apply_service: RefCounted
	var _native_target_registry = preload("res://scripts/runtime/native_renderer_target_registry.gd").new()
	var _beam_renderers: Dictionary = {}

func _init() -> void: call_deferred("run")

func apply(service: RefCounted, frame: Dictionary) -> void:
	test.check(service.compose_dense_snapshot(frame["descriptors"], frame["integers"], frame["floats"]) > 0, "Dense snapshot accepted")
	service.end_visual_snapshot()

func run() -> void:
	for args in [PackedStringArray(), PackedStringArray(["--peraviz-open-footprint-lights=off"]), PackedStringArray(["--peraviz-open-footprint-lights=invalid"])]:
		test.check(not Policy.open_lights_from_arguments(args), "Open realtime diagnostic defaults safely off")
	test.check(Policy.open_lights_from_arguments(PackedStringArray(["--peraviz-open-footprint-lights=on"])), "Only explicit on enables the A/B diagnostic")
	var loader := Harness.new()
	loader.output_count = 1000
	loader.vector_prism = true
	loader._visual_settings = {"enable_realtime_spotlights": false, "beam_presentation": 1, "footprint_multiplier": 1.0}
	root.add_child(loader)
	await process_frame
	var camera := Camera3D.new()
	loader.add_child(camera)
	loader.renderer.configure(camera, loader._visual_settings)
	var projector := Projector.new()
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for y in range(5, 11):
		for x in range(5, 11): image.set_pixel(x, y, Color.BLACK)
	var texture := ImageTexture.create_from_image(image)
	for index in range(1000):
		loader.outputs[index]["beam_optical_profile"]["beam_type"] = "Spot" if index % 2 else "Wash"
		if index < 7:
			loader.anchors[index].set_meta("peraviz_gobo_texture", texture)
			projector._set_light_projector_texture(loader.anchors[index], texture)
	var service = Service.new()
	loader.dense_service = service
	service.set_performance_trace_enabled(true)
	var bindings := Bindings.new()
	bindings.loader = loader
	test.check(service.install_dense_presentation(loader, bindings), "1000-output Vector Prism installs with existing anchors")
	var adapter = service._dense_adapter
	apply(service, loader.frame(0.7, 0.2))
	var counts: Dictionary = adapter.consume_diagnostics()["surface_lights"]
	print("[surface-policy-regression] production ", JSON.stringify(counts))
	test.check(counts.projected_outputs == 1000 and counts.surface_profiles == 1000, "All physical outputs retain resolved surface profiles")
	test.check(counts.active_surface_lights == 7 and counts.owned_surface_lights == 7 and counts.active_open_surface_lights == 0, "Only seven genuine projectors own active realtime lights")
	test.check(counts.active_projector_lights == 7 and counts.shadowed_projector_lights == 7 and counts.active_projector_textures == 7, "Projector/shadow/texture gauges agree")
	for index in range(7, 1000):
		var handle = adapter._outputs[index].lights[0]
		test.check(handle.has_projected_surface_profile and not handle.owns_realtime_surface_light and not handle.realtime_visible, "Optical capability does not grant renderer ownership")
		test.check(handle.light.light_projector == null and not handle.light.shadow_enabled, "Open profiles never acquire projector textures or shadows")
	var provider = loader.renderer._active_shape_provider
	var builds: int = provider._mesh_builder.get_counters().gobo_energy_builds
	var footprints: int = loader.renderer._footprint_cache.creations
	var nodes: int = loader.get_child_count()
	for iteration in range(20):
		camera.position.x = float(iteration)
		apply(service, loader.frame(0.4 + iteration * 0.01, iteration * 0.02))
	var stable: Dictionary = adapter.consume_diagnostics()["surface_lights"]
	test.check(stable.active_surface_lights == 7 and stable.surface_light_activations == 0 and stable.surface_light_deactivations == 0, "Dimmer/color/camera changes retain current counts without new ownership transitions")
	test.check(builds > 0 and builds == provider._mesh_builder.get_counters().gobo_energy_builds and footprints == loader.renderer._footprint_cache.creations, "Playback does not regenerate transmission, coverage or softness textures")
	test.check(loader.get_child_count() == nodes, "Playback creates no new light or beam Nodes")
	var trace_owner := TraceOwner.new()
	trace_owner._fixture_light_apply_service = service
	trace_owner._beam_renderers[1] = loader.renderer
	var report: Dictionary = preload("res://scripts/runtime/performance_trace_snapshot.gd").new().collect(trace_owner, null)
	test.check(report.dense_presentation.surface_lights.active_surface_lights == 7 and report.presentation_cache_builds.renderer_1_footprint_textures == footprints and report.presentation_cache_builds.renderer_1_gobo_energy_builds == builds, "Real trace collector exposes surface inventory and static build gauges")
	trace_owner.free()
	loader._visual_settings.footprint_multiplier = 0.0
	service.refresh_dense_renderer()
	counts = adapter.diagnostics().surface_lights
	test.check(counts.active_surface_lights == 0 and counts.owned_surface_lights == 0 and loader.renderer.get_beam_resource(loader.anchors[0]).visible, "Surface gain zero removes ownership/effect independently of shaft")
	loader._visual_settings.footprint_multiplier = 1.0
	service.refresh_dense_renderer()
	adapter._diagnostic_open_surface_lights = true # Same internal value as the parsed startup argument.
	service.refresh_dense_renderer()
	counts = adapter.diagnostics().surface_lights
	test.check(counts.active_surface_lights == 1000 and counts.active_open_shadowless_lights == 993 and counts.active_projector_lights == 7, "Opt-in diagnostic explicitly reproduces the costly all-open policy")
	print("[surface-policy-regression] diagnostic ", JSON.stringify(counts))
	adapter._diagnostic_open_surface_lights = false
	service.refresh_dense_renderer()
	test.check(adapter.diagnostics().surface_lights.active_surface_lights == 7, "Leaving the diagnostic restores bounded production ownership")
	for mode in ["no-beams", "transforms-only"]:
		service.set_render_diagnostic_mode(mode)
		counts = adapter.diagnostics().surface_lights
		test.check(counts.active_surface_lights == 0 and counts.surface_profiles == 1000, "Suppressed modes retain profile data without realtime surface work: " + mode)
		for anchor in loader.anchors: test.check(not loader.renderer.get_beam_resource(anchor).visible, "Suppressed mode hides shafts")
	service.set_render_diagnostic_mode("full")
	test.check(adapter.diagnostics().surface_lights.active_surface_lights == 7 and loader.renderer.get_beam_resource(loader.anchors[10]).visible, "Full resumes held gobo lights and shafts without fresh DMX")
	loader._visual_settings.enable_realtime_spotlights = true
	service.refresh_dense_renderer()
	test.check(adapter.diagnostics().surface_lights.active_surface_lights == 1000, "Explicit realtime mode still owns its requested renderer cost")
	loader._visual_settings.enable_realtime_spotlights = false
	service.refresh_dense_renderer()
	service.reset_scene_state()
	for anchor in loader.anchors: loader.renderer.cleanup_beam(anchor)
	loader.free()
	await process_frame
	await check_compatibility()
	check_rectangle_ownership()
	check_reported_photometry()
	test.finish(self)

func check_compatibility() -> void:
	var loader := Harness.new()
	loader.output_count = 1
	loader.vector_prism = true
	loader._visual_settings = {"enable_realtime_spotlights": false, "footprint_multiplier": 1.0}
	root.add_child(loader)
	await process_frame
	var light = loader.anchors[0]
	loader.renderer.update_beam(light, loader._build_cached_beam_params(light, 25.0, Color.WHITE, 1.0, 20.0, 0.03, {}))
	var service = Service.new()
	service._update_desired_light_state(light, 2.0, 12.5, Color.WHITE, true)
	service._apply_desired_light_state(loader, light)
	test.check(not service._light_desired_for(light).owns_realtime_surface_light, "Compatibility path also keeps open profile data separate from ownership")
	service._diagnostic_open_surface_lights = true
	service._apply_desired_light_state(loader, light)
	test.check(service._light_desired_for(light).owns_realtime_surface_light, "Compatibility A/B is explicit")
	loader._visual_settings.footprint_multiplier = 0.0
	service._apply_desired_light_state(loader, light)
	test.check(not service._light_desired_for(light).owns_realtime_surface_light and light.light_energy == 0.0, "Compatibility surface blackout cannot be undone by the profile capability")
	loader.renderer.cleanup_beam(light)
	loader.free()
	await process_frame

func check_reported_photometry() -> void:
	# User-reported MAC Axiom values; no fixture-name branch or source rewriting.
	var params := {"beam_type": "Spot", "beam_type_explicit": true, "profile_beam_angle": 14.5, "beam_angle_explicit": true, "field_angle": 51.7857, "field_angle_explicit": true, "beam_angle": 2.0, "smooth_light_profile": true, "luminous_flux": 16000.0}
	var state = State.new()
	state.configure(params, null)
	print("[photometry-review] ", state.diagnostic(params))
	test.check(state.radial_profile.anchored and state.radial_profile.field_ratio > 3.0 and state.radial_profile.exponent < 1.0, "Reported explicit pair explains an unusually soft Spot shoulder")
	test.check(state.diagnostic(params).contains("photometry_review=suspicious-spot-shoulder") and state.diagnostic(params).contains("BeamType=Spot source=explicit"), "Generic opt-in diagnostic identifies suspicious Spot data for review")
	test.check(params.field_angle == 51.7857 and params.profile_beam_angle == 14.5 and params.luminous_flux == 16000.0, "Suspicious photometry never overrides canonical source values")

func check_rectangle_ownership() -> void:
	var renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd").new()
	var light := SpotLight3D.new()
	root.add_child(light)
	var params := {"beam_type": "Rectangle", "scaled_intensity": 0.0}
	renderer.update_beam(light, params)
	var state: RefCounted = light.get_meta(State.META)
	test.check(state.has_projected_surface_profile and light.light_projector == null and not light.shadow_enabled, "Open Rectangle capability does not manufacture projector ownership")
	renderer._diagnostic_open_surface_lights = true
	renderer.update_beam(light, params)
	var mask: Texture2D = light.light_projector
	test.check(mask != null and light.shadow_enabled, "Explicit Rectangle diagnostic uses its necessary mask and shadow path")
	renderer._diagnostic_open_surface_lights = false
	renderer.update_beam(light, params)
	test.check(light.light_projector == null and not light.shadow_enabled, "Leaving Rectangle diagnostic releases its projector and restores shadows")
	renderer._diagnostic_open_surface_lights = true
	renderer.update_beam(light, params)
	test.check(light.light_projector == mask and renderer._footprint_cache.creations == 1, "Rectangle ownership toggles reuse a single cached presentation mask")
	renderer.cleanup_beam(light)
	light.free()
