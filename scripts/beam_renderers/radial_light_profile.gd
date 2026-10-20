extends RefCounted

# Peraviz presentation approximation, not measured GDTF photometry. Tangent-space
# coordinates avoid atan per fragment while retaining both angular anchors exactly.
const LN2: float = 0.69314718056
const LN10: float = 2.30258509299
const EDGE_INTENSITY: float = 0.002
const TAIL_START: float = 0.72
const TAIL_END: float = 0.98
const TERMINAL_EPSILON: float = 0.000001

var exponent: float = 8.0
var coefficient: float = LN2
var support_scale: float = 1.0
var rectangular: bool = false
var aspect: Vector2 = Vector2.ONE
var projected: bool = true
var anchored: bool = false
var signature: Vector4 = Vector4.ZERO
var _configured: bool = false
var _kind: String
var _angles: Vector2
var _ratio: float
var _softness: float
var _bias: float

func configure(beam_type: String, beam_angle: float, field_angle: float, rectangle_ratio: float = 1.0, softness: float = 0.32, radial_bias: float = 1.0) -> bool:
	if _configured and _kind == beam_type and _angles == Vector2(beam_angle, field_angle) and _ratio == rectangle_ratio and _softness == softness and _bias == radial_bias:
		return false
	_configured = true
	_kind = beam_type
	_angles = Vector2(beam_angle, field_angle)
	_ratio = rectangle_ratio
	_softness = softness
	_bias = radial_bias
	var kind := beam_type.to_lower()
	projected = kind != "none" and kind != "glow"
	rectangular = kind == "rectangle"
	var soft: bool = kind in ["wash", "fresnel", "pc"]
	exponent = 2.0 if soft else 8.0
	anchored = false
	if is_finite(beam_angle) and is_finite(field_angle) and beam_angle > 0.0 and field_angle > beam_angle and field_angle < 178.0:
		var ratio := tan(deg_to_rad(field_angle * 0.5)) / tan(deg_to_rad(beam_angle * 0.5))
		var candidate := log(LN10 / LN2) / log(ratio)
		if is_finite(candidate) and candidate >= 0.5 and candidate <= 32.0:
			exponent = candidate
			anchored = true
	# Defaults retain the anchors. Artistic biases change the curve, never metadata.
	exponent = clampf(exponent * pow(2.0, (0.32 - clampf(softness, 0.0, 1.0)) * 1.5) * clampf(radial_bias, 0.25, 4.0), 0.5, 32.0)
	support_scale = pow(-log(EDGE_INTENSITY) / LN2, 1.0 / exponent)
	coefficient = LN2 * pow(support_scale, exponent)
	var safe_ratio := clampf(rectangle_ratio if is_finite(rectangle_ratio) else 1.0, 0.01, 100.0)
	aspect = Vector2(sqrt(safe_ratio), 1.0 / sqrt(safe_ratio)) if rectangular else Vector2.ONE
	var next := Vector4(exponent, coefficient if projected else 0.0, aspect.x if rectangular else 0.0, aspect.y if rectangular else 0.0)
	signature = next
	return true

func sample_radius(beam_normalized_radius: float) -> float:
	return exp(-LN2 * pow(maxf(beam_normalized_radius, 0.0), exponent)) if projected else 0.0

func sample_support(point: Vector2) -> float:
	var metric: float = maxf(absf(point.x) / aspect.x, absf(point.y) / aspect.y) if rectangular else point.length()
	return sample_radius(metric * support_scale) * (1.0 - smoothstep(0.96, 1.0, metric))

static func axial(distance_m: float, length_m: float, decay: float = 1.1) -> float:
	var d := maxf(distance_m, 0.0)
	var strength := maxf(decay, 0.0)
	return exp(-0.018 * strength * d) / (1.0 + 0.002 * strength * d * d) * (1.0 - smoothstep(TAIL_START, TAIL_END, d / maxf(length_m, 0.001)))

static func surface_distance(distance_m: float) -> float:
	return 1.0 / maxf(distance_m * distance_m, 0.0001)
