extends RefCounted
class_name RenderDiagnosticPolicy

const FULL: String = "full"
const TRANSFORMS_ONLY: String = "transforms-only"
const NO_BEAMS: String = "no-beams"
const ARGUMENT_PREFIX: String = "--peraviz-render-diagnostic="

static func from_arguments(arguments: PackedStringArray) -> String:
	for argument in arguments:
		var value: String = str(argument)
		if not value.begins_with(ARGUMENT_PREFIX):
			continue
		var requested: String = value.trim_prefix(ARGUMENT_PREFIX).to_lower()
		if requested in [FULL, TRANSFORMS_ONLY, NO_BEAMS]:
			return requested
	return FULL

static func applies_section(mode: String, section_type: int) -> bool:
	if mode == TRANSFORMS_ONLY:
		return section_type == 1
	if mode == NO_BEAMS:
		return section_type not in [4, 5, 6, 14, 15]
	return true

static func renders_beams(mode: String) -> bool:
	return mode == FULL
