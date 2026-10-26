@tool
extends RefCounted

# Older archives used Spot intensity for the surface light. Explicit new values
# always win; keep spot_multiplier for experimental/native realtime lighting.
static func migrate(settings: Dictionary) -> Dictionary:
	var result := settings.duplicate(false)
	if not result.has("footprint_multiplier") and result.has("spot_multiplier"):
		result["footprint_multiplier"] = maxf(float(result.get("spot_multiplier", 1.0)), 0.0)
	return result

# Only archive/project restoration applies legacy defaults. Partial live UI updates
# must never reinterpret a missing backend as a request to switch away from custom.
static func migrate_saved(settings: Dictionary) -> Dictionary:
	var result := migrate(settings)
	if not result.has("footprint_multiplier"): result["footprint_multiplier"] = 1.0
	if not result.has("footprint_softness"): result["footprint_softness"] = 0.04
	if not result.has("footprint_backend"): result["footprint_backend"] = "native"
	return result

static func surface_multiplier(settings: Dictionary) -> float:
	var footprint := maxf(float(settings.get("footprint_multiplier", settings.get("spot_multiplier", 1.0))), 0.0)
	return footprint if int(settings.get("beam_presentation", 1)) == 1 else maxf(float(settings.get("spot_multiplier", 1.0)), 0.0)
