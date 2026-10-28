@tool
extends RefCounted

# Older archives used Spot intensity for the surface light. Explicit new values
# always win; keep spot_multiplier for experimental/native realtime lighting.
static func migrate(settings: Dictionary) -> Dictionary:
	var result := settings.duplicate(false)
	if not result.has("footprint_multiplier") and result.has("spot_multiplier"):
		result["footprint_multiplier"] = maxf(float(result.get("spot_multiplier", 1.0)), 0.0)
	return result

# Restoration fills only missing values. Explicit selections and zero remain exact;
# partial live updates never introduce defaults or change the backend.
static func migrate_saved(settings: Dictionary) -> Dictionary:
	var result := migrate(settings)
	if not result.has("footprint_multiplier"): result["footprint_multiplier"] = 0.6
	if not result.has("footprint_softness"): result["footprint_softness"] = 0.10
	if not result.has("footprint_backend"): result["footprint_backend"] = "custom"
	if not result.has("wash_intersection_width_m"): result["wash_intersection_width_m"] = 0.5
	if not result.has("lens_emission_multiplier"): result["lens_emission_multiplier"] = 1.0
	return result

static func surface_multiplier(settings: Dictionary) -> float:
	var footprint := maxf(float(settings.get("footprint_multiplier", settings.get("spot_multiplier", 1.0))), 0.0)
	return footprint if int(settings.get("beam_presentation", 1)) == 1 else maxf(float(settings.get("spot_multiplier", 1.0)), 0.0)
