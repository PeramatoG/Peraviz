extends SceneTree

const State = preload("res://scripts/runtime/optical_projection_state.gd")
const Profile = preload("res://scripts/beam_renderers/radial_light_profile.gd")
const Cache = preload("res://scripts/beam_renderers/footprint_profile_cache.gd")
const Energy = preload("res://scripts/beam_renderers/gobo_shaft_energy.gd")
const Builder = preload("res://scripts/beam_renderers/gobo_prism_mesh_builder.gd")
const Renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _init() -> void: call_deferred("run")

func run() -> void:
	for fixture in [
		{"beam_type": "Spot", "beam_type_explicit": true, "beam_angle_explicit": true, "field_angle_explicit": true, "profile_beam_angle": 10.0, "field_angle": 20.0},
		{"beam_type": "Spot", "beam_type_explicit": true, "beam_angle_explicit": true},
		{"beam_type": "Wash", "beam_type_explicit": true, "beam_angle_explicit": true, "field_angle_explicit": true, "profile_beam_angle": 10.0, "field_angle": 20.0},
		{},
		{"beam_type": "Wash", "beam_type_explicit": true, "beam_angle_explicit": true},
		{"beam_type": "Spot", "beam_type_explicit": true, "beam_angle_explicit": true, "field_angle_explicit": true, "profile_beam_angle": 20.0, "field_angle": 10.0}]:
		var state = State.new()
		fixture["beam_angle"] = 10.0
		fixture["smooth_light_profile"] = true
		state.configure(fixture, null)
		var anchored: bool = fixture.get("field_angle", 25) == 20
		test.check(state.radial_profile.anchored == anchored, "Only useful independently authored angles anchor the reconstruction")
		var ratio: float = tan(deg_to_rad(10.0)) / tan(deg_to_rad(5.0))
		var profile_id: int = state.radial_profile.get_instance_id()
		var revision: int = state.profile_revision
		for cycle in range(4):
			for angle in [5.0, 10.0, 35.0, 70.0, 10.0]:
				fixture["beam_angle"] = angle
				state.configure(fixture, null)
				if anchored:
					var expected := rad_to_deg(2 * atan(tan(deg_to_rad(angle * 0.5)) * ratio))
					test.check_close(state.resolved_field_angle_deg, expected, 0.0001, "FieldAngle follows Zoom tangent ratio without drift")
					test.check(tan(deg_to_rad(state.half_angle_deg)) <= tan(deg_to_rad(expected * 0.5)) * (1.501 if fixture.get("beam_type", "Wash") == "Wash" else 1.061), "Support respects the bounded type-specific tail")
				test.check(state.radial_profile.get_instance_id() == profile_id and state.profile_revision == revision, "Zoom cycling reuses the static base profile")
		if fixture.get("beam_type_explicit", false) == false:
			test.check(state.diagnostic(fixture).contains("BeamType=Wash source=gdtf-default") and state.diagnostic(fixture).contains("FieldAngle=25.000 source=gdtf-default"), "Defaults remain canonical and are reported as defaults")
	var soft = Profile.new()
	soft.configure("Wash", 25, 25, 1, 0.32, 1, false, false)
	var hard = Profile.new()
	hard.configure("Spot", 25, 25, 1, 0.32, 1, true, false)
	test.check(hard.support_scale < soft.support_scale and hard.support_scale <= 1.2 and soft.support_scale <= 1.7, "Fallback support stays compact and respects the authored BeamType")
	test.check(hard.native_angular_attenuation(5, 5.9) < soft.native_angular_attenuation(5, 8.25), "Native Wash angular falloff is softer than Spot")
	test.check(Profile.axial(10, 75, 1) < 0.3 and Profile.axial(25, 75, 1) < 0.04 and Profile.axial(1, 75, 1) > 0.8, "Reference axial decay is visible without a near-lens singularity")
	test.check(Profile.axial(25, 75, 0) == 1.0, "Zero decay leaves only the mandatory terminal window")
	var mask := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	for y in range(12, 52):
		for x in range(12, 52): mask.set_pixel(x, y, Color.WHITE)
	var source := ImageTexture.create_from_image(mask)
	var original := source.get_image().get_data()
	test.check(Energy.transmission(null) == 1.0 and Energy.transmission(source) > 0.0 and Energy.transmission(source) < 1.0, "Open transmission is unity and a partial mask only removes energy")
	var cache = Cache.new()
	var sharp: Texture2D = cache.texture_for(hard, source, 0)
	var normal: Texture2D = cache.texture_for(hard, source, 0.04)
	var blurred: Texture2D = cache.texture_for(hard, source, 0.2)
	var edge := Vector2i(22, 64)
	test.check(sharp.get_image().get_pixelv(edge).r < normal.get_image().get_pixelv(edge).r and normal.get_image().get_pixelv(edge).r <= blurred.get_image().get_pixelv(edge).r, "Cached softness progressively widens the mask edge")
	test.check(source.get_image().get_data() == original and cache.texture_for(hard, source, 0.04) == normal, "Softness preserves the GDTF source and reuses the derived texture")
	check_coverage()
	await check_surfaces()
	test.finish(self)

