extends RefCounted

# Peraviz presentation geometry only: native GDTF/DMX semantics remain upstream.
# Coordinates are emitter-local; fixture ancestors supply Pan/Tilt to both consumers.
const META: StringName = &"peraviz_optical_projection_state"
const RadialProfile = preload("res://scripts/beam_renderers/radial_light_profile.gd")
const Geometry = preload("res://scripts/beam_geometry_calculator.gd")

var base_transform: Transform3D
var last_projector_transform: Transform3D
var footprint_applied: bool = false
var full_angle_deg: float = 25.0
var half_angle_deg: float = 12.5
var source_full_angle_deg: float = 25.0
var lens_radius: float = 0.03
var visual_range: float = 75.0
var far_radius: float = 0.03
var gobo_roll_deg: float = 0.0
var alignment_roll_deg: float = 0.0
var mirror_x: bool = true
var mirror_z: bool = false
var gobo_scale: float = 1.0
var lens_offset: Vector3 = Vector3.ZERO
var revision: int = 0
var geometry_revision: int = 0
var shaft_revision: int = -1
var footprint_revision: int = -1
var texture_id: int = 0
var configured: bool = false
var radial_profile: RefCounted = RadialProfile.new()
var profile_revision: int = 0
var pattern_texture: Texture2D
var surface_texture: Texture2D
var surface_source_id: int = -1
var surface_profile_revision: int = -1
var smooth_profile_enabled: bool = false
var base_beam_angle_deg: float = 25.0
var resolved_field_angle_deg: float = 25.0
var footprint_softness: float = 0.04
var surface_softness: float = -1.0
var native_angle_attenuation: float = 1.0
var has_projected_surface_profile: bool = false
var surface_uses_projector: bool = false

static func resolve(light: SpotLight3D) -> RefCounted:
	if light.has_meta(META):
		return light.get_meta(META) as RefCounted
	var state = load("res://scripts/runtime/optical_projection_state.gd").new()
	state.base_transform = light.transform
	light.set_meta(META, state)
	return state

