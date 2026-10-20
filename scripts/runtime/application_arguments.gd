extends RefCounted

# Canonical application boundary: Godot options precede --; Peraviz options follow it.
const Policy = preload("res://scripts/runtime/render_diagnostic_policy.gd")
const TransformPolicy = preload("res://scripts/runtime/presentation_transform_controller.gd")
const PERF_TRACE: String = "--peraviz-perf-trace"

static func has_flag(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)

static func read_diagnostics() -> Dictionary:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = Policy.FULL
	var transform_mode: String = TransformPolicy.from_arguments(arguments)
	var requested: bool = arguments.has(PERF_TRACE)
	var mode_count: int = 0
	for argument in arguments:
		if argument.begins_with(TransformPolicy.ARGUMENT): requested = true
		if argument.begins_with(Policy.ARGUMENT_PREFIX):
			requested = true
			mode_count += 1
			mode = Policy.from_arguments(PackedStringArray([argument]))
			if argument.trim_prefix(Policy.ARGUMENT_PREFIX).to_lower() not in [Policy.FULL,Policy.NO_BEAMS,Policy.TRANSFORMS_ONLY]:
				push_warning("Unknown Peraviz render diagnostic mode; using full.")
	if mode_count > 1:
		push_warning("Multiple Peraviz diagnostic modes supplied; the last application argument wins.")
	# Deliberately reject the old placement rather than silently running a different mode.
	for argument in OS.get_cmdline_args():
		if argument == PERF_TRACE or argument.begins_with(Policy.ARGUMENT_PREFIX) or argument.begins_with(TransformPolicy.ARGUMENT):
			push_warning("Peraviz options before -- are ignored. Use: godot [engine options] -- [Peraviz options].")
			break
	return {"perf_trace": arguments.has(PERF_TRACE), "render_mode": mode, "requested": requested, "transform_mode": transform_mode}
