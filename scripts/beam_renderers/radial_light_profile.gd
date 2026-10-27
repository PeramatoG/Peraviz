extends RefCounted

# Peraviz presentation approximation, not measured GDTF photometry. Tangent-space
# coordinates avoid atan per fragment while retaining both angular anchors exactly.
const LN2: float = 0.69314718056
const LN10: float = 2.30258509299
const FIELD_FEATHER: float = 1.06
const TAIL_START: float = 0.72
const TAIL_END: float = 0.98
const TERMINAL_EPSILON: float = 0.000001

var exponent: float = 8.0
var coefficient: float = LN2
var support_scale: float = 1.0
var rectangular: bool = false
var diffuse: bool = false
var aspect: Vector2 = Vector2.ONE
var projected: bool = true
var anchored: bool = false
var field_ratio: float = 1.0
var fallback_reason: String = "missing_authored_angles"
var feather_start: float = 0.86
var signature: Vector4 = Vector4.ZERO
var _configured: bool = false
var _kind: String
var _angles: Vector2
var _ratio: float
var _softness: float
var _bias: float
var _explicit_pair: bool = false

func configure(beam_type: String, beam_angle: float, field_angle: float, rectangle_ratio: float = 1.0, softness: float = 0.32, radial_bias: float = 1.0, beam_explicit: bool = true, field_explicit: bool = true) -> bool:
	# Normalize invalid metadata before the cache comparison: NaN is unequal to
	# itself and must not trigger curve generation on every optical update.
	beam_angle = beam_angle if is_finite(beam_angle) else 0.0
	field_angle = field_angle if is_finite(field_angle) else 0.0
	rectangle_ratio = rectangle_ratio if is_finite(rectangle_ratio) else 1.0
	softness = softness if is_finite(softness) else 0.32
	radial_bias = radial_bias if is_finite(radial_bias) else 1.0
	if _configured and _kind == beam_type and _angles == Vector2(beam_angle, field_angle) and _ratio == rectangle_ratio and _softness == softness and _bias == radial_bias and _explicit_pair == (beam_explicit and field_explicit):
		return false
	_configured = true
	_kind = beam_type
	_angles = Vector2(beam_angle, field_angle)
	_ratio = rectangle_ratio
	_softness = softness
	_bias = radial_bias
	_explicit_pair = beam_explicit and field_explicit
	var kind := beam_type.to_lower()
	projected = kind in ["wash", "spot", "rectangle", "pc", "fresnel"]
	rectangular = kind == "rectangle"
	diffuse = kind in ["wash", "fresnel", "pc"]
	var soft: bool = diffuse
	exponent = 2.0 if soft else 8.0
	anchored = false
	field_ratio = 1.0
	fallback_reason = "missing_authored_angles" if not _explicit_pair else "invalid_or_equal_angles"
	if _explicit_pair and is_finite(beam_angle) and is_finite(field_angle) and beam_angle > 0.0 and field_angle > beam_angle and field_angle < 178.0:
		var ratio := tan(deg_to_rad(field_angle * 0.5)) / tan(deg_to_rad(beam_angle * 0.5))
		fallback_reason = "unstable_angular_ratio"
		var candidate := log(LN10 / LN2) / log(ratio)
		if is_finite(candidate) and candidate >= 0.5 and candidate <= 32.0:
			exponent = candidate
			anchored = true
			field_ratio = ratio
			fallback_reason = "none"
	# Authored anchors constrain the model. Artistic exponent controls apply only
	# to fallback curves; changing an anchored exponent moves the 10% contour.
	if not anchored:
		exponent = clampf(exponent * pow(2.0, (0.32 - clampf(softness, 0.0, 1.0)) * 1.5) * clampf(radial_bias, 0.25, 4.0), 0.5, 32.0)
	var outer_support: float = 1.5 if soft else FIELD_FEATHER
	support_scale = field_ratio * outer_support if anchored else (1.65 if soft else 1.18)
	feather_start = 1.0 / outer_support if anchored else (0.72 if soft else 0.86)
	if anchored:
		# Softness may shape only the unmeasured tail beyond the authored field.
		feather_start = maxf(feather_start, 1.0 - clampf(softness / 0.32, 0.25, 1.0) * (1.0 - feather_start))
	coefficient = LN2 * pow(support_scale, exponent)
	var safe_ratio := clampf(rectangle_ratio if is_finite(rectangle_ratio) else 1.0, 0.01, 100.0)
	aspect = Vector2(sqrt(safe_ratio), 1.0 / sqrt(safe_ratio)).normalized() if rectangular else Vector2.ONE
	var next := Vector4(exponent, coefficient if projected else 0.0, aspect.x if rectangular else 0.0, aspect.y if rectangular else 0.0)
	signature = next
	return true

func sample_radius(beam_normalized_radius: float) -> float:
	return exp(-LN2 * pow(maxf(beam_normalized_radius, 0.0), exponent)) if projected else 0.0

func sample_support(point: Vector2) -> float:
	var metric: float = maxf(absf(point.x) / aspect.x, absf(point.y) / aspect.y) if rectangular else point.length()
	return sample_radius(metric * support_scale) * (1.0 - smoothstep(feather_start, 1.0, metric))

static func axial(distance_m: float, length_m: float, decay: float = 1.0) -> float:
	var d := maxf(distance_m, 0.0)
	var strength := maxf(decay, 0.0)
	return exp(-0.055 * strength * d) / (1.0 + 0.015 * strength * d * d) * (1.0 - smoothstep(TAIL_START, TAIL_END, d / maxf(length_m, 0.001)))

static func surface_distance(distance_m: float) -> float:
	return 1.0 / maxf(distance_m * distance_m, 0.0001)

func dynamic_field_angle(current_beam: float, base_beam: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(current_beam * 0.5)) * field_ratio)) if anchored and base_beam > 0.0 else current_beam

func native_angular_attenuation(beam_half: float, support_half: float) -> float:
	var rim := (1.0 - cos(deg_to_rad(beam_half))) / maxf(1.0 - cos(deg_to_rad(support_half)), 0.000001)
	return clampf(log(clampf(rim, 0.0001, 0.9999)) / -LN2, 0.05, 8.0)