func configure(params: Dictionary, texture: Texture2D) -> bool:
	# Godot's projector supports half apertures up to 89 degrees. Resolve this
	# engine presentation limit once; the shaft consumes the same full aperture.
	pattern_texture = texture
	var enable_profile := bool(params.get("smooth_light_profile", false))
	# Typed comparisons inside the reusable profile avoid temporary containers and
	# recomputing curves/textures during Zoom, color, intensity or roll playback.
	base_beam_angle_deg = float(params.get("profile_beam_angle", base_beam_angle_deg if configured else (params.get("beam_angle", 25.0) if bool(params.get("beam_angle_explicit", false)) else 25.0)))
	var previous_support: float = radial_profile.support_scale
	var previous_aspect: Vector2 = radial_profile.aspect
	var previous_rectangle: bool = radial_profile.rectangular
	var profile_changed: bool = radial_profile.configure(str(params.get("beam_type", "Wash")), base_beam_angle_deg, float(params.get("field_angle", 25.0)), float(params.get("rectangle_ratio", 1.0)), float(params.get("beam_softness", 0.32)), float(params.get("beam_radial_falloff", 1.0)), bool(params.get("beam_angle_explicit", false)), bool(params.get("field_angle_explicit", false)))
	has_projected_surface_profile = radial_profile.projected
	profile_changed = profile_changed or smooth_profile_enabled != enable_profile
	if profile_changed: profile_revision += 1
	footprint_softness = clampf(float(params.get("footprint_softness", 0.04)), 0.0, 0.25)
	var angle := clampf(float(params.get("beam_angle", 25.0)), 0.1, 178.0)
	var radius := maxf(float(params.get("lens_radius", 0.03)), 0.005)
	var length_m := Geometry.clamp_visual_length(float(params.get("beam_visual_length_m", params.get("beam_range", 75.0))))
	var scale_value := maxf(float(params.get("gobo_scale", 1.0)), 0.05)
	var alignment := float(params.get("beam_gobo_alignment_rotation_deg", 0.0))
	var mx := bool(params.get("beam_gobo_mirror_x", true))
	var mz := bool(params.get("beam_gobo_mirror_z", false))
	var offset := Vector3(float(params.get("lens_shift_x", 0.0)), float(params.get("lens_shift_y", 0.0)), -maxf(float(params.get("lens_offset_m", params.get("near_offset", 0.0))), 0.0))
	var next_texture: int = texture.get_instance_id() if texture != null else 0
	if configured and smooth_profile_enabled == enable_profile and previous_support == radial_profile.support_scale and previous_aspect == radial_profile.aspect and previous_rectangle == radial_profile.rectangular and source_full_angle_deg == angle and lens_radius == radius and visual_range == length_m and gobo_scale == scale_value and alignment_roll_deg == alignment and mirror_x == mx and mirror_z == mz and lens_offset == offset and texture_id == next_texture:
		# Artistic profile uniforms do not change aperture, topology or alignment.
		if profile_changed:
			resolved_field_angle_deg = radial_profile.dynamic_field_angle(angle, float(params.get("profile_beam_angle", angle)))
			revision += 1
		return profile_changed
	smooth_profile_enabled = enable_profile
	source_full_angle_deg = angle
	resolved_field_angle_deg = radial_profile.dynamic_field_angle(angle, float(params.get("profile_beam_angle", angle)))
	# Visual artwork scale expands the same cone for both consumers.
	half_angle_deg = rad_to_deg(atan(tan(deg_to_rad(angle * 0.5)) * scale_value * (radial_profile.support_scale if smooth_profile_enabled else 1.0)))
	var guarded_tangent := maxf(Geometry.RESOURCE_GUARD_RADIUS_M - radius * scale_value, 0.0) / length_m
	half_angle_deg = minf(half_angle_deg, minf(89.0, rad_to_deg(atan(guarded_tangent))))
	full_angle_deg = half_angle_deg * 2.0
	native_angle_attenuation = radial_profile.native_angular_attenuation(rad_to_deg(atan(tan(deg_to_rad(angle * 0.5)) * scale_value)), half_angle_deg)
	lens_radius = radius
	visual_range = length_m
	gobo_scale = scale_value
	alignment_roll_deg = alignment
	mirror_x = mx
	mirror_z = mz
	lens_offset = offset
	texture_id = next_texture
	far_radius = float(Geometry.far_radius_for_full_angle(radius * scale_value, full_angle_deg, length_m)["far_radius_m"])
	configured = true
	revision += 1
	geometry_revision += 1
	return true

func set_pattern(texture: Texture2D) -> void:
	if pattern_texture == texture: return
	pattern_texture = texture
	texture_id = texture.get_instance_id() if texture != null else 0
	# Selection also invalidates the shaft topology, including an open gobo
	# restored after presentation was suppressed. Roll never enters this path.
	geometry_revision += 1
	revision += 1

func set_roll(degrees: float) -> void:
	if is_equal_approx(gobo_roll_deg, degrees): return
	gobo_roll_deg = degrees
	revision += 1

func projector_roll() -> Basis:
	# Godot projector artwork rotates around emitted -Z. No Euler round trip.
	var parity_sign: float = 1.0 if mirror_x != mirror_z else -1.0
	return Basis(Vector3.FORWARD, deg_to_rad((alignment_roll_deg + gobo_roll_deg) * parity_sign))

func projector_basis() -> Basis:
	# Godot texture X is opposite raw prism artwork X at the reference parity.
	# Encode explicit visual mirror changes in texture-plane axes, never the axis Z.
	return projector_roll().scaled_local(Vector3(1.0 if mirror_x else -1.0, -1.0 if mirror_z else 1.0, 1.0))

