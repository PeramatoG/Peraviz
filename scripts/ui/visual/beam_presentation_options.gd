extends RefCounted
class_name BeamPresentationOptions

const LABELS: Array[String] = [
	"Shared Haze (Experimental)",
	"Vector Gobo Prism (Production)",
	"Shared Haze + Gobo Shadow (Experimental)",
	"Shader Beam Proxy (Experimental)",
]

const PRESET_NAMES: Array[String] = [
	"Vector Prism + Custom Footprints",
]

# Serialized IDs remain stable. Restored legacy selections are visible but cannot
# be selected anew outside the explicit internal diagnostic session.
static func visible_ids(active: int) -> Array[int]:
	if OS.get_environment("PERAVIZ_DIAGNOSTIC_RENDERERS") == "1": return [1, 0, 2, 3]
	if active != 1: return [1, active]
	return [1]
