extends SceneTree

const Harness = preload("res://tests/gdscript/helpers/footprint_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Policy = preload("res://scripts/runtime/surface_light_policy.gd")
const Optical = preload("res://scripts/runtime/optical_projection_state.gd")
const Volume = preload("res://scripts/beam_renderers/custom_footprint_volume.gd")
const Migration = preload("res://scripts/visual_settings_migration.gd")
const WindowSettings = preload("res://scripts/visual_settings_window.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

class Bindings extends RefCounted:
	var loader: Node
	func get_dense_presentation_bindings() -> Dictionary: return loader.get_dense_presentation_bindings()

func _init() -> void: call_deferred("run")

func apply(service: RefCounted, frame: Dictionary) -> void:
	test.check(service.compose_dense_snapshot(frame.descriptors, frame.integers, frame.floats) > 0, "Native physical snapshot accepted")
	service.end_visual_snapshot()

func run() -> void:
	if "--render-footprint-probe" in OS.get_cmdline_user_args(): root.disable_3d = true
	test.check(WindowSettings.DEFAULT_SETTINGS.footprint_backend == "custom" and not WindowSettings.DEFAULT_SETTINGS.enable_realtime_spotlights, "New-session defaults select custom without realtime lights")
	for mode in [0, 1, 2, 3]:
		var migrated: Dictionary = Migration.migrate_saved({"beam_presentation": mode})
		test.check(migrated.beam_presentation == mode and migrated.footprint_backend == "native", "Legacy numeric mode retains native meaning")
	test.check(Migration.migrate_saved({"footprint_backend": "custom"}).footprint_backend == "custom", "Explicit saved backend survives migration")
	test.check(not Migration.migrate({"beam_multiplier": 0.0}).has("footprint_backend"), "Partial live updates do not switch backend")
	for preset in ["Vector Prism + Custom Footprints", "Vector Prism + Native Footprints"]:
		test.check(WindowSettings.QUICK_PRESETS[preset].beam_presentation == 1, "Both presets retain Vector Prism shafts")
	for key in WindowSettings.QUICK_PRESETS["Vector Prism + Custom Footprints"]:
		test.check(WindowSettings.DEFAULT_SETTINGS[key] == WindowSettings.QUICK_PRESETS["Vector Prism + Custom Footprints"][key], "Default settings identify the preferred quick preset: " + key)
	var loader := Harness.new()
	loader.output_count = 128
	loader.vector_prism = true
	loader._visual_settings = {"beam_presentation": 1, "footprint_backend": "custom", "footprint_max_range": 20.0, "enable_realtime_spotlights": false, "footprint_multiplier": 1.0, "beam_multiplier": 0.0}
	root.add_child(loader)
	await process_frame
	var camera := Camera3D.new()
	loader.add_child(camera)
	loader.renderer.configure(camera, loader._visual_settings)
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.7, 0.4, 0.5))
	image.set_pixel(4, 3, Color.BLACK)
	var texture := ImageTexture.create_from_image(image)
	loader.anchors[0].set_meta("peraviz_gobo_texture", texture)
	loader.anchors[0].set_meta(Policy.BACKEND_META, "custom")
	loader._fixture_gobo_projector._set_light_projector_texture(loader.anchors[0], texture)
	test.check(loader.anchors[0].light_projector == null and not loader.anchors[0].shadow_enabled, "Cold custom gobo cannot bind a native projector")
	loader.proxies_root = Node3D.new()
	loader.add_child(loader.proxies_root)
	var scenic := MeshInstance3D.new()
	scenic.mesh = BoxMesh.new()
	scenic.position = Vector3(1000,0,0)
	loader.proxies_root.add_child(scenic)
	loader._loaded_bounds = scenic.global_transform * scenic.get_aabb()
	# Enable bounds only for the dedicated motion test below.
	var service = Service.new()
	loader.dense_service = service
	loader._fixture_light_apply_service = service
	var bindings := Bindings.new()
	bindings.loader = loader
	test.check(await service.install_dense_presentation(loader, bindings), "Custom integrates with normal dense physical presentation")
	var adapter = service._dense_adapter
	apply(service, loader.frame(0.7, 0.2))
	var counts: Dictionary = adapter.diagnostics()
	test.check(counts.custom_projector_resources == 128 and counts.active_custom_footprints == 128, "Independent footprints survive native shaft application")
	test.check(counts.surface_lights.active_projector_lights == 0 and counts.surface_lights.active_surface_lights == 0, "Custom footprints are never counted as native lights")
	var volume = adapter._footprints.volumes[0]
	test.check(volume.projection.pattern_texture == texture and volume.material_override.get_shader_parameter("pattern_texture") == texture, "Original image resource is bound directly, without vectorization or composition")
	test.check(volume.material_override.get_shader_parameter("artwork_aspect") == Vector2(1, 0.5), "Original artwork aspect is preserved")
	var dynamic: PackedFloat32Array = adapter._native.footprint_values(volume.material_override.get_rid())
	test.check(is_equal_approx(dynamic[3], 11.2) and is_equal_approx(dynamic[0], 0.2), "Physical surface intensity/color remain independent of zero shaft gain")
	service.refresh_dense_renderer()
	test.check(adapter._footprints.volumes[0] == volume, "Unrelated presentation rebinding reuses custom mesh/material resources")
	var updates: int = volume.parameter_updates
	var texture_builds: int = loader.renderer._footprint_cache.creations
	for iteration in range(8): apply(service, loader.frame(0.6, iteration * 0.1))
	test.check(volume.parameter_updates == updates and loader.renderer._footprint_cache.creations == texture_builds, "Color/Dimmer playback does not update projection geometry or build artwork")
	check_optics(loader.anchors[0], volume)
	apply(service, loader.frame(0.0, 0.3))
	test.check(adapter.diagnostics().active_custom_footprints == 0, "Blackout removes all custom contributions")
	apply(service, loader.frame(0.8, 0.4))
	for iteration in range(3):
		for backend in ["native", "custom"]:
			loader._visual_settings.footprint_backend = backend
			loader.renderer.configure(camera, loader._visual_settings)
			service.refresh_dense_renderer()
			counts = adapter.diagnostics()
			test.check(counts.custom_projector_resources == (128 if backend == "custom" else 0), "Switching owns exactly one set of footprint resources")
			test.check((loader.anchors[0].light_projector == null) == (backend == "custom"), "Backend switch restores or releases original native projector")
			test.check(loader.anchors[0].shadow_enabled == (backend == "native"), "Custom switch releases gobo-required shadows")
			test.check(counts.surface_lights.active_projector_lights == (0 if backend == "custom" else 1), "Held state replays without fresh DMX or duplicate footprint emission")
			test.check(counts.active_custom_footprints == (128 if backend == "custom" else 0), "Native physical state rehydrates new resources")
	for mode in ["no-beams", "transforms-only", "full"]:
		service.set_render_diagnostic_mode(mode)
		test.check(adapter.diagnostics().active_custom_footprints == (128 if mode == "full" else 0), "Diagnostics suspend/resume held footprints")
	loader._visual_settings.enable_realtime_spotlights = true
	service.refresh_dense_renderer()
	counts = adapter.diagnostics()
	test.check(counts.surface_lights.active_surface_lights == 128 and counts.surface_lights.active_projector_lights == 0, "Explicit independent realtime lighting survives custom selection without miscounting custom gobos as native projectors")
	loader._visual_settings.enable_realtime_spotlights = false
	service.refresh_dense_renderer()
	var kept_volume: MeshInstance3D = adapter._footprints.volumes[0]
	var old_renderer: BeamRendererBase = loader.renderer
	var replacement := preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd").new()
	replacement.configure(camera, loader._visual_settings)
	for anchor in loader.anchors:
		old_renderer.cleanup_beam(anchor)
		replacement.ensure_beam(anchor)
	loader.renderer = replacement
	loader._active_beam_renderer = replacement
	service.refresh_dense_renderer()
	test.check(adapter._footprints.volumes[0] == kept_volume and adapter.diagnostics().active_custom_footprints == 128, "Renderer replacement preserves independent surface resources and held native state")
	var custom_owner: RefCounted = adapter._footprints
	custom_owner._receiver_bounds = AABB(Vector3(999,-1,-1), Vector3.ONE * 2)
	custom_owner._bounds_known = true
	for projector in custom_owner.volumes: projector.set_receiver_bounds(custom_owner._receiver_bounds, true)
	test.check(custom_owner.volumes[1].culled, "Distant scenery culls a projector before movement")
	scenic.position = Vector3(0,0,-2)
	scenic.force_update_transform()
	await process_frame
	await process_frame
	test.check(not custom_owner.volumes[1].culled, "Scenery motion refreshes conservative bounds through a coalesced subscription")
	service.reset_scene_state()
	for anchor in loader.anchors:
		test.check(not anchor.has_meta(Volume.META), "Scene teardown releases owned volume metadata")
		loader.renderer.cleanup_beam(anchor)
	loader.free()
	await process_frame
	if "--render-footprint-probe" in OS.get_cmdline_user_args():
		await preload("res://tests/gdscript/helpers/footprint_graphical_probe.gd").new().run(self, test)
	test.finish(self)