func apply_footprint(light: SpotLight3D) -> void:
	# A fixture/emitter owner may explicitly replace its local optical transform.
	# Ancestor Pan/Tilt needs no state mutation: both consumers inherit it.
	if footprint_applied and not light.transform.is_equal_approx(last_projector_transform):
		var previous_origin := base_transform.origin
		base_transform = light.transform
		if light.position.is_equal_approx(last_projector_transform.origin):
			# A basis-only emitter write retains the anchor, not the lens offset
			# already applied by presentation. Never add that offset cumulatively.
			base_transform.origin = previous_origin
		revision += 1
	var resolved := base_transform
	resolved.origin += base_transform.basis * lens_offset
	resolved.basis = base_transform.basis * projector_basis()
	if not light.transform.is_equal_approx(resolved): light.transform = resolved
	if not is_equal_approx(light.spot_angle, half_angle_deg): light.spot_angle = half_angle_deg
	# Angular attenuation is already baked from the shared profile.
	if smooth_profile_enabled:
		if light.spot_attenuation != 2.0: light.spot_attenuation = 2.0
		var angular: float = 0.0 if texture_id != 0 or radial_profile.rectangular else native_angle_attenuation
		if light.spot_angle_attenuation != angular: light.spot_angle_attenuation = angular
	last_projector_transform = resolved
	footprint_applied = true
	footprint_revision = revision
	if light.has_meta(&"peraviz_custom_footprint"):
		light.get_meta(&"peraviz_custom_footprint").sync()

func apply_shaft(beam: MeshInstance3D) -> void:
	# Raw topology runs along Y. Preserve source-artwork X/right, Y/down and
	# explicit parity. Convert the resolved absolute basis to the rolled light's
	# child coordinates; never compensate an already-mutated child transform.
	var renderer_basis := Basis(Vector3.RIGHT, PI * 0.5)
	renderer_basis = renderer_basis.scaled_local(Vector3(-1.0 if mirror_x else 1.0, visual_range, -1.0 if mirror_z else 1.0))
	renderer_basis = renderer_basis * Basis(Vector3.UP, deg_to_rad(alignment_roll_deg + gobo_roll_deg))
	# Raw vector artwork X must follow projector U (+light X), not oppose it.
	# Apply this mesh-coordinate conversion after the shared roll/parity basis:
	# moving it before the roll would reverse rotation for asymmetric gobos.
	renderer_basis = renderer_basis.scaled_local(Vector3(-1.0, 1.0, 1.0))
	var inverse_roll := projector_basis().inverse()
	var resolved := Transform3D(inverse_roll * renderer_basis, inverse_roll * Vector3(0.0, 0.0, -visual_range * 0.5))
	if not beam.transform.is_equal_approx(resolved): beam.transform = resolved
	if not beam.has_meta(META): beam.set_meta(META, self)
	shaft_revision = revision

func diagnostic(params: Dictionary) -> String:
	var type_source := "explicit" if bool(params.get("beam_type_explicit", false)) else "gdtf-default"
	var beam_source := "explicit" if bool(params.get("beam_angle_explicit", false)) else "gdtf-default"
	var field_source := "explicit" if bool(params.get("field_angle_explicit", false)) else "gdtf-default"
	var base_angle := base_beam_angle_deg
	var source := "zoom" if not is_equal_approx(base_angle, source_full_angle_deg) else beam_source
	var review: bool = str(params.get("beam_type", "Wash")).to_lower() == "spot" and bool(params.get("beam_type_explicit", false)) and radial_profile.anchored and radial_profile.field_ratio > 3.0
	return "model=generalized-gaussian fallback=%s support_half_deg=%.3f BeamType=%s source=%s BeamAngle=%.3f source=%s BaseBeamAngle=%.3f source=%s FieldAngle=%.3f source=%s ResolvedFieldAngle=%.3f source=%s profile=%s shoulder_ratio=%.3f exponent=%.3f photometry_review=%s" % [radial_profile.fallback_reason, half_angle_deg, str(params.get("beam_type", "Wash")), type_source, source_full_angle_deg, source, base_angle, beam_source, float(params.get("field_angle", 25.0)), field_source, resolved_field_angle_deg, "scaled-from-base-profile" if radial_profile.anchored else "type-fallback", "anchored" if radial_profile.anchored else "fallback", radial_profile.field_ratio, radial_profile.exponent, "suspicious-spot-shoulder" if review else "none"]