func check_coverage() -> void:
	var outer := PackedVector2Array([Vector2(-0.7,-0.7),Vector2(0.7,-0.7),Vector2(0.7,0.7),Vector2(-0.7,0.7)])
	var dense := PackedVector2Array()
	for edge in range(outer.size()):
		for step in range(8): dense.append(outer[edge].lerp(outer[(edge+1)%outer.size()], float(step)/8.0))
	var sparse_rings: Array[PackedVector2Array] = [outer]
	var dense_rings: Array[PackedVector2Array] = [dense]
	var sparse_gain := Energy.build(sparse_rings,null).get_image()
	var dense_gain := Energy.build(dense_rings,null).get_image()
	for row in range(0,Energy.DIRECTIONS,11):
		for column in range(0,Energy.OFFSETS,13):
			test.check_close(sparse_gain.get_pixel(column,row).r,dense_gain.get_pixel(column,row).r,0.00001,"Extra contour segments cannot change shaft gain")
	var many: Array[PackedVector2Array] = [outer]
	for index in range(8):
		var x := -0.65 + index * 0.18
		many.append(PackedVector2Array([Vector2(x,-0.3),Vector2(x+0.025,-0.3),Vector2(x+0.025,0.3),Vector2(x,0.3)]))
	var simple: Array[PackedVector2Array] = [outer, PackedVector2Array([Vector2(-0.1,-0.3),Vector2(0.1,-0.3),Vector2(0.1,0.3),Vector2(-0.1,0.3)])]
	var simple_chords := Energy.chord_lengths(simple)
	var complex_chords := Energy.chord_lengths(many)
	for row in range(0,Energy.DIRECTIONS,13):
		var simple_area := 0.0
		var complex_area := 0.0
		for column in range(Energy.OFFSETS):
			simple_area += simple_chords.get_pixel(column,row).r * 6.0 / Energy.OFFSETS
			complex_area += complex_chords.get_pixel(column,row).r * 6.0 / Energy.OFFSETS
		test.check_close(simple_area,complex_area,0.05,"Equal-area masks retain integrated chord energy regardless of hole count")
	for rings in [simple, many]:
		var table := Energy.build(rings, null).get_image()
		for direction in range(0, Energy.DIRECTIONS, 7):
			var normal := Vector2(cos(PI * (direction+0.5) / Energy.DIRECTIONS), sin(PI * (direction+0.5) / Energy.DIRECTIONS))
			for column in range(0, Energy.OFFSETS, 5):
				var offset := (float(column)+0.5)/Energy.OFFSETS*3.0-1.5
				var crossings := 0
				for ring in rings:
					for i in range(ring.size()):
						var a := normal.dot(ring[i])
						var b := normal.dot(ring[(i+1)%ring.size()])
						if minf(a,b) < offset and offset < maxf(a,b): crossings += 1
				test.check(table.get_pixel(column,direction).r * ceil(crossings*0.5) <= 1.00001, "Simple and many-hole topology cannot add source gain")

func check_surfaces() -> void:
	var renderer = Renderer.new()
	renderer.configure(null, {"beam_presentation": 1})
	for kind in ["Spot", "Wash", "PC", "Fresnel", "Rectangle"]:
		var light := SpotLight3D.new()
		root.add_child(light)
		var params := {"beam_type": kind, "beam_type_explicit": true, "scaled_intensity": 0.0, "beam_angle": 10.0}
		renderer.update_beam(light, params)
		var state: RefCounted = light.get_meta(State.META)
		test.check(state.configured and state.radial_profile.projected and light.spot_attenuation == 2.0, "Open footprint resolves even with zero shaft gain")
		test.check(state.base_beam_angle_deg == 25.0, "Missing base photometry retains the canonical default despite current Zoom")
		if kind != "Rectangle": test.check(light.light_projector == null and not light.shadow_enabled and light.spot_angle_attenuation > 0, "Ordinary open footprint uses native unshadowed falloff")
		else: test.check(light.light_projector == null and not light.shadow_enabled, "Open Rectangle data does not implicitly own a shadowed projector")
		light.free()
	var zoom_light := SpotLight3D.new()
	root.add_child(zoom_light)
	for angle in [10.0, 4.0, 30.0, 10.0]:
		renderer.update_beam(zoom_light, {"beam_type": "Spot", "beam_angle_explicit": true, "beam_angle": angle, "field_angle_explicit": true, "field_angle": 20.0, "scaled_intensity": 0.0})
		var state: RefCounted = zoom_light.get_meta(State.META)
		test.check_close(state.base_beam_angle_deg, 10.0, 0.0001, "Fresh compatibility parameter maps cannot replace the retained Zoom base")
		test.check_close(state.radial_profile.field_ratio, tan(deg_to_rad(10.0)) / tan(deg_to_rad(5.0)), 0.0001, "Renderer updates retain the base tangent ratio")
	zoom_light.free()
	await process_frame
