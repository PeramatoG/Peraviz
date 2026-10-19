extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

const CoalescingLoader = preload("res://tests/gdscript/helpers/coalescing_loader.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var loader := CoalescingLoader.new()
	get_root().add_child(loader)
	await process_frame
	var service = FixtureLightApplyServiceScript.new()
	service.set_performance_trace_enabled(true)
	var before: Dictionary = service.get_visual_apply_counters()
	service.begin_visual_snapshot()
	var deferred_intensity: Dictionary = service.apply_emitter_intensity(loader, "fixture", 201, 1 << 1, 0.5, 10.0, 8.0, 10.0, 2.0)
	service.apply_emitter_color(loader, "fixture", 301, 1 << 2, Color(0.2, 0.4, 0.8), 1.0)
	var deferred_counters: Dictionary = service.get_visual_apply_counters()
	service.end_visual_snapshot()
	var after: Dictionary = service.get_visual_apply_counters()
	test.check(int(after.get("emitter_output_commit_candidates", 0)) - int(before.get("emitter_output_commit_candidates", 0)) == 6, "Intensity and color should nominate every shared physical output")
	test.check(int(after.get("emitter_output_commits", 0)) - int(before.get("emitter_output_commits", 0)) == 3, "Each shared physical output should commit once")
	test.check(int(after.get("emitter_output_commits_coalesced", 0)) - int(before.get("emitter_output_commits_coalesced", 0)) == 3, "The duplicate intensity/color commits should be coalesced")
	test.check(bool(deferred_intensity.get("commit_deferred", false)) and not bool(deferred_intensity.get("unchanged", true)), "Deferred semantic rows must not be classified as renderer no-ops")
	test.check(int(deferred_counters.get("emitter_output_commits", 0)) == int(before.get("emitter_output_commits", 0)), "Semantic rows should remain distinguishable from deferred renderer commits")
	test.check(int(after.get("emitter_output_commit_usec", 0)) >= int(before.get("emitter_output_commit_usec", 0)), "Deferred emitter commit time should be accumulated")
	for index in range(2):
		var params: Dictionary = loader.anchors[index].get_meta("peraviz_beam_last_params", {})
		test.check(params.get("beam_color", Color.BLACK) == Color(0.2, 0.4, 0.8) and is_equal_approx(float(params.get("beam_intensity", 0.0)), 10.0), "Coalesced output should receive final color and intensity")
	test.check(not loader.renderer.get_beam_resource(loader.anchors[2]).visible, "BeamType Glow should remain emission-only after a coalesced commit")

	service.begin_visual_snapshot()
	service.apply_emitter_intensity(loader, "fixture", 201, 1 << 1, 0.75, 15.0, 12.0, 15.0, 3.0)
	service.end_visual_snapshot()
	test.check(loader.anchors[0].get_meta("peraviz_beam_last_params", {}).get("beam_color", Color.BLACK) == Color(0.2, 0.4, 0.8), "Intensity-only snapshots should retain held color")
	service.begin_visual_snapshot()
	service.apply_emitter_color(loader, "fixture", 302, 1 << 2, Color(1.0, 0.1, 0.2), 1.0)
	service.end_visual_snapshot()
	test.check(is_equal_approx(float(loader.anchors[1].get_meta("peraviz_beam_last_params", {}).get("beam_intensity", 0.0)), 15.0), "Color-only snapshots should retain held intensity")
	test.check(loader.anchors[0].get_meta("peraviz_beam_last_params", {}).get("beam_color", Color.BLACK) == Color(0.2, 0.4, 0.8), "Independent output color should remain unchanged")
	test.check(loader.anchors[1].get_meta("peraviz_beam_last_params", {}).get("beam_color", Color.BLACK) == Color(1.0, 0.1, 0.2), "Independent output should remain addressable")

	for level in [0.0, 0.5, 0.0, 0.8]:
		service.begin_visual_snapshot()
		service.apply_emitter_intensity(loader, "fixture", 201, 1 << 1, level, level * 20.0, level * 16.0, level * 20.0, level * 4.0)
		service.end_visual_snapshot()
	test.check(loader.renderer.is_beam_dynamic_ready(loader.anchors[0]) and loader.renderer.get_beam_resource(loader.anchors[0]).visible, "Projected output should survive dark start and reactivate")
	test.check(loader.renderer.get_beam_resource(loader.anchors[1]).visible, "Master intensity should update every physical projected output")
	for anchor in loader.anchors:
		loader.renderer.cleanup_beam(anchor)
	loader.free()
	service = null
	await process_frame
	test.finish(self)
