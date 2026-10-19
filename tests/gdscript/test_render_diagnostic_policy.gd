extends SceneTree

const RenderDiagnosticPolicyScript = preload("res://scripts/runtime/render_diagnostic_policy.gd")
const DmxFixtureRuntimeScript = preload("res://scripts/dmx_fixture_runtime.gd")
const DmxControllerScript = preload("res://scripts/controllers/dmx_controller.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class FakeReceiver:
	extends RefCounted
	var apply_completions: int = 0
	var stats_reads: int = 0
	func is_running() -> bool:
		return true
	func pump_visual_runtime(_runtime: Object) -> int:
		return 1
	func record_godot_apply_completion() -> void:
		apply_completions += 1
	func get_stats() -> Dictionary:
		stats_reads += 1
		return {}
	func consume_interval_latency() -> Dictionary:
		return {}

class NoOpVisualRuntime:
	extends RefCounted
	func consume_latest_visual_frame() -> Dictionary:
		return {"descriptors": PackedInt32Array(), "integers": PackedInt32Array(), "floats": PackedFloat32Array()}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	test.check(RenderDiagnosticPolicyScript.from_arguments(PackedStringArray()) == "full", "Default render diagnostic mode must be full")
	test.check(RenderDiagnosticPolicyScript.from_arguments(PackedStringArray(["--peraviz-render-diagnostic=transforms-only"])) == "transforms-only", "Transforms-only argument must parse")
	test.check(RenderDiagnosticPolicyScript.from_arguments(PackedStringArray(["--peraviz-render-diagnostic=no-beams"])) == "no-beams", "No-beams argument must parse")
	test.check(RenderDiagnosticPolicyScript.from_arguments(PackedStringArray(["--peraviz-render-diagnostic=invalid"])) == "full", "Invalid diagnostic mode must safely use full")
	test.check(RenderDiagnosticPolicyScript.applies_section("transforms-only", 1), "Transforms-only must apply transform rows")
	test.check(not RenderDiagnosticPolicyScript.applies_section("transforms-only", 2), "Transforms-only must suppress intensity rows")
	test.check(not RenderDiagnosticPolicyScript.renders_beams("no-beams"), "No-beams mode must suppress beam rendering")
	test.check(not RenderDiagnosticPolicyScript.applies_section("no-beams", 15), "No-beams mode must suppress gobo beam parameter work")
	test.check(RenderDiagnosticPolicyScript.applies_section("no-beams", 2), "No-beams mode must retain Dimmer held state and emissive output")
	var controller = DmxControllerScript.new()
	controller._dmx_receiver = FakeReceiver.new()
	controller._perf_snapshot = preload("res://scripts/runtime/performance_trace_snapshot.gd").new()
	controller._perf_trace_enabled = true
	controller._perf_trace_last_msec = -1000
	controller._report_performance_trace_if_needed()
	test.check(controller._perf_trace_last_msec >= 0, "Performance trace schema must format without runtime errors")
	controller._perf_trace_enabled = false
	var reads_before: int = controller._dmx_receiver.stats_reads
	controller._report_performance_trace_if_needed()
	test.check(controller._dmx_receiver.stats_reads == reads_before, "Trace OFF must not sample diagnostics")
	var fixture_runtime = DmxFixtureRuntimeScript.new()
	fixture_runtime._native_visual_runtime_available = true
	fixture_runtime._native_visual_runtime = NoOpVisualRuntime.new()
	var receiver := FakeReceiver.new()
	fixture_runtime._collect_dmx(receiver, Callable())
	test.check(receiver.apply_completions == 1, "A consumed state with no visual rows must complete its latency sample")
	test.finish(self)
