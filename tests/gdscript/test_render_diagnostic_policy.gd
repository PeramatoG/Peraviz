extends SceneTree

const RenderDiagnosticPolicyScript = preload("res://scripts/runtime/render_diagnostic_policy.gd")
const DmxControllerScript = preload("res://scripts/controllers/dmx_controller.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class FakeReceiver:
	extends RefCounted
	func get_stats() -> Dictionary:
		return {}

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
	controller._perf_trace_enabled = true
	controller._perf_trace_last_msec = -1000
	controller._report_performance_trace_if_needed()
	test.check(controller._perf_trace_last_msec >= 0, "Performance trace schema must format without runtime errors")
	test.finish(self)
