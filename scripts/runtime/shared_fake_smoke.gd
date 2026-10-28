extends RefCounted

# One application-wide presentation field. No fixture/DMX state or frame callbacks.
const DEFAULTS := {
	"fake_smoke_enabled":false, "fake_smoke_density":1.0, "fake_smoke_variation":0.35,
	"fake_smoke_scale_m":12.0, "fake_smoke_animation_speed":0.03,
	"fake_smoke_wind_direction_deg":35.0, "fake_smoke_wind_speed":0.12,
}
const KEYS := ["fake_smoke_enabled","fake_smoke_density","fake_smoke_variation","fake_smoke_scale_m","fake_smoke_animation_speed","fake_smoke_wind_direction_deg","fake_smoke_wind_speed"]
const VOLUME: Image = preload("res://resources/fake_smoke_density.res")
var _noise: ImageTexture3D

func apply_changed(settings: Dictionary, changes: Dictionary, initialize: bool = false) -> void:
	if initialize:
		apply(settings)
		return
	for key in changes:
		if key in KEYS:
			apply(settings)
			return

func apply(settings: Dictionary) -> void:
	var enabled: bool = bool(settings.get("fake_smoke_enabled",DEFAULTS.fake_smoke_enabled))
	if enabled and _noise == null:
		var slices: Array[Image] = []
		for z in range(32): slices.append(VOLUME.get_region(Rect2i(0,z*32,32,32)))
		_noise = ImageTexture3D.new()
		if _noise.create(Image.FORMAT_L8,32,32,32,false,slices) != OK:
			_noise = null
			enabled = false
		else: RenderingServer.global_shader_parameter_set("peraviz_fake_smoke_noise",_noise)
	var direction: float = deg_to_rad(float(settings.get("fake_smoke_wind_direction_deg",DEFAULTS.fake_smoke_wind_direction_deg)))
	var wind: float = clampf(float(settings.get("fake_smoke_wind_speed",DEFAULTS.fake_smoke_wind_speed)),0.0,2.0)
	RenderingServer.global_shader_parameter_set("peraviz_fake_smoke_shape",Vector3(clampf(float(settings.get("fake_smoke_density",DEFAULTS.fake_smoke_density)),0.0,2.0),clampf(float(settings.get("fake_smoke_variation",DEFAULTS.fake_smoke_variation)),0.0,1.0),1.0/clampf(float(settings.get("fake_smoke_scale_m",DEFAULTS.fake_smoke_scale_m)),2.0,40.0)))
	RenderingServer.global_shader_parameter_set("peraviz_fake_smoke_velocity",Vector3(cos(direction)*wind,clampf(float(settings.get("fake_smoke_animation_speed",DEFAULTS.fake_smoke_animation_speed)),0.0,0.5),sin(direction)*wind))
	RenderingServer.global_shader_parameter_set("peraviz_fake_smoke_enabled",enabled)

# The single application owner releases the field on exit, not on scene reload.
func release() -> void:
	RenderingServer.global_shader_parameter_set("peraviz_fake_smoke_enabled",false)
	RenderingServer.global_shader_parameter_set("peraviz_fake_smoke_noise",null)
	_noise = null
