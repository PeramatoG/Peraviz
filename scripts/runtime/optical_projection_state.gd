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
var surface_texture: Texture2D
var surface_source_id: int = -1
var surface_profile_revision: int = -1
var smooth_profile_enabled: bool = false

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
	var enable_profile := bool(params.get("smooth_light_profile", false))
	# Typed comparisons inside the reusable profile avoid temporary containers and
	# recomputing curves/textures during Zoom, color, intensity or roll playback.
	var profile_changed: bool = radial_profile.configure(str(params.get("beam_type", "Spot")), float(params.get("profile_beam_angle", params.get("beam_angle", 25.0))), float(params.get("field_angle", 0.0)), float(params.get("rectangle_ratio", 1.0)), float(params.get("beam_softness", 0.32)), float(params.get("beam_radial_falloff", 1.0)))
	profile_changed = profile_changed or smooth_profile_enabled != enable_profile
	if profile_changed: profile_revision += 1
	var angle := clampf(float(params.get("beam_angle", 25.0)), 0.1, 178.0)
	var radius := maxf(float(params.get("lens_radius", 0.03)), 0.005)
	var length_m := Geometry.clamp_visual_length(float(params.get("beam_visual_length_m", params.get("beam_range", 75.0))))
	var scale_value := maxf(float(params.get("gobo_scale", 1.0)), 0.05)
	var alignment := float(params.get("beam_gobo_alignment_rotation_deg", 0.0))
	var mx := bool(params.get("beam_gobo_mirror_x", true))
	var mz := bool(params.get("beam_gobo_mirror_z", false))
	var offset := Vector3(float(params.get("lens_shift_x", 0.0)), float(params.get("lens_shift_y", 0.0)), -maxf(float(params.get("lens_offset_m", params.get("near_offset", 0.0))), 0.0))
	var next_texture: int = texture.get_instance_id() if texture != null else 0
	if configured and not profile_changed and source_full_angle_deg == angle and lens_radius == radius and visual_range == length_m and gobo_scale == scale_value and alignment_roll_deg == alignment and mirror_x == mx and mirror_z == mz and lens_offset == offset and texture_id == next_texture:
		return false
	smooth_profile_enabled = enable_profile
	source_full_angle_deg = angle
	# Visual artwork scale expands the same cone for both consumers.
	half_angle_deg = rad_to_deg(atan(tan(deg_to_rad(angle * 0.5)) * scale_value * (radial_profile.support_scale if smooth_profile_enabled else 1.0)))
	var guarded_tangent := maxf(Geometry.RESOURCE_GUARD_RADIUS_M - radius * scale_value, 0.0) / length_m
	half_angle_deg = minf(half_angle_deg, minf(89.0, rad_to_deg(atan(guarded_tangent))))
	full_angle_deg = half_angle_deg * 2.0
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
		if light.spot_angle_attenuation != 0.0: light.spot_angle_attenuation = 0.0
	last_projector_transform = resolved
	footprint_applied = true
	footprint_revision = revision

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
