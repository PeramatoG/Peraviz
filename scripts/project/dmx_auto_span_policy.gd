extends RefCounted

const DEFAULT := "auto_safe"
const IDS := ["off", "auto_safe", "auto_overlap"]

static func normalize(value: Variant) -> String:
	if value is String and IDS.has(value): return value
	push_warning("Invalid DMX Auto Span policy '%s'; using Automatic — only if free." % str(value))
	return DEFAULT
