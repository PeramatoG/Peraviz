extends RefCounted

# Renderer ownership is independent of the optical capability to describe a surface.
# This diagnostic is deliberately absent from saved settings and the normal UI.
const OPEN_ARGUMENT: String = "--peraviz-open-footprint-lights="
const OWNED: int = 1 << 0
const ACTIVE: int = 1 << 1
const OPEN: int = 1 << 2
const PROJECTOR: int = 1 << 3
const SHADOWED_PROJECTOR: int = 1 << 4
const PROJECTOR_TEXTURE: int = 1 << 5
const OPEN_SHADOWLESS: int = 1 << 6
const COUNTER_KEYS: PackedStringArray = [
	"owned_surface_lights", "active_surface_lights", "active_open_surface_lights",
	"active_projector_lights", "shadowed_projector_lights", "active_projector_textures",
	"active_open_shadowless_lights",
]

static func open_lights_from_arguments(arguments: PackedStringArray) -> bool:
	for argument in arguments:
		if argument.begins_with(OPEN_ARGUMENT):
			return argument.trim_prefix(OPEN_ARGUMENT) == "on"
	return false

static func owns_realtime_light(realtime: bool, presentation: int, projector: bool, diagnostic_open: bool, has_profile: bool) -> bool:
	return realtime or projector or presentation in [0, 2] or (diagnostic_open and presentation == 1 and has_profile)

# Existing handles retain a bitset; transitions update fixed-size gauges in O(1).
# Snapshots allocate only at startup / the trace-report boundary, never per frame.
class Counters:
	var projected_outputs: int = 0
	var surface_profiles: int = 0
	var _counts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var activations: int = 0
	var deactivations: int = 0

	func update(previous: int, current: int) -> void:
		var changed := previous ^ current
		if changed == 0: return
		for index in range(COUNTER_KEYS.size()):
			var bit := 1 << index
			if changed & bit: _counts[index] += 1 if current & bit else -1
		if changed & ACTIVE:
			if current & ACTIVE: activations += 1
			else: deactivations += 1

	func snapshot() -> Dictionary:
		var result := {"projected_outputs": projected_outputs, "surface_profiles": surface_profiles,
			"surface_light_activations": activations, "surface_light_deactivations": deactivations}
		for index in range(COUNTER_KEYS.size()): result[COUNTER_KEYS[index]] = _counts[index]
		return result

	func reset_interval() -> void:
		activations = 0
		deactivations = 0