func check_optics(light: SpotLight3D, volume: MeshInstance3D) -> void:
	var state: RefCounted = volume.projection
	var origin: Vector3 = light.position
	var params: Dictionary = light.get_meta("peraviz_beam_last_params")
	for mx in [true, false]:
		for mz in [false, true]:
			params.beam_gobo_mirror_x = mx
			params.beam_gobo_mirror_z = mz
			state.configure(params, state.pattern_texture)
			for roll in [0.0, 53.0, 237.0]:
				state.set_roll(roll)
				state.apply_footprint(light)
				var inv: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
				for depth in [3.0, 9.0]:
					var local := Vector3(0.3 * depth * tan(deg_to_rad(state.half_angle_deg)), 0.0, -depth)
					var world := light.global_transform * local
					var mapped := inv * world
					test.check(mapped.is_equal_approx(local), "Perspective coordinates retain the shared absolute rotation/parity")
	test.check(light.position.is_equal_approx(origin), "Roll and parity never accumulate lens offsets")
	var old_radius: float = volume.scale.x
	params.beam_angle = 12.0
	state.configure(params, state.pattern_texture)
	state.apply_footprint(light)
	test.check(volume.scale.x < old_radius and light.position.is_equal_approx(origin), "Zoom changes coverage without optical-origin drift")
	light.position += Vector3(2, 1, -1)
	light.rotation_degrees.y = 34.0
	light.force_update_transform()
	volume.force_update_transform()
	var inverse: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
	test.check((inverse * light.global_transform).is_equal_approx(Transform3D.IDENTITY), "Mechanical transform updates cached projector inverse")
	volume.set_receiver_bounds(AABB(Vector3(1000,1000,1000), Vector3.ONE), true)
	test.check(volume.culled and not volume.visible, "Conservative bounds reject empty projection volumes")
	volume.set_receiver_bounds(AABB(Vector3(-100,-100,-100), Vector3.ONE * 200), true)
	test.check(not volume.culled and volume.visible, "Partial intersections are retained without center-ray assumptions")
