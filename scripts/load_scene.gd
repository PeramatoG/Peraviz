@tool
extends Node3D

@onready var proxies_root: Node3D = $Proxies
@onready var status_label: Label = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow/StatusLabel
@onready var picker: FileDialog = $UIRoot/FileDialog
@onready var camera: Camera3D = $Camera3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var day_night_environment_controller: DayNightEnvironmentController = $DayNightEnvironmentController
@onready var user_module: VBoxContainer = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/User
@onready var advanced_module: VBoxContainer = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Advanced
@onready var auto_load_last_project_toggle: CheckButton = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow/AutoLoadLastProjectToggle
@onready var auto_start_dmx_project_toggle: CheckButton = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Advanced/AutoStartDmxProjectToggle
@onready var debug_module: VBoxContainer = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug
@onready var manual_fixture_toggle: CheckButton = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/ManualFixtureToggle
@onready var fixture_debug_panel: PanelContainer = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel
@onready var fixture_list: ItemList = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/FixtureList
@onready var fixture_selected_label: Label = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/SelectedFixtureLabel
@onready var fixture_axis_label: Label = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/AxisAnchorsLabel
@onready var fixture_emitter_label: Label = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/EmitterAnchorsLabel
@onready var pan_min_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/PanMin
@onready var pan_max_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/PanMax
@onready var pan_value_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/PanValue
@onready var tilt_min_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/TiltMin
@onready var tilt_max_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/TiltMax
@onready var tilt_value_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/TiltValue
@onready var dimmer_min_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/DimmerMin
@onready var dimmer_max_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/DimmerMax
@onready var dimmer_value_input: SpinBox = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/LimitsGrid/DimmerValue
@onready var pan_slider: HSlider = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/PanSlider
@onready var tilt_slider: HSlider = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/TiltSlider
@onready var dimmer_slider: HSlider = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/DimmerSlider
@onready var quick_reset_button: Button = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/Debug/FixtureDebugPanel/Margin/VBox/QuickResetButton
@onready var visual_settings_button: Button = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow/VisualSettingsButton
@onready var show_advanced_controls_toggle: CheckButton = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow/ShowAdvancedControlsToggle
@onready var visual_settings_window: VisualSettingsWindow = $UIRoot/VisualSettingsWindow
@onready var app_shell: AppShell = $UIRoot/AppShell
@onready var load_button: Button = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow/LoadButton
@onready var save_project_button: Button = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow/SaveProjectButton
@onready var dmx_controls_mount: VBoxContainer = $UIRoot/RootVBox/ContentRow/SidePanel/SidePanelMargin/ModulesVBox/User/DMXControlsMount
@onready var topbar_row: HBoxContainer = $UIRoot/RootVBox/TopBar/TopBarMargin/TopBarRow

var _loader := PeravizLoader.new()
var _scene_registry := SceneRegistry.new()
var _loaded_bounds: AABB
var _has_loaded_bounds: bool = false
var _node_index: Dictionary = {}
var _asset_cache := PeravizRuntimeAssetCache.new()
var _debug_coords_enabled: bool = false
var _debug_asset_cache_enabled: bool = false
var _debug_gizmos_root: Node3D
var _fixture_emissive_cache: Dictionary = {}
var _fixture_emitter_light_cache: Dictionary = {}
var _fixture_geometry_nodes_cache: Dictionary = {}
var _fixture_emitter_nodes_cache: Dictionary = {}
var _fixture_axis_nodes_cache: Dictionary = {}
var _native_pan_targets: Dictionary = {}
var _native_tilt_targets: Dictionary = {}
var _native_dimmer_targets: Dictionary = {}
var _native_target_resolution_failures: Dictionary = {}
var _native_geometry_targets_by_key: Dictionary = {}
var _native_dimmer_emitter_owner_by_key: Dictionary = {}
var _native_target_registry_summary: Dictionary = {}
var _fixture_emitter_last_state: Dictionary = {}
var _fixture_emitter_photometrics: Dictionary = {}
var _fixture_gobo_projector: FixtureGoboProjector = null
var _ui_controller: UiController
var _dmx_controller: DmxController
var _mvr_xchange_controller: MvrXchangeController
var _mvr_xchange_panel
var _fixture_debug_controller: FixtureDebugController
var _fixture_inspection_panel: FixtureInspectionPanel
var _loaded_mvr_path: String = ""
var _last_loaded_file_type: String = ""
var _visual_environment_baseline := {
	"ambient_light_energy": 0.2,
	"ambient_light_sky_contribution": 0.0,
	"glow_bloom": 0.05,
	"glow_intensity": 0.55,
	"glow_strength": 0.55,
	"background_color": Color(0.129412, 0.137255, 0.156863, 1.0),
}
var _cached_beam_defaults: Dictionary = {}
var _beam_params_template_cache: Dictionary = {}
var _visual_settings := {
	"ambient_multiplier": 0.08,
	"spot_multiplier": 1.0,
	"enable_realtime_spotlights": false,
	"beam_multiplier": 20.0,
	"bloom_multiplier": 0.0,
	"beam_render_mode": 0,
	"beam_quality": 2,
	"use_fog_volume_gobo_beam": false,
	"fog_volume_density_scale": 1.1,
	"fog_volume_emission_strength": 0.6,
	"fog_volume_edge_softness": 0.65,
	"fog_volume_invert_gobo": false,
	"beam_haze_density": 0.17,
	"beam_anisotropy": 0.62,
	"beam_noise_amount": 0.06,
	"beam_noise_scale": 1.4,
	"beam_softness": 0.32,
	"beam_radial_falloff": 1.25,
	"beam_longitudinal_falloff": 1.1,
	"haze_density_multiplier": 0.22,
	"gobo_scale": 1.0,
	"gobo_rotation_deg": 0.0,
	"beam_gobo_alignment_rotation_deg": 0.0,
	"beam_gobo_mirror_x": true,
	"beam_gobo_mirror_z": false,
	"lens_offset_m": 0.015,
	"near_offset": 0.015,
	"lens_shift_x": 0.0,
	"lens_shift_y": 0.0,
	"beam_debug_optics": false,
	"ambient_fog_density": 0.0,
	"volumetric_fog_density": 0.0,
	"volumetric_fog_fade": 0.02,
	"light_volumetric_fog_energy": 12.0,
	"use_native_fog_projector_gobos": true,
	"background_color": Color(0.129412, 0.137255, 0.156863, 1.0),
	"environment_enabled": true,
	"environment_use_continuous_cycle": false,
	"environment_current_preset": 1,
	"environment_time_of_day": 0.4,
	"environment_auto_advance": false,
	"environment_cycle_speed": 0.02,
	"environment_allow_blackout_night": true,
	"environment_day_light_intensity": 0.7,
	"environment_dusk_light_intensity": 0.18,
	"environment_night_light_intensity": 0.02,
	"environment_moon_light_intensity": 0.012,
	"environment_ambient_energy_day": 0.08,
	"environment_ambient_energy_night": 0.008,
	"environment_horizon_warmth": 0.6,
	"environment_horizon_intensity": 1.0,
	"gobo_debug_override_enabled": false,
	"gobo_debug_comparison_mode": 0,
	"gobo_debug_shake_enabled": false,
	"gobo_debug_shake_amplitude_deg": 1.0,
	"gobo_debug_shake_frequency_hz": 1.0,
	"gobo_debug_shake_waveform": 0,
}


var _beam_renderers: Dictionary = {}
var _fixture_light_apply_service: FixtureLightApplyService
var _live_gobo_diagnostic_keys: Dictionary = {}
var _active_beam_renderer: BeamRendererBase
var _active_beam_mode: int = -1

const BeamRendererBaseScript = preload("res://scripts/beam_renderers/beam_renderer_base.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const FixtureGoboProjectorScript = preload("res://scripts/fixture_gobo_projector.gd")
const BeamOpticsControllerScript = preload("res://scripts/beam_optics_controller.gd")
const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const UiVisibilityPolicyScript = preload("res://scripts/ui/ui_visibility_policy.gd")
const UiControllerScript = preload("res://scripts/controllers/ui_controller.gd")
const DmxControllerScript = preload("res://scripts/controllers/dmx_controller.gd")
const MvrXchangeControllerScript = preload("res://scripts/controllers/mvr_xchange_controller.gd")
const FixtureInspectionPanelScript = preload("res://scripts/ui/fixture_inspection_panel.gd")
const PeravizProjectArchiveScript = preload("res://scripts/project/peraviz_project_archive.gd")
const FixtureDebugControllerScript = preload("res://scripts/controllers/fixture_debug_controller.gd")
const StatusPresenterScript = preload("res://scripts/ui/status_presenter.gd")
const UserPreferencesScript = preload("res://scripts/ui/user_preferences.gd")
const MvrXchangePanelScript = preload("res://scripts/ui/mvr_xchange_panel.gd")

const SUPPORTED_LAST_FILE_TYPES := ["mvr", "pvz"]

const SceneImportServiceScript = preload("res://scripts/scene_loading/scene_import_service.gd")
const NodeFactoryScript = preload("res://scripts/scene_loading/node_factory.gd")
const FixtureBindingServiceScript = preload("res://scripts/scene_loading/fixture_binding_service.gd")
const DebugOverlayServiceScript = preload("res://scripts/scene_loading/debug_overlay_service.gd")
const FixtureRowProviderScript = preload("res://scripts/scene_loading/fixture_row_provider.gd")

var _scene_import_service := SceneImportServiceScript.new()
var _project_archive := PeravizProjectArchiveScript.new()
var _node_factory := NodeFactoryScript.new()
var _fixture_binding_service := FixtureBindingServiceScript.new()
var _debug_overlay_service := DebugOverlayServiceScript.new()
var _fixture_row_provider := FixtureRowProviderScript.new()
var _status_presenter: StatusPresenter
var _user_preferences: UserPreferences
var _debug_properties_applied: int = 0
var _debug_properties_skipped: int = 0
var _selected_fixture_badge_uuid: String = ""
var _emitter_mesh_rebuild_count: int = 0
var _emitter_parametric_update_count: int = 0

const DEBUG_TOGGLE_KEY: Key = KEY_C
const MANUAL_TEST_FLAG: String = "--peraviz_manual_fixture_test"
const DEFAULT_EMITTER_PHOTOMETRICS := {
	"luminous_flux": 10000.0,
	"color_temperature": 6000.0,
	"has_color_temperature": false,
	"beam_angle": 25.0,
	"field_angle": 25.0,
	"beam_radius": 0.05,
	"beam_radius_from_gdtf": false,
	"dominant_wavelength": 0.0,
}

# Keep emitter light direction aligned with fixture zero-position beam expectation
# (aligned with fixture lens output in runtime scenes) while still inheriting GDTF emitter transforms.
const EMITTER_LIGHT_DIRECTION_FIX: Vector3 = Vector3(-90.0, 0.0, 0.0)
const IMPORTED_CONTENT_SCALE: float = 1.0
const EMITTER_LIGHT_MIN_RANGE_M: float = 12.0
const EMITTER_LIGHT_MAX_RANGE_M: float = 150.0
const EMITTER_LIGHT_RANGE_BEAM_RADIUS_MULTIPLIER: float = 500.0
const EMITTER_LIGHT_ENERGY_SCALE: float = 0.02
const EMITTER_LIGHT_MAX_BEAM_ANGLE_DEG: float = 180.0
const BEAM_COLOR_TEMPERATURE_STRENGTH: float = 0.04
const BEAM_PARAMS_TEMPLATE_CACHE_LIMIT: int = 256
const EMITTER_ZOOM_DEFAULT_MIN_BEAM_ANGLE_DEG: float = 4.0
const EMITTER_ZOOM_DEFAULT_MAX_BEAM_ANGLE_DEG: float = EMITTER_LIGHT_MAX_BEAM_ANGLE_DEG
const EMITTER_ZOOM_LENS_RANGE_REFERENCE_M: float = 12.0
const EMITTER_CONE_MAX_BASE_RADIUS_M: float = 10.0
const EMITTER_LIGHT_MAX_FOOTPRINT_RADIUS_M: float = EMITTER_CONE_MAX_BASE_RADIUS_M
const EMITTER_LIGHT_MIN_EFFECTIVE_RANGE_M: float = 0.75
const EMITTER_BEAM_LENGTH_SCALE: float = 3.0
const EMITTER_LIGHT_FOOTPRINT_RANGE_MULTIPLIER: float = 1.0
const EMITTER_LIGHT_SPOT_ATTENUATION_MIN: float = 0.0669
const EMITTER_LIGHT_SPOT_ATTENUATION_MAX: float = 1.5
const EMITTER_CONE_FADE_END_RATIO: float = 0.82
const EMITTER_CONE_NEAR_ALPHA: float = 0.16
const EMITTER_CONE_FAR_ALPHA: float = 0.004
const EMITTER_CONE_NEAR_EMISSION: float = 0.45
const EMITTER_CONE_FAR_EMISSION: float = 0.04
const VISUAL_SETTINGS_PROJECT_KEY: String = "peraviz_visual_settings"
const BEAM_RENDER_MODE_VOLUMETRIC: int = 0
const BEAM_RENDER_MODE_LEGACY: int = 1
const BEAM_INTENSITY_VISIBILITY_THRESHOLD: float = 0.015
const BEAM_DISTANCE_CULL_M: float = 180.0
const BEAM_INTENSITY_MAX: float = 100.0
const EMITTER_LIGHT_STATE_EPSILON: float = 0.0001
const EMITTER_LIGHT_COLOR_EPSILON: float = 0.001

const ENV_QUALITY_PRESET_SETTING: String = "peraviz_environment_quality"
const ENV_QUALITY_PRESET_DEFAULT: String = "high"
const ENVIRONMENT_QUALITY_PRESETS := {
	"low": {
		"ssao_enabled": false,
		"glow_enabled": false,
		"glow_bloom": 0.0,
		"dof_blur_far_enabled": false,
		"dof_blur_near_enabled": false,
	},
	"medium": {
		"ssao_enabled": true,
		"ssao_radius": 0.7,
		"ssao_intensity": 0.35,
		"glow_enabled": true,
		"glow_bloom": 0.05,
		"glow_intensity": 0.55,
		"glow_strength": 0.55,
		"dof_blur_far_enabled": false,
		"dof_blur_near_enabled": false,
	},
	"high": {
		"ssao_enabled": true,
		"ssao_radius": 1.0,
		"ssao_intensity": 0.5,
		"glow_enabled": true,
		"glow_bloom": 0.1,
		"glow_intensity": 0.7,
		"glow_strength": 0.7,
		"dof_blur_far_enabled": false,
		"dof_blur_near_enabled": false,
	},
}

func _ready() -> void:
	_cached_beam_defaults = BeamOpticsControllerScript.BuildDefaultMasterOptics()
	_beam_params_template_cache.clear()
	_apply_imported_content_scale()
	_scene_registry.configure(proxies_root)
	_fixture_row_provider.configure(_loader, _scene_registry)
	manual_fixture_toggle.toggled.connect(_on_manual_fixture_toggle)
	show_advanced_controls_toggle.toggled.connect(_on_show_advanced_controls_toggled)
	if auto_load_last_project_toggle != null:
		auto_load_last_project_toggle.toggled.connect(_on_auto_load_last_project_toggled)
	if auto_start_dmx_project_toggle != null:
		auto_start_dmx_project_toggle.toggled.connect(_on_auto_start_dmx_project_toggled)
	if visual_settings_window != null and visual_settings_window.has_signal("settings_changed"):
		visual_settings_window.connect("settings_changed", Callable(self, "_on_visual_settings_changed"))
	else:
		push_warning("VisualSettingsWindow is missing signal 'settings_changed'; live visual updates disabled.")
	_ui_controller = UiControllerScript.new()
	_ui_controller.configure(
		load_button,
		save_project_button,
		visual_settings_button,
		picker,
		Callable(self, "_on_file_selected"),
		Callable(self, "_on_save_project_selected"),
		Callable(self, "_open_visual_settings_window")
	)
	_fixture_debug_controller = FixtureDebugControllerScript.new()
	_fixture_debug_controller.configure(
		self,
		_scene_registry,
		_fixture_row_provider,
		camera,
		{
			"manual_fixture_toggle": manual_fixture_toggle,
			"fixture_debug_panel": fixture_debug_panel,
			"fixture_list": fixture_list,
			"fixture_selected_label": fixture_selected_label,
			"fixture_axis_label": fixture_axis_label,
			"fixture_emitter_label": fixture_emitter_label,
			"pan_min_input": pan_min_input,
			"pan_max_input": pan_max_input,
			"pan_value_input": pan_value_input,
			"tilt_min_input": tilt_min_input,
			"tilt_max_input": tilt_max_input,
			"tilt_value_input": tilt_value_input,
			"dimmer_min_input": dimmer_min_input,
			"dimmer_max_input": dimmer_max_input,
			"dimmer_value_input": dimmer_value_input,
			"pan_slider": pan_slider,
			"tilt_slider": tilt_slider,
			"dimmer_slider": dimmer_slider,
			"quick_reset_button": quick_reset_button,
		},
		Callable(self, "_resolve_fixture_uuid_from_node"),
		Callable(self, "_apply_fixture_controls_from_debug")
	)
	_dmx_controller = DmxControllerScript.new()
	_dmx_controller.configure(
		self,
		Callable(self, "_resolve_dmx_controls_host"),
		Callable(self, "_apply_dmx_controls_to_fixture")
	)
	_dmx_controller.set_status_callbacks(
		Callable(self, "_on_dmx_status_changed"),
		Callable(self, "_on_dmx_start_failed")
	)
	_status_presenter = StatusPresenterScript.new()
	_status_presenter.configure(self, status_label, topbar_row, load_button, show_advanced_controls_toggle)
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.mvr, *.pvz ; MVR or Peraviz Project", "*.mvr ; MVR", "*.pvz ; Peraviz Project"])
	_debug_coords_enabled = bool(ProjectSettings.get_setting("peraviz_debug_coords", false))
	_debug_asset_cache_enabled = bool(ProjectSettings.get_setting("peraviz_debug_asset_cache", false))
	var manual_fixture_test_enabled: bool = _read_manual_fixture_test_setting()
	_fixture_debug_controller.set_manual_fixture_test_enabled(manual_fixture_test_enabled)
	_load_user_preferences()
	_refresh_ui_module_visibility()
	_asset_cache.configure_debug_logging(_debug_asset_cache_enabled, 100)
	_ensure_debug_gizmo_root()
	_update_debug_legend()
	_refresh_emitter_light_scalars()
	_setup_fixture_inspection_panel()
	_refresh_fixture_debug_panel()
	_setup_dmx_controls()
	_setup_mvr_xchange_panel()
	_fixture_light_apply_service = FixtureLightApplyServiceScript.new()
	_setup_dmx_fixture_runtime()
	_apply_environment_quality_preset()
	_capture_visual_environment_baseline()
	_load_visual_settings_from_project()
	_initialize_beam_renderers()
	_fixture_gobo_projector = FixtureGoboProjectorScript.new()
	if visual_settings_window != null and visual_settings_window.has_method("configure"):
		visual_settings_window.call("configure", _visual_settings)
		if visual_settings_window.has_method("set_ui_visibility_policy"):
			visual_settings_window.call("set_ui_visibility_policy", UiVisibilityPolicyScript)
		_apply_visual_settings_preferences_to_window()
	else:
		push_warning("VisualSettingsWindow is not ready for configure(); initial visual settings not pushed.")
	_apply_visual_settings(_visual_settings)
	_refresh_day_night_environment_controller()
	call_deferred("_auto_load_last_file_from_preferences")


func _apply_imported_content_scale() -> void:
	if proxies_root == null:
		return
	proxies_root.scale = Vector3.ONE * IMPORTED_CONTENT_SCALE

func _apply_environment_quality_preset() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var requested_preset: String = str(ProjectSettings.get_setting(ENV_QUALITY_PRESET_SETTING, ENV_QUALITY_PRESET_DEFAULT)).to_lower()
	if not ENVIRONMENT_QUALITY_PRESETS.has(requested_preset):
		requested_preset = ENV_QUALITY_PRESET_DEFAULT
	var preset_config: Dictionary = ENVIRONMENT_QUALITY_PRESETS.get(requested_preset, {})
	for property_name in preset_config.keys():
		world_environment.environment.set(property_name, preset_config[property_name])

func _capture_visual_environment_baseline() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	_visual_environment_baseline["ambient_light_energy"] = float(world_environment.environment.ambient_light_energy)
	if _environment_has_property(world_environment.environment, "ambient_light_sky_contribution"):
		_visual_environment_baseline["ambient_light_sky_contribution"] = float(world_environment.environment.ambient_light_sky_contribution)
	_visual_environment_baseline["glow_bloom"] = float(world_environment.environment.glow_bloom)
	_visual_environment_baseline["glow_intensity"] = float(world_environment.environment.glow_intensity)
	_visual_environment_baseline["glow_strength"] = float(world_environment.environment.glow_strength)
	_visual_environment_baseline["background_color"] = world_environment.environment.background_color
	_visual_settings["background_color"] = _visual_environment_baseline["background_color"]

func _load_visual_settings_from_project() -> void:
	# Debug workflow: keep visual settings ephemeral during runtime.
	# Do not read prior persisted overrides from project settings.
	return

func _save_visual_settings_to_project() -> void:
	# Debug workflow: avoid writing visual overrides to project.godot.
	return

func _initialize_beam_renderers() -> void:
	_beam_renderers[BEAM_RENDER_MODE_LEGACY] = LegacyConeBeamRendererScript.new()
	_beam_renderers[BEAM_RENDER_MODE_VOLUMETRIC] = VolumetricBeamRendererScript.new()
	_update_beam_renderer_mode(true)

func _apply_visual_settings(settings: Dictionary) -> void:
	var previous_settings: Dictionary = _visual_settings.duplicate(true)
	for key in _visual_settings.keys():
		if settings.has(key):
			_visual_settings[key] = settings[key]

	if world_environment != null and world_environment.environment != null:
		if _environment_has_property(world_environment.environment, "ambient_light_source"):
			world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_environment.environment.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
		var ambient_multiplier: float = float(_visual_settings.get("ambient_multiplier", 0.08))
		world_environment.environment.ambient_light_energy = ambient_multiplier
		if _environment_has_property(world_environment.environment, "ambient_light_sky_contribution"):
			world_environment.environment.ambient_light_sky_contribution = 0.0
		var bloom_multiplier: float = float(_visual_settings.get("bloom_multiplier", 0.0))
		world_environment.environment.glow_enabled = bloom_multiplier > 0.001
		world_environment.environment.glow_bloom = float(_visual_environment_baseline.get("glow_bloom", 0.05)) * bloom_multiplier
		world_environment.environment.glow_intensity = float(_visual_environment_baseline.get("glow_intensity", 0.55)) * bloom_multiplier
		world_environment.environment.glow_strength = float(_visual_environment_baseline.get("glow_strength", 0.55)) * bloom_multiplier
		world_environment.environment.background_color = _visual_settings.get("background_color", _visual_environment_baseline.get("background_color", Color(0.129412, 0.137255, 0.156863, 1.0)))
		var ambient_fog_density: float = max(float(_visual_settings.get("ambient_fog_density", 0.0)), 0.0)
		world_environment.environment.fog_enabled = ambient_fog_density > 0.0001
		if world_environment.environment.fog_enabled:
			world_environment.environment.fog_density = ambient_fog_density
		var volumetric_fog_density: float = max(float(_visual_settings.get("volumetric_fog_density", 0.0)), 0.0)
		world_environment.environment.volumetric_fog_enabled = volumetric_fog_density > 0.0001
		world_environment.environment.volumetric_fog_density = volumetric_fog_density
		if _environment_has_property(world_environment.environment, "volumetric_fog_fade"):
			world_environment.environment.volumetric_fog_fade = max(float(_visual_settings.get("volumetric_fog_fade", 0.02)), 0.005)

	# Renderer-level volumetric fog froxel settings are kept static in project.godot.
	# Do not mutate froxel sizing/filtering at runtime, as it can cause renderer signal churn.

	_beam_params_template_cache.clear()
	_update_beam_renderer_mode(false)
	_save_visual_settings_to_project()
	_refresh_emitter_light_scalars()

	var beam_scalar_changed: bool = (
		not is_equal_approx(float(previous_settings.get("beam_multiplier", 20.0)), float(_visual_settings.get("beam_multiplier", 20.0)))
		or int(previous_settings.get("beam_quality", 1)) != int(_visual_settings.get("beam_quality", 1))
	)
	if beam_scalar_changed:
		_refresh_existing_beam_material_scalars()
	_refresh_day_night_environment_controller()



func _environment_has_property(environment: Environment, property_name: String) -> bool:
	if environment == null:
		return false
	for entry in environment.get_property_list():
		if str(entry.get("name", "")) == property_name:
			return true
	return false

func _refresh_day_night_environment_controller() -> void:
	if day_night_environment_controller == null:
		return
	_apply_day_night_settings_from_visual_controls()
	day_night_environment_controller.apply_now()

func _apply_day_night_settings_from_visual_controls() -> void:
	day_night_environment_controller.enabled = bool(_visual_settings.get("environment_enabled", true))
	day_night_environment_controller.use_continuous_cycle = bool(_visual_settings.get("environment_use_continuous_cycle", false))
	day_night_environment_controller.current_preset = int(clamp(int(_visual_settings.get("environment_current_preset", 1)), 0, 4)) as DayNightEnvironmentController.EnvironmentPreset
	day_night_environment_controller.time_of_day = clampf(float(_visual_settings.get("environment_time_of_day", 0.4)), 0.0, 1.0)
	day_night_environment_controller.auto_advance = bool(_visual_settings.get("environment_auto_advance", false))
	day_night_environment_controller.cycle_speed = max(float(_visual_settings.get("environment_cycle_speed", 0.02)), 0.0)
	day_night_environment_controller.allow_blackout_night = bool(_visual_settings.get("environment_allow_blackout_night", true))
	day_night_environment_controller.day_light_intensity = max(float(_visual_settings.get("environment_day_light_intensity", 0.7)), 0.0)
	day_night_environment_controller.dusk_light_intensity = max(float(_visual_settings.get("environment_dusk_light_intensity", 0.18)), 0.0)
	day_night_environment_controller.night_light_intensity = max(float(_visual_settings.get("environment_night_light_intensity", 0.02)), 0.0)
	day_night_environment_controller.moon_light_intensity = max(float(_visual_settings.get("environment_moon_light_intensity", 0.012)), 0.0)
	day_night_environment_controller.ambient_energy_day = max(float(_visual_settings.get("environment_ambient_energy_day", 0.08)), 0.0)
	day_night_environment_controller.ambient_energy_night = max(float(_visual_settings.get("environment_ambient_energy_night", 0.008)), 0.0)
	day_night_environment_controller.horizon_warmth = clampf(float(_visual_settings.get("environment_horizon_warmth", 0.6)), 0.0, 1.0)
	day_night_environment_controller.horizon_intensity = clampf(float(_visual_settings.get("environment_horizon_intensity", 1.0)), 0.0, 2.0)

func _update_beam_renderer_mode(force_refresh: bool) -> void:
	var requested_mode: int = int(clamp(int(_visual_settings.get("beam_render_mode", BEAM_RENDER_MODE_VOLUMETRIC)), BEAM_RENDER_MODE_VOLUMETRIC, BEAM_RENDER_MODE_LEGACY))
	var requested_renderer: BeamRendererBase = _beam_renderers.get(requested_mode, null)
	if requested_renderer == null:
		requested_mode = BEAM_RENDER_MODE_LEGACY
		requested_renderer = _beam_renderers.get(requested_mode, null)
	if requested_renderer == null:
		return

	if force_refresh or requested_mode != _active_beam_mode:
		for fixture_uuid in _fixture_emitter_light_cache.keys():
			var lights: Array = _fixture_emitter_light_cache.get(fixture_uuid, [])
			for light_node in lights:
				if light_node is SpotLight3D and is_instance_valid(light_node):
					_cleanup_light_beam_renderers(light_node)

	_active_beam_mode = requested_mode
	_active_beam_renderer = requested_renderer
	if _status_presenter != null:
		var render_mode_label: String = "Volumetric" if _active_beam_mode == BEAM_RENDER_MODE_VOLUMETRIC else "Legacy"
		_status_presenter.set_render_mode_badge(render_mode_label)
	for renderer in _beam_renderers.values():
		if renderer is BeamRendererBase:
			renderer.configure(camera, _visual_settings)

func _cleanup_light_beam_renderers(light: SpotLight3D) -> void:
	for renderer in _beam_renderers.values():
		if renderer is BeamRendererBase:
			renderer.cleanup_beam(light)

func _refresh_emitter_light_scalars() -> void:
	for fixture_uuid in _fixture_emitter_light_cache.keys():
		var lights: Array = _fixture_emitter_light_cache.get(fixture_uuid, [])
		for light in lights:
			if light is SpotLight3D and is_instance_valid(light):
				_apply_light_scalars_to_light(light)

func _refresh_existing_beam_material_scalars() -> void:
	for fixture_uuid in _fixture_emitter_light_cache.keys():
		var lights: Array = _fixture_emitter_light_cache.get(fixture_uuid, [])
		for light in lights:
			if light is SpotLight3D and is_instance_valid(light):
				_update_existing_beam_material_scalars(light)

func _apply_light_scalars_to_light(light: SpotLight3D) -> void:
	var light_rid: RID = _get_light_base_rid(light)
	if not light_rid.is_valid():
		return
	var base_energy: float = float(light.get_meta("peraviz_base_light_energy", light.light_energy))
	RenderingServer.light_set_param(light_rid, RenderingServer.LIGHT_PARAM_ENERGY, base_energy * float(_visual_settings.get("spot_multiplier", 1.0)))
	RenderingServer.light_set_param(light_rid, RenderingServer.LIGHT_PARAM_VOLUMETRIC_FOG_ENERGY, float(_visual_settings.get("light_volumetric_fog_energy", 12.0)))

func _update_existing_beam_material_scalars(light: SpotLight3D) -> void:
	var base_intensity: float = float(light.get_meta("peraviz_beam_base_intensity", 0.0))
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else {}
	if beam_params.is_empty():
		return
	var beam_multiplier: float = float(_visual_settings.get("beam_multiplier", 20.0))
	beam_params["scaled_intensity"] = clamp(base_intensity * beam_multiplier, 0.0, BEAM_INTENSITY_MAX)
	beam_params["beam_quality"] = int(_visual_settings.get("beam_quality", 1))
	beam_params["intensity_max"] = BEAM_INTENSITY_MAX
	var beam_phase_start: int = Time.get_ticks_usec()
	_update_beam_for_light(light, beam_params)
	if _fixture_light_apply_service != null:
		_fixture_light_apply_service._track_phase("beam_update", beam_phase_start)

func _ensure_beam_runtime_for_light(light: SpotLight3D) -> void:
	if _active_beam_renderer == null or light == null or not is_instance_valid(light):
		return
	_active_beam_renderer.ensure_beam(light)

func _update_beam_for_light(light: SpotLight3D, beam_params: Dictionary) -> void:
	if _active_beam_renderer == null:
		return
	light.set_meta("peraviz_beam_last_params", beam_params)
	_active_beam_renderer.ensure_beam(light)
	_active_beam_renderer.update_beam(light, beam_params)

func _apply_emitter_light_dimmer_fast(light: SpotLight3D, photometric: Dictionary, normalized_dimmer: float, beam_color: Color, controls: Dictionary = {}) -> bool:
	if light == null or not is_instance_valid(light) or not light.has_meta("peraviz_beam_last_params"):
		return false
	var last_state: Dictionary = _get_or_create_emitter_last_state(light)
	_set_light_property_bool(light, "visible", normalized_dimmer > 0.0001, last_state)
	var render_ready_values: PackedFloat32Array = _get_render_ready_values(controls)
	var luminous_flux: float = max(float(photometric.get("luminous_flux", 10000.0)), 0.0)
	var base_light_energy: float = render_ready_values[0] if render_ready_values.size() >= 9 else luminous_flux * normalized_dimmer * EMITTER_LIGHT_ENERGY_SCALE
	_set_light_meta_float(light, "peraviz_base_light_energy", base_light_energy, last_state)
	_set_light_property_float(light, "light_energy", base_light_energy * float(_visual_settings.get("spot_multiplier", 1.0)), last_state)
	_set_light_meta_float(light, "peraviz_beam_base_intensity", clamp(normalized_dimmer, 0.0, 1.0), last_state)
	var scaled_intensity_override: float = render_ready_values[7] if render_ready_values.size() >= 9 else -1.0
	return _update_beam_intensity_for_light(light, normalized_dimmer, beam_color, scaled_intensity_override)

func _update_beam_intensity_for_light(light: SpotLight3D, normalized_dimmer: float, beam_color: Color, scaled_intensity_override: float = -1.0) -> bool:
	if _active_beam_renderer == null or not light.has_meta("peraviz_beam_last_params"):
		return false
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
	if beam_params.is_empty():
		return false
	var scaled_intensity: float = clamp(scaled_intensity_override, 0.0, BEAM_INTENSITY_MAX) if scaled_intensity_override >= 0.0 else clamp(normalized_dimmer * float(_visual_settings.get("beam_multiplier", 20.0)), 0.0, BEAM_INTENSITY_MAX)
	beam_params["normalized_dimmer"] = clamp(normalized_dimmer, 0.0, 1.0)
	beam_params["scaled_intensity"] = scaled_intensity
	beam_params["beam_intensity"] = scaled_intensity
	beam_params["beam_color"] = beam_color
	beam_params["intensity_max"] = BEAM_INTENSITY_MAX
	if _active_beam_renderer.update_beam_intensity(light, beam_params):
		light.set_meta("peraviz_beam_last_params", beam_params)
		return true
	return false

func _open_visual_settings_window() -> void:
	if visual_settings_window != null and visual_settings_window.has_method("popup_settings"):
		visual_settings_window.call("popup_settings")
	else:
		push_warning("VisualSettingsWindow is not ready for popup_settings().")

func _on_visual_settings_changed(settings: Dictionary) -> void:
	_apply_visual_settings(settings)

func _on_file_selected(path: String) -> void:
	var extension: String = path.get_extension().to_lower()
	if extension == "pvz":
		_open_project(path)
		return
	_load_mvr_scene(path, "mvr")

func _load_mvr_scene(path: String, loaded_file_type: String = "mvr", remember_loaded_file: bool = true) -> Dictionary:
	if _status_presenter != null:
		_status_presenter.set_scene_state_loading(path)
	_clear_scene()
	var import_result: Dictionary = _scene_import_service.import_scene(
		path,
		_loader,
		_node_factory,
		_fixture_binding_service,
		_asset_cache,
		proxies_root,
		_node_index,
		Callable(self, "_refresh_dmx_fixture_bindings"),
		Callable(self, "_populate_fixture_list"),
		Callable(self, "_sync_selection_state"),
		Callable(self, "_rebuild_debug_gizmos"),
		Callable(self, "_focus_loaded_scene"),
		Callable(self, "_update_debug_legend"),
		Callable(self, "_refresh_emitter_light_scalars"),
		Callable(self, "_extract_emitter_photometrics"),
		Callable(self, "_rebuild_loaded_bounds"),
		Callable(self, "_set_has_loaded_bounds"),
		_debug_coords_enabled,
		_debug_asset_cache_enabled,
		_scene_registry,
		_fixture_row_provider
	)
	if bool(import_result.get("ok", false)):
		_refresh_fixture_inspection_panel()
		_loaded_mvr_path = path
		_last_loaded_file_type = loaded_file_type
		if remember_loaded_file:
			_remember_loaded_file(path, loaded_file_type)
		if _status_presenter != null:
			_status_presenter.set_scene_state_loaded(int(import_result.get("node_count", 0)))
	else:
		if _status_presenter != null:
			var error_message: String = str(import_result.get("error", "unknown error"))
			_status_presenter.set_scene_state_load_error(error_message)
	return import_result


func _on_save_project_selected(path: String) -> void:
	if _loaded_mvr_path.is_empty() or not FileAccess.file_exists(_loaded_mvr_path):
		if _status_presenter != null:
			_status_presenter.show_toast("Load an MVR before saving a Peraviz project.")
		return
	var save_result: Dictionary = _project_archive.save_project(
		path,
		_loaded_mvr_path,
		_read_peraviz_version(),
		_visual_settings,
		_collect_dmx_project_settings(),
		_collect_app_state("pvz")
	)
	if bool(save_result.get("ok", false)):
		var saved_project_path: String = str(save_result.get("project_path", path))
		_remember_loaded_file(saved_project_path, "pvz")
		if _status_presenter != null:
			_status_presenter.show_toast("Saved Peraviz project: %s" % saved_project_path)
	else:
		if _status_presenter != null:
			_status_presenter.show_toast("Project save failed: %s" % str(save_result.get("error", "unknown error")))

func _open_project(path: String) -> void:
	if _status_presenter != null:
		_status_presenter.set_scene_state_loading(path)
	var project_result: Dictionary = _project_archive.open_project(path)
	if not bool(project_result.get("ok", false)):
		if _status_presenter != null:
			_status_presenter.set_scene_state_load_error(str(project_result.get("error", "unknown error")))
		return

	var import_result: Dictionary = _load_mvr_scene(str(project_result.get("scene_path", "")), "pvz", false)
	if not bool(import_result.get("ok", false)):
		return

	var visual_project_settings: Variant = project_result.get("visual_settings", {})
	var dmx_project_settings: Dictionary = {}
	var dmx_settings_value: Variant = project_result.get("dmx_settings", {})
	if dmx_settings_value is Dictionary:
		dmx_project_settings = dmx_settings_value as Dictionary
	_restore_visual_project_settings(visual_project_settings)
	_restore_dmx_project_settings(dmx_project_settings)
	_last_loaded_file_type = "pvz"
	_remember_loaded_file(path, "pvz")
	if _status_presenter != null:
		_status_presenter.show_toast("Opened Peraviz project: %s" % path.get_file())

func _collect_dmx_project_settings() -> Dictionary:
	var settings: Dictionary = _project_archive.get_default_dmx_settings()
	if _dmx_controller != null:
		settings["universe_offset"] = _dmx_controller.get_universe_offset()
		settings["dmx_enabled_when_saved"] = _dmx_controller.is_dmx_enabled()
	settings["auto_start_dmx"] = _user_preferences != null and _user_preferences.auto_start_dmx
	return settings

func _restore_dmx_project_settings(settings: Dictionary) -> void:
	if _dmx_controller == null:
		if _status_presenter != null:
			_status_presenter.show_toast("DMX settings could not be restored because DMX controls are unavailable.")
		return
	if settings.has("universe_offset"):
		_dmx_controller.set_universe_offset(int(settings.get("universe_offset", -1)))
	var should_auto_start: bool = bool(settings.get("auto_start_dmx", false)) and bool(settings.get("dmx_enabled_when_saved", false))
	if should_auto_start and not _dmx_controller.start_dmx():
		if _status_presenter != null:
			_status_presenter.show_toast("Project opened, but DMX could not be auto-started.")

func _restore_visual_project_settings(settings: Variant) -> void:
	if settings is not Dictionary:
		return
	var visual_settings: Dictionary = settings as Dictionary
	if visual_settings.is_empty():
		return
	_apply_visual_settings(visual_settings)
	if visual_settings_window != null and visual_settings_window.has_method("configure"):
		visual_settings_window.call("configure", _visual_settings)

func _collect_app_state(last_loaded_file_type: String) -> Dictionary:
	return {
		"last_loaded_file_type": last_loaded_file_type,
	}

func _remember_loaded_file(path: String, file_type: String) -> void:
	if _user_preferences == null:
		return
	var normalized_file_type: String = _resolve_supported_file_type(path, file_type)
	if normalized_file_type.is_empty():
		return
	_user_preferences.last_file_path = path
	_user_preferences.last_file_type = normalized_file_type
	_user_preferences.save_to_disk()
	_sync_session_preference_toggles()

func _auto_load_last_file_from_preferences() -> void:
	if _user_preferences == null or not _user_preferences.auto_load_last_file:
		return
	var last_path: String = _user_preferences.last_file_path
	if last_path.is_empty():
		return
	if not FileAccess.file_exists(last_path):
		if _status_presenter != null:
			_status_presenter.show_toast("Last project file no longer exists: %s" % last_path)
		return
	var last_file_type: String = _resolve_supported_file_type(last_path, _user_preferences.last_file_type)
	if last_file_type.is_empty():
		if _status_presenter != null:
			var stored_file_type: String = _user_preferences.last_file_type
			if stored_file_type.is_empty():
				stored_file_type = "<empty>"
			_status_presenter.show_toast("Last project file type is unsupported: %s" % stored_file_type)
		return
	match last_file_type:
		"pvz":
			_open_project(last_path)
		"mvr":
			_load_mvr_scene(last_path, "mvr")

func _resolve_supported_file_type(path: String, fallback_file_type: String) -> String:
	var extension_file_type: String = path.get_extension().to_lower()
	if SUPPORTED_LAST_FILE_TYPES.has(extension_file_type):
		return extension_file_type
	var normalized_file_type: String = fallback_file_type.to_lower()
	return normalized_file_type if SUPPORTED_LAST_FILE_TYPES.has(normalized_file_type) else ""

func _sync_session_preference_toggles() -> void:
	if _user_preferences == null:
		return
	if auto_load_last_project_toggle != null:
		auto_load_last_project_toggle.set_pressed_no_signal(_user_preferences.auto_load_last_file)
	if auto_start_dmx_project_toggle != null:
		auto_start_dmx_project_toggle.set_pressed_no_signal(_user_preferences.auto_start_dmx)

func _read_peraviz_version() -> String:
	var version_file := FileAccess.open("res://VERSION", FileAccess.READ)
	if version_file == null:
		return "unknown"
	var version: String = version_file.get_as_text().strip_edges()
	version_file.close()
	return version if not version.is_empty() else "unknown"

func _load_user_preferences() -> void:
	_user_preferences = UserPreferencesScript.new()
	_user_preferences.load_from_disk()
	UiVisibilityPolicyScript.set_advanced_controls_enabled(_user_preferences.advanced_mode)
	if show_advanced_controls_toggle != null:
		show_advanced_controls_toggle.button_pressed = _user_preferences.advanced_mode
	if app_shell != null:
		app_shell.set_side_panel_open(_user_preferences.sidebar_open)
	_sync_session_preference_toggles()

func _apply_visual_settings_preferences_to_window() -> void:
	if _user_preferences == null or visual_settings_window == null:
		return
	if visual_settings_window.has_method("set_advanced_mode_enabled"):
		visual_settings_window.call("set_advanced_mode_enabled", _user_preferences.advanced_mode)
	if visual_settings_window.has_method("set_active_tab_index"):
		visual_settings_window.call("set_active_tab_index", _user_preferences.last_settings_tab)

func _save_user_preferences() -> void:
	if _user_preferences == null:
		return
	if app_shell != null:
		_user_preferences.sidebar_open = app_shell.is_side_panel_open()
	_user_preferences.advanced_mode = UiVisibilityPolicyScript.is_advanced_controls_enabled()
	if visual_settings_window != null and visual_settings_window.has_method("get_active_tab_index"):
		_user_preferences.last_settings_tab = int(visual_settings_window.call("get_active_tab_index"))
	_user_preferences.set_module_visible(UiVisibilityPolicyScript.MODULE_USER, user_module != null and user_module.visible)
	_user_preferences.set_module_visible(UiVisibilityPolicyScript.MODULE_ADVANCED, advanced_module != null and advanced_module.visible)
	_user_preferences.set_module_visible(UiVisibilityPolicyScript.MODULE_DEBUG, debug_module != null and debug_module.visible)
	_user_preferences.save_to_disk()


func _setup_mvr_xchange_panel() -> void:
	if _mvr_xchange_panel != null and is_instance_valid(_mvr_xchange_panel):
		return
	if user_module == null:
		return
	_mvr_xchange_controller = MvrXchangeControllerScript.new()
	_mvr_xchange_controller.configure(self)
	_mvr_xchange_controller.stations_changed.connect(_on_mvr_xchange_stations_changed)
	_mvr_xchange_controller.status_changed.connect(_on_mvr_xchange_status_changed)
	_mvr_xchange_controller.state_changed.connect(_on_mvr_xchange_state_changed)
	_mvr_xchange_controller.mvr_file_received.connect(_on_mvr_xchange_file_received)
	_mvr_xchange_panel = MvrXchangePanelScript.new()
	_mvr_xchange_panel.name = "MvrXchangePanel"
	user_module.add_child(_mvr_xchange_panel)
	_mvr_xchange_panel.set_preferences(_user_preferences.mvr_xchange_group if _user_preferences != null else "Default", _user_preferences.mvr_xchange_bind_ip if _user_preferences != null else "")
	_mvr_xchange_panel.set_available(_mvr_xchange_controller.is_available())
	_mvr_xchange_panel.start_requested.connect(_on_mvr_xchange_start_requested)
	_mvr_xchange_panel.stop_requested.connect(_on_mvr_xchange_stop_requested)
	_mvr_xchange_panel.preferences_changed.connect(_on_mvr_xchange_preferences_changed)
	_mvr_xchange_panel.station_selected.connect(_on_mvr_xchange_station_selected)
	_mvr_xchange_panel.update_requested.connect(_on_mvr_xchange_update_requested)
	_on_mvr_xchange_status_changed(false, 0, "OFF")

func _on_mvr_xchange_start_requested(group: String, bind_ip: String) -> void:
	_on_mvr_xchange_preferences_changed(group, bind_ip)
	if _mvr_xchange_controller != null:
		_mvr_xchange_controller.start_discovery(group, bind_ip)

func _on_mvr_xchange_stop_requested() -> void:
	if _mvr_xchange_controller != null:
		_mvr_xchange_controller.stop_discovery()

func _on_mvr_xchange_preferences_changed(group: String, bind_ip: String) -> void:
	if _user_preferences == null:
		return
	_user_preferences.mvr_xchange_group = group if not group.is_empty() else "Default"
	_user_preferences.mvr_xchange_bind_ip = bind_ip
	_user_preferences.save_to_disk()

func _on_mvr_xchange_stations_changed(stations: Array) -> void:
	if _mvr_xchange_panel != null:
		_mvr_xchange_panel.set_stations(stations)

func _on_mvr_xchange_status_changed(is_running: bool, station_count: int, message: String) -> void:
	if _mvr_xchange_panel != null:
		_mvr_xchange_panel.set_status(is_running, station_count, message)
	if _status_presenter != null:
		_status_presenter.set_mvr_xchange_badge(is_running, station_count)

func _on_mvr_xchange_state_changed(state: String, metadata: Dictionary) -> void:
	if _mvr_xchange_panel != null:
		_mvr_xchange_panel.set_state(state, metadata)
	if _status_presenter != null:
		_status_presenter.set_mvr_xchange_badge(_mvr_xchange_controller != null and _mvr_xchange_controller.is_running(), _mvr_xchange_controller.get_stations().size() if _mvr_xchange_controller != null else 0, state)

func _on_mvr_xchange_station_selected(service_name: String) -> void:
	if _mvr_xchange_controller != null:
		_mvr_xchange_controller.select_station(service_name)

func _on_mvr_xchange_update_requested() -> void:
	if _mvr_xchange_controller != null:
		_mvr_xchange_controller.request_update()

func _on_mvr_xchange_file_received(path: String, _metadata: Dictionary) -> void:
	if path.is_empty():
		return
	_load_mvr_scene(path, "mvr", false)
	if _mvr_xchange_controller != null:
		_mvr_xchange_controller.mark_loaded(path)
	if _status_presenter != null:
		_status_presenter.show_toast("Loaded MVR from MVR-xchange")

func _on_manual_fixture_toggle(enabled: bool) -> void:
	ProjectSettings.set_setting("peraviz_manual_fixture_test", enabled)
	_refresh_fixture_debug_panel()

func _on_show_advanced_controls_toggled(enabled: bool) -> void:
	UiVisibilityPolicyScript.set_advanced_controls_enabled(enabled)
	if visual_settings_window != null and visual_settings_window.has_method("set_advanced_mode_enabled"):
		visual_settings_window.call("set_advanced_mode_enabled", enabled)
	_refresh_ui_module_visibility()

func _on_auto_load_last_project_toggled(enabled: bool) -> void:
	if _user_preferences == null:
		return
	_user_preferences.auto_load_last_file = enabled
	_user_preferences.save_to_disk()

func _on_auto_start_dmx_project_toggled(enabled: bool) -> void:
	if _user_preferences == null:
		return
	_user_preferences.auto_start_dmx = enabled
	_user_preferences.save_to_disk()

func _refresh_ui_module_visibility() -> void:
	var user_visible: bool = UiVisibilityPolicyScript.is_module_visible(UiVisibilityPolicyScript.MODULE_USER)
	var advanced_visible: bool = UiVisibilityPolicyScript.is_module_visible(UiVisibilityPolicyScript.MODULE_ADVANCED)
	var debug_visible: bool = UiVisibilityPolicyScript.is_module_visible(UiVisibilityPolicyScript.MODULE_DEBUG)
	if _user_preferences != null:
		user_visible = user_visible and _user_preferences.get_module_visible(UiVisibilityPolicyScript.MODULE_USER, true)
		advanced_visible = advanced_visible and _user_preferences.get_module_visible(UiVisibilityPolicyScript.MODULE_ADVANCED, false)
		debug_visible = debug_visible and _user_preferences.get_module_visible(UiVisibilityPolicyScript.MODULE_DEBUG, false)
	if user_module != null:
		user_module.visible = user_visible
	if advanced_module != null:
		advanced_module.visible = advanced_visible
	if debug_module != null:
		debug_module.visible = debug_visible
	if show_advanced_controls_toggle != null:
		show_advanced_controls_toggle.button_pressed = UiVisibilityPolicyScript.is_advanced_controls_enabled()

func _unhandled_input(event: InputEvent) -> void:
	_sync_selection_state("input")
	_sync_selected_fixture_badge()

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_focus_loaded_scene()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == DEBUG_TOGGLE_KEY:
		_debug_coords_enabled = not _debug_coords_enabled
		ProjectSettings.set_setting("peraviz_debug_coords", _debug_coords_enabled)
		print("[PeravizCoordDebug] event=toggle coords_debug=", _debug_coords_enabled)
		_rebuild_debug_gizmos()
		_update_debug_legend()
		get_viewport().set_input_as_handled()
		return

	if _is_manual_fixture_test_enabled() and event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_fixture_debug_controller.try_select_fixture_from_mouse(mouse_event.position)
			_sync_selected_fixture_badge()
			get_viewport().set_input_as_handled()


func _ensure_debug_gizmo_root() -> void:
	_debug_overlay_service.ensure_debug_gizmo_root(self)

func _clear_debug_gizmos() -> void:
	_debug_overlay_service.clear_debug_gizmos(self)

func _rebuild_debug_gizmos() -> void:
	_debug_overlay_service.rebuild_debug_gizmos(self, _debug_coords_enabled, proxies_root, _node_index)


func _is_basis_valid(candidate_basis: Basis) -> bool:
	var determinant: float = candidate_basis.determinant()
	if is_zero_approx(determinant):
		return false
	return is_finite(determinant)

func _safe_basis_from_data(data: Dictionary) -> Basis:
	var basis_x: Vector3 = data.get("basis_x", Vector3.RIGHT)
	var basis_y: Vector3 = data.get("basis_y", Vector3.UP)
	var basis_z: Vector3 = data.get("basis_z", Vector3.BACK)
	var candidate_basis := Basis(basis_x, basis_y, basis_z)
	if _is_basis_valid(candidate_basis):
		return candidate_basis

	print("[PeravizCoordDebug] event=invalid_basis_fallback basis_x=", basis_x, " basis_y=", basis_y, " basis_z=", basis_z)
	return Basis.IDENTITY

func _safe_position(value: Vector3, context: String) -> Vector3:
	if is_finite(value.x) and is_finite(value.y) and is_finite(value.z):
		return value
	print("[PeravizCoordDebug] event=invalid_position_fallback context=", context, " pos=", value)
	return Vector3.ZERO

func _safe_scale_from_data(data: Dictionary, context: String) -> Vector3:
	var raw_scale: Vector3 = data.get("scale", Vector3.ONE)
	if not is_finite(raw_scale.x) or not is_finite(raw_scale.y) or not is_finite(raw_scale.z):
		print("[PeravizCoordDebug] event=invalid_scale_fallback context=", context, " scale=", raw_scale)
		return Vector3.ONE

	var min_axis: float = 0.0001
	var sx: float = raw_scale.x
	var sy: float = raw_scale.y
	var sz: float = raw_scale.z
	if is_zero_approx(sx):
		sx = min_axis
	if is_zero_approx(sy):
		sy = min_axis
	if is_zero_approx(sz):
		sz = min_axis

	if not is_equal_approx(sx, raw_scale.x) or not is_equal_approx(sy, raw_scale.y) or not is_equal_approx(sz, raw_scale.z):
		print("[PeravizCoordDebug] event=zero_scale_sanitized context=", context, " raw_scale=", raw_scale, " sanitized_scale=", Vector3(sx, sy, sz))
	return Vector3(sx, sy, sz)

func _safe_target_global_position(target: Node3D) -> Vector3:
	if target == null:
		return Vector3.ZERO
	var origin: Vector3 = target.global_position
	if not is_finite(origin.x) or not is_finite(origin.y) or not is_finite(origin.z):
		print("[PeravizCoordDebug] event=invalid_target_origin_fallback node=", target.name, " origin=", origin)
		return Vector3.ZERO
	return origin

func _add_debug_gizmo_for_target(target: Node3D, kind: String, origin_color: Color, length: float) -> void:
	if target == null:
		return
	var holder := Node3D.new()
	holder.name = "Gizmo_%s" % kind
	_debug_gizmos_root.add_child(holder)
	holder.global_transform = Transform3D(target.global_basis, _safe_target_global_position(target))
	holder.add_child(_create_axes_gizmo_node(origin_color, length))
	if kind == "emitter":
		holder.add_child(_create_emitter_direction_gizmo(length))

func _create_emitter_direction_gizmo(length: float) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	var beam_material := ORMMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color = Color(1.0, 0.55, 0.15)
	beam_material.emission_enabled = true
	beam_material.emission = Color(1.0, 0.55, 0.15)
	beam_material.emission_energy_multiplier = 2.0
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, beam_material)
	immediate.surface_add_vertex(Vector3.ZERO)
	immediate.surface_add_vertex(Vector3.DOWN * (length * 1.8))
	immediate.surface_end()

	var beam := MeshInstance3D.new()
	beam.mesh = immediate
	beam.material_override = beam_material
	return beam

func _create_axes_gizmo_node(origin_color: Color, length: float) -> Node3D:
	var immediate := ImmediateMesh.new()
	var line_material := ORMMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	immediate.surface_set_color(Color(1, 0, 0))
	immediate.surface_add_vertex(Vector3.ZERO)
	immediate.surface_add_vertex(Vector3.RIGHT * length)
	immediate.surface_set_color(Color(0, 1, 0))
	immediate.surface_add_vertex(Vector3.ZERO)
	immediate.surface_add_vertex(Vector3.UP * length)
	immediate.surface_set_color(Color(0, 0.4, 1))
	immediate.surface_add_vertex(Vector3.ZERO)
	immediate.surface_add_vertex(Vector3.BACK * length)
	immediate.surface_end()

	var axes_instance := MeshInstance3D.new()
	axes_instance.mesh = immediate
	axes_instance.material_override = line_material

	var marker := SphereMesh.new()
	marker.radius = max(length * 0.08, 0.01)
	marker.height = marker.radius * 2.0
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = origin_color
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var marker_instance := MeshInstance3D.new()
	marker_instance.mesh = marker
	marker_instance.material_override = marker_material

	var container := Node3D.new()
	container.add_child(axes_instance)
	container.add_child(marker_instance)
	return container

func _update_debug_legend() -> void:
	_debug_overlay_service.print_debug_legend(_debug_coords_enabled)

func _build_node_tree(nodes: Array) -> void:
	_node_factory.build_node_tree(nodes, proxies_root, _node_index, Callable(self, "_rebuild_loaded_bounds"), _loader, _asset_cache)

func _apply_mesh_orientation_corrections(node: Node3D, inherited_flip: bool) -> void:
	if node == null:
		return

	var node_flip: bool = node.transform.basis.determinant() < 0.0
	var global_flip: bool = inherited_flip != node_flip
	if node is MeshInstance3D:
		_rebuild_mesh_instance_for_orientation(node as MeshInstance3D, global_flip)

	for child in node.get_children():
		if child is Node3D:
			_apply_mesh_orientation_corrections(child as Node3D, global_flip)

func _rebuild_mesh_instance_for_orientation(mesh_instance: MeshInstance3D, flip_orientation: bool) -> void:
	if mesh_instance == null:
		return

	if not mesh_instance.has_meta("peraviz_asset_path"):
		return

	var asset_path: String = str(mesh_instance.get_meta("peraviz_asset_path", ""))
	if asset_path.is_empty():
		return

	var mesh_cache_key: String = asset_path
	if flip_orientation:
		mesh_cache_key = "%s#flipped" % asset_path

	var cached_mesh: Mesh = _asset_cache.get_mesh(mesh_cache_key)
	if cached_mesh == null:
		var mesh_data: Dictionary = _loader.load_3ds_mesh_data(asset_path)
		if not bool(mesh_data.get("ok", false)):
			return
		var rebuilt_mesh: ArrayMesh = _build_3ds_mesh(mesh_data, flip_orientation)
		if rebuilt_mesh == null:
			return
		_asset_cache.store_mesh(mesh_cache_key, rebuilt_mesh)
		cached_mesh = rebuilt_mesh

	mesh_instance.mesh = cached_mesh
	mesh_instance.set_meta("peraviz_flip_orientation_applied", flip_orientation)

func _remove_redundant_dummy_meshes(root: Node) -> void:
	if root == null:
		return

	for child in root.get_children():
		_remove_redundant_dummy_meshes(child)

	if root is not Node3D:
		return

	var root_node: Node3D = root
	var placeholders_to_remove: Array[Node] = []
	for child in root_node.get_children():
		if child is MeshInstance3D and bool(child.get_meta("peraviz_dummy_placeholder", false)):
			placeholders_to_remove.push_back(child)

	if placeholders_to_remove.is_empty():
		return

	var has_real_visual: bool = _node_has_real_visual_descendants(root_node, placeholders_to_remove)
	if not has_real_visual:
		return

	for placeholder in placeholders_to_remove:
		placeholder.queue_free()

func _node_has_real_visual_descendants(root: Node, ignored_nodes: Array[Node]) -> bool:
	if root is MeshInstance3D:
		if not bool(root.get_meta("peraviz_dummy_placeholder", false)):
			return true
	elif root is MultiMeshInstance3D:
		return true

	for child in root.get_children():
		if ignored_nodes.has(child):
			continue
		if _node_has_real_visual_descendants(child, ignored_nodes):
			return true

	return false

func _set_has_loaded_bounds(value: bool) -> void:
	_has_loaded_bounds = value

func _rebuild_loaded_bounds() -> void:
	_has_loaded_bounds = false
	for child in proxies_root.get_children():
		if child is Node3D:
			_expand_loaded_bounds_from_node(child)

func _create_scene_node(data: Dictionary) -> Node3D:
	return _node_factory.create_scene_node(data, _loader, _asset_cache)

func _reparent_fixture_visual_children(geometry_node: Node3D, model_root: Node3D) -> void:
	if geometry_node == null or model_root == null:
		return

	if model_root is MeshInstance3D:
		return

	var model_root_local: Transform3D = model_root.transform
	var moved_any_child: bool = false
	for child in model_root.get_children():
		if child is not Node3D:
			continue

		var child_node: Node3D = child
		var child_local_before: Transform3D = child_node.transform
		var child_local_after: Transform3D = model_root_local * child_local_before
		model_root.remove_child(child_node)
		child_node.owner = null
		geometry_node.add_child(child_node)
		child_node.transform = child_local_after
		moved_any_child = true

	if moved_any_child:
		model_root.queue_free()

func _build_visual_node(data: Dictionary, item_type: String, item_class: String, is_fixture: bool, visual_scale_hint: float, flip_orientation: bool = false) -> Node3D:
	var asset_path: String = str(data.get("asset_path", ""))
	var asset_kind: String = _extract_asset_kind(data, asset_path)
	if not asset_path.is_empty():
		var loaded: Variant = _load_3d_asset(asset_path, asset_kind, flip_orientation)
		if loaded is Node3D:
			var loaded_node: Node3D = loaded
			_force_double_sided_materials(loaded_node)
			return loaded_node
		print("[Peraviz] Asset fallback for missing/invalid model: ", asset_path, " type=", item_type, " class=", item_class, " asset_kind=", asset_kind)

	if item_type == "fixture" or item_type == "fixture_geometry":
		if asset_kind == "primitive":
			var primitive_mesh: Node3D = _create_gdtf_primitive_mesh(data)
			_force_double_sided_materials(primitive_mesh)
			return primitive_mesh
		return null

	var dummy_mesh: Node3D = _create_dummy_mesh(is_fixture, visual_scale_hint)
	_force_double_sided_materials(dummy_mesh)
	return dummy_mesh

func _force_double_sided_materials(root: Node) -> void:
	if root == null:
		return

	if root is MeshInstance3D:
		_apply_double_sided_to_mesh_instance(root as MeshInstance3D)
	elif root is MultiMeshInstance3D:
		_apply_double_sided_to_multimesh_instance(root as MultiMeshInstance3D)

	for child in root.get_children():
		_force_double_sided_materials(child)

func _apply_double_sided_to_mesh_instance(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null:
		return

	if mesh_instance.material_override != null:
		mesh_instance.material_override = _duplicate_as_double_sided(mesh_instance.material_override)

	_apply_double_sided_to_mesh_surfaces(mesh_instance, mesh_instance.mesh)

func _apply_double_sided_to_multimesh_instance(multimesh_instance: MultiMeshInstance3D) -> void:
	if multimesh_instance == null:
		return

	if multimesh_instance.material_override != null:
		multimesh_instance.material_override = _duplicate_as_double_sided(multimesh_instance.material_override)

	var mesh: Mesh = multimesh_instance.multimesh.mesh if multimesh_instance.multimesh != null else null
	_apply_double_sided_to_mesh_surfaces(multimesh_instance, mesh)

func _apply_double_sided_to_mesh_surfaces(geometry_instance: GeometryInstance3D, mesh: Mesh) -> void:
	if geometry_instance == null or mesh == null:
		return

	var surface_count: int = mesh.get_surface_count()
	for surface_index in range(surface_count):
		var override_material: Material = geometry_instance.get_surface_override_material(surface_index)
		if override_material != null:
			geometry_instance.set_surface_override_material(surface_index, _duplicate_as_double_sided(override_material))
			continue

		var surface_material: Material = mesh.surface_get_material(surface_index)
		if surface_material != null:
			geometry_instance.set_surface_override_material(surface_index, _duplicate_as_double_sided(surface_material))
		else:
			geometry_instance.set_surface_override_material(surface_index, _create_default_double_sided_material())

func _duplicate_as_double_sided(material: Material) -> Material:
	if material is not BaseMaterial3D:
		return material

	var base_material: BaseMaterial3D = material as BaseMaterial3D
	if base_material.cull_mode == BaseMaterial3D.CULL_DISABLED:
		return material

	var duplicated_material: BaseMaterial3D = base_material.duplicate(true)
	duplicated_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return duplicated_material

func _create_default_double_sided_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _extract_visual_scale_hint(data: Dictionary) -> float:
	if bool(data.get("has_basis", false)):
		var basis_x: Vector3 = data.get("basis_x", Vector3.RIGHT)
		var basis_y: Vector3 = data.get("basis_y", Vector3.UP)
		var basis_z: Vector3 = data.get("basis_z", Vector3.BACK)
		var average_basis_length: float = (basis_x.length() + basis_y.length() + basis_z.length()) / 3.0
		return max(average_basis_length, 0.0001)

	var node_scale: Vector3 = data.get("scale", Vector3.ONE)
	var average_scale: float = (abs(node_scale.x) + abs(node_scale.y) + abs(node_scale.z)) / 3.0
	if not is_finite(average_scale):
		return 1.0
	return max(average_scale, 0.0001)

func _load_3d_asset(asset_path: String, asset_kind_hint: String = "", flip_orientation: bool = false) -> Variant:
	var resolved_asset_kind: String = asset_kind_hint.to_lower()
	if resolved_asset_kind.is_empty() or resolved_asset_kind == "none":
		resolved_asset_kind = _infer_asset_kind_from_extension(asset_path)

	var extension: String = asset_path.get_extension().to_lower()
	if resolved_asset_kind == "mesh" or extension == "3ds":
		var mesh_cache_key: String = asset_path
		if flip_orientation:
			mesh_cache_key = "%s#flipped" % asset_path
		var cached_mesh: Mesh = _asset_cache.get_mesh(mesh_cache_key)
		if cached_mesh != null:
			var cached_mesh_instance := MeshInstance3D.new()
			cached_mesh_instance.mesh = cached_mesh
			cached_mesh_instance.set_meta("peraviz_asset_path", asset_path)
			cached_mesh_instance.set_meta("peraviz_asset_kind", "mesh")
			cached_mesh_instance.set_meta("peraviz_flip_orientation_applied", flip_orientation)
			return cached_mesh_instance

		var mesh_data: Dictionary = _loader.load_3ds_mesh_data(asset_path)
		if not bool(mesh_data.get("ok", false)):
			_asset_cache.mark_failed(asset_path)
			return null
		var mesh: ArrayMesh = _build_3ds_mesh(mesh_data, flip_orientation)
		if mesh == null:
			_asset_cache.mark_failed(asset_path)
			return null
		_asset_cache.store_mesh(mesh_cache_key, mesh)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.set_meta("peraviz_asset_path", asset_path)
		mesh_instance.set_meta("peraviz_asset_kind", "mesh")
		mesh_instance.set_meta("peraviz_flip_orientation_applied", flip_orientation)
		return mesh_instance

	if resolved_asset_kind == "scene" or extension == "glb" or extension == "gltf":
		var cached_scene_instance: Node3D = _asset_cache.instantiate_scene(asset_path)
		if cached_scene_instance != null:
			return cached_scene_instance

		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err: int = gltf.append_from_file(asset_path, state)
		if err != OK:
			_asset_cache.mark_failed(asset_path)
			return null
		var generated: Node = gltf.generate_scene(state)
		if generated is Node3D:
			var packed_scene := PackedScene.new()
			if packed_scene.pack(generated) == OK:
				_asset_cache.store_scene(asset_path, packed_scene)
				generated.free()
				return _asset_cache.instantiate_scene(asset_path)
		if generated != null:
			generated.free()
		_asset_cache.mark_failed(asset_path)
		return null

	var scene_instance: Node3D = _asset_cache.instantiate_scene(asset_path)
	if scene_instance != null:
		return scene_instance

	var resource: Resource = load(asset_path)
	if resource is PackedScene:
		_asset_cache.store_scene(asset_path, resource)
		return _asset_cache.instantiate_scene(asset_path)

	_asset_cache.mark_failed(asset_path)
	return null


func _extract_node_class(data: Dictionary, item_type: String) -> String:
	var node_class: String = str(data.get("class", ""))
	if node_class.is_empty():
		node_class = item_type
	return node_class

func _extract_asset_kind(data: Dictionary, asset_path: String) -> String:
	var kind: String = str(data.get("asset_kind", "")).to_lower()
	if kind.is_empty() or kind == "none":
		kind = _infer_asset_kind_from_extension(asset_path)
	return kind

func _infer_asset_kind_from_extension(asset_path: String) -> String:
	var extension: String = asset_path.get_extension().to_lower()
	if extension == "3ds":
		return "mesh"
	if extension == "glb" or extension == "gltf" or extension == "obj" or extension == "dae" or extension == "fbx" or extension == "stl":
		return "scene"
	return "none"


func _build_3ds_mesh(mesh_data: Dictionary, flip_orientation: bool = false) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var texcoords: PackedVector2Array = mesh_data.get("texcoords", PackedVector2Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var texture_path: String = str(mesh_data.get("texture_path", ""))
	var has_material_base_color: bool = bool(mesh_data.get("has_material_base_color", false))
	var material_base_color_vec: Vector3 = mesh_data.get("material_base_color", Vector3.ONE)
	var material_base_color: Color = Color(material_base_color_vec.x, material_base_color_vec.y, material_base_color_vec.z, 1.0)
	if vertices.is_empty() or indices.is_empty():
		return null

	if flip_orientation:
		if (indices.size() % 3) != 0:
			push_warning("[Peraviz] 3DS mesh index count is not divisible by 3; skipping orientation flip.")
		else:
			for i in range(0, indices.size(), 3):
				var tmp: int = indices[i + 1]
				indices[i + 1] = indices[i + 2]
				indices[i + 2] = tmp

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if texcoords.size() == vertices.size():
		arrays[Mesh.ARRAY_TEX_UV] = texcoords
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if not texture_path.is_empty() and texcoords.size() == vertices.size():
		var image := Image.new()
		var image_error: Error = image.load(texture_path)
		if image_error == OK:
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			var texture: ImageTexture = ImageTexture.create_from_image(image)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			material.albedo_texture = texture
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			array_mesh.surface_set_material(0, material)
		else:
			push_warning("[Peraviz] Failed to load 3DS texture image: %s (error=%d)" % [texture_path, image_error])
	elif has_material_base_color:
		var base_color_material := StandardMaterial3D.new()
		base_color_material.albedo_color = material_base_color
		base_color_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		array_mesh.surface_set_material(0, base_color_material)
	else:
		var textured_fallback_material := StandardMaterial3D.new()
		textured_fallback_material.albedo_color = Color(0.2, 0.2, 0.2, 1.0)
		textured_fallback_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		array_mesh.surface_set_material(0, textured_fallback_material)

	return array_mesh


func _create_dummy_mesh(is_fixture: bool, visual_scale_hint: float) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.set_meta("peraviz_dummy_placeholder", true)
	var world_target_size: float = 0.35
	var normalized_scale: float = max(visual_scale_hint, 0.0001)
	var local_size_multiplier: float = world_target_size / normalized_scale
	if is_fixture:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.15 * local_size_multiplier
		cone.height = 0.4 * local_size_multiplier
		mesh_instance.mesh = cone
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (0.3 * local_size_multiplier)
		mesh_instance.mesh = box

	var material_key: String = "builtin://material/dummy_fixture" if is_fixture else "builtin://material/dummy_object"
	var material: Material = _asset_cache.get_material(material_key, true)
	if material == null:
		var base_material := StandardMaterial3D.new()
		base_material.albedo_color = Color(1.0, 0.5, 0.1) if is_fixture else Color(0.2, 0.8, 1.0)
		_asset_cache.store_material(material_key, base_material)
		material = _asset_cache.get_material(material_key, true)
	mesh_instance.material_override = material
	return mesh_instance

func _create_gdtf_primitive_mesh(data: Dictionary) -> Node3D:
	var primitive_type: String = str(data.get("primitive_type", "")).to_lower()
	var primitive_shape: String = _classify_gdtf_primitive_shape(primitive_type)
	var source_size_x: float = max(float(data.get("primitive_size_x", 0.1)), 0.001)
	var source_size_y: float = max(float(data.get("primitive_size_y", 0.1)), 0.001)
	var source_size_z: float = max(float(data.get("primitive_size_z", 0.1)), 0.001)
	# GDTF dimensions are authored in fixture source axes (X,Y,Z).
	# Peraviz maps source vectors to Godot as (X, Z, -Y), so primitive dimensions
	# must be remapped before creating Godot-native meshes.
	var sx: float = source_size_x
	var sy: float = source_size_z
	var sz: float = source_size_y
	var primitive_scale: Vector3 = Vector3(sx, sy, sz)
	var mesh_instance := MeshInstance3D.new()
	if primitive_shape == "sphere":
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		mesh_instance.mesh = sphere
	elif primitive_shape == "cylinder":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1.0
		mesh_instance.mesh = cylinder
	elif primitive_shape == "cone":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.5
		cone.height = 1.0
		mesh_instance.mesh = cone
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mesh_instance.mesh = box
	mesh_instance.scale = primitive_scale

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.2, 0.22, 1.0)
	material.roughness = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	return mesh_instance

func _classify_gdtf_primitive_shape(primitive_type: String) -> String:
	var normalized: String = primitive_type.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "undefined":
		return "box"

	if normalized.contains("cone"):
		return "cone"
	if normalized.contains("cylinder"):
		return "cylinder"
	if normalized.contains("sphere"):
		return "sphere"

	if normalized in ["yoke", "scanner", "scanner1_1", "pigtail"]:
		return "cylinder"
	if normalized in ["head"]:
		return "sphere"
	if normalized in ["base", "base1_1", "conventional", "conventional1_1", "cube"]:
		return "box"

	return "box"

func _clear_scene() -> void:
	_clear_fixture_inspection_panel()
	_clear_fixture_node_cache()
	_fixture_row_provider.clear()
	_scene_import_service.clear_scene(
		_scene_registry,
		proxies_root,
		_node_index,
		_asset_cache,
		_fixture_emissive_cache,
		_fixture_emitter_light_cache,
		_fixture_emitter_photometrics,
		_fixture_gobo_projector,
		Callable(self, "_clear_selected_fixture"),
		Callable(self, "_clear_debug_gizmos"),
		Callable(self, "_set_has_loaded_bounds")
	)

func _register_fixture_registry(nodes: Array) -> void:
	_fixture_binding_service.register_fixture_registry(nodes, _node_index, _scene_registry, Callable(self, "_extract_emitter_photometrics"))

func _read_manual_fixture_test_setting() -> bool:
	var setting_enabled: bool = bool(ProjectSettings.get_setting("peraviz_manual_fixture_test", false))
	if setting_enabled:
		return true
	return OS.get_cmdline_args().has(MANUAL_TEST_FLAG)

func _populate_fixture_list() -> void:
	_fixture_debug_controller.populate_fixture_list()

func _resolve_fixture_uuid_from_node(node: Node) -> String:
	return _fixture_binding_service.resolve_fixture_uuid_from_node(node)

func _attach_fixture_pick_colliders(fixture_uuid: String, fixture_node: Node3D) -> void:
	_fixture_binding_service.attach_fixture_pick_colliders(fixture_uuid, fixture_node)

func _attach_fixture_pick_colliders_recursive(fixture_uuid: String, node: Node) -> void:
	if node is MeshInstance3D:
		_attach_pick_collider_to_mesh(node as MeshInstance3D, fixture_uuid)
	if node is Node:
		node.set_meta("peraviz_fixture_uuid", fixture_uuid)
	for child in node.get_children():
		_attach_fixture_pick_colliders_recursive(fixture_uuid, child)

func _attach_pick_collider_to_mesh(mesh_instance: MeshInstance3D, fixture_uuid: String) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var mesh_bounds: AABB = mesh_instance.get_aabb()
	if mesh_bounds.size == Vector3.ZERO:
		return

	var static_body := StaticBody3D.new()
	static_body.name = "FixturePickBody"
	static_body.set_meta("peraviz_fixture_uuid", fixture_uuid)
	mesh_instance.add_child(static_body)

	var shape := BoxShape3D.new()
	shape.size = mesh_bounds.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = mesh_bounds.get_center()
	static_body.add_child(collision)

func _clear_selected_fixture(reason: String) -> void:
	_fixture_debug_controller.clear_selected_fixture(reason)
	_sync_selected_fixture_badge()

func _sync_selection_state(reason: String) -> void:
	_fixture_debug_controller.sync_selection_state(reason)
	_sync_selected_fixture_badge()

func _refresh_fixture_debug_panel() -> void:
	_fixture_debug_controller.refresh_fixture_debug_panel()

func _is_manual_fixture_test_enabled() -> bool:
	return manual_fixture_toggle.button_pressed

func _apply_fixture_controls_from_debug(fixture_uuid: String, values: Dictionary, reason: String) -> void:
	var pan: float = float(values.get("pan", 0.0))
	var tilt: float = float(values.get("tilt", 0.0))
	var dimmer: float = float(values.get("dimmer", 100.0))
	_apply_pan_tilt_to_fixture(fixture_uuid, pan, tilt)
	_apply_dimmer_feedback_to_fixture(fixture_uuid, dimmer)
	_print_emitter_debug_vectors(fixture_uuid, reason, pan, tilt, dimmer)

func _apply_pan_tilt_to_fixture(fixture_uuid: String, pan_degrees: float, tilt_degrees: float) -> void:
	_apply_pan_tilt_components_to_fixture(fixture_uuid, true, pan_degrees, true, tilt_degrees)

func _apply_pan_tilt_components_to_fixture(fixture_uuid: String,
		has_pan: bool,
		pan_degrees: float,
		has_tilt: bool,
		tilt_degrees: float) -> void:
	var axis_entry: Dictionary = _get_fixture_axis_nodes(fixture_uuid)
	var pan_axis: Node3D = axis_entry.get("pan", null) as Node3D
	var tilt_axis: Node3D = axis_entry.get("tilt", null) as Node3D
	if has_pan and pan_axis != null:
		pan_axis.rotation_degrees.y = pan_degrees
	if has_tilt and tilt_axis != null:
		tilt_axis.rotation_degrees.x = tilt_degrees

func _register_native_runtime_targets(renderer_manifest: Array) -> void:
	_native_pan_targets.clear()
	_native_tilt_targets.clear()
	_native_dimmer_targets.clear()
	_native_target_resolution_failures.clear()
	_native_geometry_targets_by_key.clear()
	_native_dimmer_emitter_owner_by_key.clear()
	_native_target_registry_summary = _new_native_target_registry_summary()
	_build_native_geometry_target_map(renderer_manifest)
	for item in renderer_manifest:
		if item is not Dictionary:
			continue
		var row: Dictionary = item
		var targets: Array = row.get("targets", [])
		if not targets.is_empty():
			for target_item in targets:
				if target_item is Dictionary:
					_register_native_renderer_target(target_item)
			continue
		_register_native_legacy_manifest_row(row)
	_log_native_target_registry_summary_once()


func _register_native_legacy_manifest_row(row: Dictionary) -> void:
	var fixture_uuid: String = str(row.get("fixture_uuid", ""))
	if fixture_uuid.is_empty():
		return
	_register_native_axis_target(_native_pan_targets, row, int(row.get("pan_component_id", 0)), str(row.get("pan_geometry_key", "")), "pan")
	_register_native_axis_target(_native_tilt_targets, row, int(row.get("tilt_component_id", 0)), str(row.get("tilt_geometry_key", "")), "tilt")
	_register_native_dimmer_target(row, int(row.get("dimmer_target_id", 0)), fixture_uuid, str(row.get("dimmer_geometry_key", "")))

func _register_native_renderer_target(target: Dictionary) -> void:
	var semantic: String = str(target.get("semantic", "")).to_lower()
	var fixture_uuid: String = str(target.get("fixture_uuid", ""))
	var geometry_key: String = str(target.get("geometry_key", ""))
	if semantic == "pan":
		_register_native_axis_target(_native_pan_targets, target, int(target.get("target_id", target.get("component_id", 0))), geometry_key, "pan")
	elif semantic == "tilt":
		_register_native_axis_target(_native_tilt_targets, target, int(target.get("target_id", target.get("component_id", 0))), geometry_key, "tilt")
	elif semantic == "dimmer":
		_register_native_dimmer_target(target, int(target.get("render_target_id", target.get("target_id", 0))), fixture_uuid, geometry_key)

func _new_native_target_registry_summary() -> Dictionary:
	return {
		"imported_geometry_keys": 0,
		"empty_manifest_geometry_keys": 0,
		"duplicate_imported_geometry_keys": 0,
		"duplicate_manifest_target_ids": 0,
		"registration_timing_failures": 0,
		"pan_requested": 0,
		"pan_resolved": 0,
		"pan_failed": 0,
		"tilt_requested": 0,
		"tilt_resolved": 0,
		"tilt_failed": 0,
		"dimmer_requested": 0,
		"dimmer_resolved": 0,
		"dimmer_failed": 0,
		"dimmer_owner_geometries_resolved": 0,
		"dimmer_targets_with_emitter_nodes": 0,
		"dimmer_targets_with_lights": 0,
		"dimmer_targets_with_beam_instances": 0,
		"dimmer_targets_with_lens_materials": 0,
		"dimmer_targets_with_optional_spotlights": 0,
		"dimmer_targets_with_no_mutable_resource": 0,
		"dimmer_target_overlaps": 0,
		"first_failures": [],
	}

func _build_native_geometry_target_map(renderer_manifest: Array) -> void:
	var fixture_uuids: Dictionary = {}
	for item in renderer_manifest:
		if item is Dictionary:
			var fixture_uuid: String = str(item.get("fixture_uuid", ""))
			if not fixture_uuid.is_empty():
				fixture_uuids[fixture_uuid] = true
	for node_id in _node_index.keys():
		var node3d: Node3D = _node_index.get(node_id, null) as Node3D
		if node3d == null:
			continue
		var key: String = str(node3d.get_meta("peraviz_gdtf_geometry_key", ""))
		if key.is_empty():
			continue
		var fixture_uuid: String = str(node3d.get_meta("peraviz_fixture_uuid", ""))
		if fixture_uuid.is_empty():
			fixture_uuid = _fixture_uuid_from_geometry_key(key)
		if not fixture_uuids.has(fixture_uuid):
			continue
		if _native_geometry_targets_by_key.has(key):
			_native_target_registry_summary["duplicate_imported_geometry_keys"] = int(_native_target_registry_summary.get("duplicate_imported_geometry_keys", 0)) + 1
		_native_geometry_targets_by_key[key] = node3d
	_native_target_registry_summary["imported_geometry_keys"] = _native_geometry_targets_by_key.size()

func _register_native_axis_target(targets: Dictionary, manifest_row: Dictionary, target_id: int, geometry_key: String, role: String) -> void:
	if target_id <= 0:
		return
	_increment_registry_counter("%s_requested" % role)
	if geometry_key.is_empty():
		_increment_registry_counter("empty_manifest_geometry_keys")
		_register_native_target_failure(manifest_row, target_id, role, "Manifest target has an empty canonical geometry key.")
		return
	if targets.has(target_id):
		_increment_registry_counter("duplicate_manifest_target_ids")
		_register_native_target_failure(manifest_row, target_id, role, "Duplicate native target handle in renderer manifest.")
		return
	var target: Node3D = _native_geometry_targets_by_key.get(geometry_key, null) as Node3D
	if target == null:
		_register_native_target_failure(manifest_row, target_id, role, "No imported geometry node has canonical geometry key %s" % geometry_key)
		return
	targets[target_id] = target
	_increment_registry_counter("%s_resolved" % role)

func _register_native_dimmer_target(manifest_row: Dictionary, target_id: int, fixture_uuid: String, geometry_key: String) -> void:
	if target_id <= 0:
		return
	_increment_registry_counter("dimmer_requested")
	if geometry_key.is_empty():
		_increment_registry_counter("empty_manifest_geometry_keys")
		_register_native_target_failure(manifest_row, target_id, "dimmer", "Manifest target has an empty canonical geometry key.")
		return
	if _native_dimmer_targets.has(target_id):
		_increment_registry_counter("duplicate_manifest_target_ids")
		_register_native_target_failure(manifest_row, target_id, "dimmer", "Duplicate native Dimmer target handle in renderer manifest.")
		return
	var target: Node3D = _native_geometry_targets_by_key.get(geometry_key, null) as Node3D
	if target == null:
		_register_native_target_failure(manifest_row, target_id, "dimmer", "No imported geometry node has canonical geometry key %s" % geometry_key)
		return
	var target_nodes: Array = [target]
	var emitter_nodes: Array = _collect_native_descendant_emitters(geometry_key)
	emitter_nodes = _filter_native_dimmer_target_emitters(manifest_row, target_id, geometry_key, emitter_nodes)
	var cache_key: String = "%s:%d" % [fixture_uuid, target_id]
	var emitter_anchors: Array = _collect_fixture_emitter_lights(cache_key, emitter_nodes)
	var lens_material_targets: Array = _prepare_native_dimmer_lens_materials(cache_key, target_nodes + emitter_nodes)
	var beam_instances: Array = _prepare_native_dimmer_beam_instances(emitter_anchors)
	_native_dimmer_targets[target_id] = {
		"fixture_uuid": fixture_uuid,
		"property_id": int(manifest_row.get("property_id", 0)),
		"component_id": int(manifest_row.get("component_id", 0)),
		"render_target_id": target_id,
		"target_id": target_id,
		"owner_geometry_key": geometry_key,
		"owner_geometry_node": target,
		"geometry_nodes": target_nodes,
		"emitter_nodes": emitter_nodes,
		"emitter_anchors": emitter_anchors,
		"optional_spotlights": emitter_anchors,
		"beam_instances": beam_instances,
		"lens_material_targets": lens_material_targets,
		"emitter_photometrics": _get_fixture_emitter_photometrics(fixture_uuid),
	}
	_increment_registry_counter("dimmer_owner_geometries_resolved")
	if not emitter_nodes.is_empty():
		_increment_registry_counter("dimmer_targets_with_emitter_nodes")
	if not emitter_anchors.is_empty():
		_increment_registry_counter("dimmer_targets_with_lights")
		_increment_registry_counter("dimmer_targets_with_optional_spotlights")
	if not beam_instances.is_empty():
		_increment_registry_counter("dimmer_targets_with_beam_instances")
	if not lens_material_targets.is_empty():
		_increment_registry_counter("dimmer_targets_with_lens_materials")
	if emitter_anchors.is_empty() and beam_instances.is_empty() and lens_material_targets.is_empty():
		_increment_registry_counter("dimmer_targets_with_no_mutable_resource")
	_increment_registry_counter("dimmer_resolved")

func _prepare_native_dimmer_beam_instances(emitter_anchors: Array) -> Array:
	var beam_instances: Array = []
	for anchor in emitter_anchors:
		var spot: SpotLight3D = anchor as SpotLight3D
		if spot == null or not is_instance_valid(spot):
			continue
		spot.visible = false
		spot.light_energy = 0.0
		spot.set_meta("peraviz_beam_base_intensity", 0.0)
		_ensure_beam_runtime_for_light(spot)
		var beam: MeshInstance3D = _get_beam_resource_for_light(spot)
		if beam != null and is_instance_valid(beam):
			beam.visible = false
			beam_instances.append(beam)
	return beam_instances

func _get_beam_resource_for_light(light: SpotLight3D) -> MeshInstance3D:
	if _active_beam_renderer != null and _active_beam_renderer.has_method("get_beam_resource"):
		return _active_beam_renderer.get_beam_resource(light) as MeshInstance3D
	return null

func _filter_native_dimmer_target_emitters(manifest_row: Dictionary, target_id: int, geometry_key: String, emitter_nodes: Array) -> Array:
	var filtered: Array = []
	for emitter_node in emitter_nodes:
		var node3d: Node3D = emitter_node as Node3D
		if node3d == null:
			continue
		var emitter_key: String = str(node3d.get_meta("peraviz_gdtf_geometry_key", ""))
		if emitter_key.is_empty():
			continue
		if _native_dimmer_emitter_owner_by_key.has(emitter_key):
			_increment_registry_counter("dimmer_target_overlaps")
			_register_native_target_failure(manifest_row, target_id, "dimmer", "Emitter %s is already owned by Dimmer target %s." % [emitter_key, str(_native_dimmer_emitter_owner_by_key.get(emitter_key))])
			continue
		_native_dimmer_emitter_owner_by_key[emitter_key] = target_id
		filtered.append(node3d)
	return filtered

func _prepare_native_dimmer_lens_materials(cache_key: String, geometry_nodes: Array) -> Array:
	if _fixture_emissive_cache.has(cache_key):
		return _fixture_emissive_cache.get(cache_key, [])
	var targets: Array = []
	for geometry_node in geometry_nodes:
		_prepare_lens_material_targets_recursive(geometry_node, targets)
	_fixture_emissive_cache[cache_key] = targets
	return targets

func _prepare_lens_material_targets_recursive(node: Node3D, output_targets: Array) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		_prepare_mesh_lens_material_targets(node as MeshInstance3D, output_targets)
	for child in node.get_children():
		if child is Node3D:
			_prepare_lens_material_targets_recursive(child, output_targets)

func _prepare_mesh_lens_material_targets(mesh_instance: MeshInstance3D, output_targets: Array) -> void:
	if not _is_emitter_lens_mesh(mesh_instance):
		return
	var surface_count: int = mesh_instance.get_surface_override_material_count()
	if surface_count <= 0 and mesh_instance.mesh != null:
		surface_count = mesh_instance.mesh.get_surface_count()
	if surface_count <= 0:
		return
	for surface_index in range(surface_count):
		var material: Material = mesh_instance.get_surface_override_material(surface_index)
		if material == null and mesh_instance.mesh != null and surface_index < mesh_instance.mesh.get_surface_count():
			material = mesh_instance.mesh.surface_get_material(surface_index)
		var prepared: BaseMaterial3D = _prepare_lens_emissive_material(material)
		if prepared == null:
			continue
		mesh_instance.set_surface_override_material(surface_index, prepared)
		output_targets.append({"mesh": mesh_instance, "surface": surface_index, "material": prepared})

func _prepare_lens_emissive_material(material: Material) -> BaseMaterial3D:
	var prepared: BaseMaterial3D = null
	if material is BaseMaterial3D:
		prepared = (material as BaseMaterial3D).duplicate(true) as BaseMaterial3D
	else:
		prepared = StandardMaterial3D.new()
	if prepared == null:
		return null
	prepared.emission_enabled = true
	prepared.emission = Color.WHITE
	prepared.emission_energy_multiplier = 0.0
	return prepared

func _collect_native_descendant_emitters(geometry_key: String) -> Array:
	var nodes: Array = []
	var prefix: String = geometry_key + "/"
	for key in _native_geometry_targets_by_key.keys():
		var candidate_key: String = str(key)
		if candidate_key != geometry_key and not candidate_key.begins_with(prefix):
			continue
		var node: Node3D = _native_geometry_targets_by_key.get(key, null) as Node3D
		if node != null and bool(node.get_meta("peraviz_is_emitter", false)):
			nodes.append(node)
	return nodes

func _fixture_uuid_from_geometry_key(geometry_key: String) -> String:
	var slash_index: int = geometry_key.find("/")
	return geometry_key if slash_index < 0 else geometry_key.substr(0, slash_index)

func _increment_registry_counter(key: String) -> void:
	_native_target_registry_summary[key] = int(_native_target_registry_summary.get(key, 0)) + 1

func _register_native_target_failure(manifest_row: Dictionary, target_id: int, semantic: String, reason: String) -> void:
	_increment_registry_counter("%s_failed" % semantic)
	var failure: Dictionary = _target_failure(manifest_row, target_id, semantic, reason)
	_native_target_resolution_failures[target_id] = failure
	var failures: Array = _native_target_registry_summary.get("first_failures", [])
	if failures.size() < 5:
		failures.append(failure)
	_native_target_registry_summary["first_failures"] = failures

func _log_native_target_registry_summary_once() -> void:
	print("[native-target-registry] imported_geometry_keys=%d pan=%d/%d/%d tilt=%d/%d/%d dimmer=%d/%d/%d dimmer_resources=owners:%d emitters:%d lights:%d beams:%d materials:%d empty:%d empty_manifest_keys=%d duplicate_imported_keys=%d duplicate_manifest_target_ids=%d registration_timing_failures=%d first_failures=%s" % [
		int(_native_target_registry_summary.get("imported_geometry_keys", 0)),
		int(_native_target_registry_summary.get("pan_requested", 0)),
		int(_native_target_registry_summary.get("pan_resolved", 0)),
		int(_native_target_registry_summary.get("pan_failed", 0)),
		int(_native_target_registry_summary.get("tilt_requested", 0)),
		int(_native_target_registry_summary.get("tilt_resolved", 0)),
		int(_native_target_registry_summary.get("tilt_failed", 0)),
		int(_native_target_registry_summary.get("dimmer_requested", 0)),
		int(_native_target_registry_summary.get("dimmer_resolved", 0)),
		int(_native_target_registry_summary.get("dimmer_failed", 0)),
		int(_native_target_registry_summary.get("dimmer_owner_geometries_resolved", 0)),
		int(_native_target_registry_summary.get("dimmer_targets_with_emitter_nodes", 0)),
		int(_native_target_registry_summary.get("dimmer_targets_with_lights", 0)),
		int(_native_target_registry_summary.get("dimmer_targets_with_beam_instances", 0)),
		int(_native_target_registry_summary.get("dimmer_targets_with_lens_materials", 0)),
		int(_native_target_registry_summary.get("dimmer_targets_with_no_mutable_resource", 0)),
		int(_native_target_registry_summary.get("empty_manifest_geometry_keys", 0)),
		int(_native_target_registry_summary.get("duplicate_imported_geometry_keys", 0)),
		int(_native_target_registry_summary.get("duplicate_manifest_target_ids", 0)),
		int(_native_target_registry_summary.get("registration_timing_failures", 0)),
		str(_native_target_registry_summary.get("first_failures", [])),
	])

func _find_node_by_geometry_key(nodes: Array, geometry_key: String) -> Node3D:
	for node in nodes:
		var node3d: Node3D = node as Node3D
		if node3d == null:
			continue
		if not geometry_key.is_empty() and str(node3d.get_meta("peraviz_gdtf_geometry_key", "")) == geometry_key:
			return node3d
	return null

func _target_failure(manifest_row: Dictionary, target_id: int, semantic: String, reason: String) -> Dictionary:
	var fixture_uuid: String = str(manifest_row.get("fixture_uuid", ""))
	return {
		"fixture_uuid": fixture_uuid,
		"fixture_id": int(manifest_row.get("fixture_id", 0)),
		"target_id": target_id,
		"geometry_id": int(manifest_row.get("%s_geometry_id" % semantic, 0)),
		"geometry_key": str(manifest_row.get("%s_geometry_key" % semantic, "")),
		"matching_imported_keys": _matching_imported_geometry_keys(fixture_uuid),
		"fixture_root_path": _fixture_root_path(fixture_uuid),
		"semantic": semantic,
		"reason": reason,
	}

func _matching_imported_geometry_keys(fixture_uuid: String) -> Array:
	var keys: Array = []
	var prefix: String = fixture_uuid + "/"
	for key in _native_geometry_targets_by_key.keys():
		var candidate: String = str(key)
		if candidate.begins_with(prefix):
			keys.append(candidate)
			if keys.size() >= 8:
				break
	return keys

func _fixture_root_path(fixture_uuid: String) -> String:
	if _scene_registry == null or fixture_uuid.is_empty():
		return ""
	var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid)
	return str(fixture_node.get_path()) if fixture_node != null else ""

func _apply_native_transform_targets(pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> Dictionary:
	var pan_axis: Node3D = _native_pan_targets.get(pan_component_id, null) as Node3D
	var tilt_axis: Node3D = _native_tilt_targets.get(tilt_component_id, null) as Node3D
	var result: Dictionary = {"pan_requested": pan_component_id > 0, "pan_applied": false, "tilt_requested": tilt_component_id > 0, "tilt_applied": false, "failed": 0}
	if pan_component_id > 0 and pan_axis != null:
		pan_axis.rotation_degrees.y = pan_degrees
		result["pan_applied"] = true
	elif pan_component_id > 0:
		if not _native_target_resolution_failures.has(pan_component_id):
			_native_target_resolution_failures[pan_component_id] = {"target_id": pan_component_id, "semantic": "pan", "reason": "target never registered"}
		result["failed"] = int(result["failed"]) + 1
	if tilt_component_id > 0 and tilt_axis != null:
		tilt_axis.rotation_degrees.x = tilt_degrees
		result["tilt_applied"] = true
	elif tilt_component_id > 0:
		if not _native_target_resolution_failures.has(tilt_component_id):
			_native_target_resolution_failures[tilt_component_id] = {"target_id": tilt_component_id, "semantic": "tilt", "reason": "target never registered"}
		result["failed"] = int(result["failed"]) + 1
	return result

func _has_native_dimmer_target(dimmer_target_id: int) -> bool:
	return dimmer_target_id > 0 and _native_dimmer_targets.has(dimmer_target_id)

func _get_native_dimmer_target_record(dimmer_target_id: int) -> Dictionary:
	if dimmer_target_id <= 0:
		return {}
	return _native_dimmer_targets.get(dimmer_target_id, {})

func _get_native_target_failure(target_id: int) -> Variant:
	return _native_target_resolution_failures.get(target_id, null)

func _get_native_target_registry_summary() -> Dictionary:
	return {
		"pan_targets_resolved": _native_pan_targets.size(),
		"tilt_targets_resolved": _native_tilt_targets.size(),
		"dimmer_targets_resolved": _native_dimmer_targets.size(),
		"registry_summary": _native_target_registry_summary.duplicate(true),
		"target_resolution_failures": _native_target_resolution_failures.duplicate(true),
	}

func _find_axis_for_role(axis_nodes: Array, role: String) -> Node3D:
	if axis_nodes.is_empty():
		return null

	var role_name_hints: PackedStringArray = PackedStringArray([role])
	if role == "pan":
		role_name_hints.append("yoke")
	if role == "tilt":
		role_name_hints.append("head")

	for node in axis_nodes:
		if node == null:
			continue
		var normalized: String = node.name.to_lower()
		for hint in role_name_hints:
			if normalized.contains(hint):
				return node

	if role == "pan":
		return axis_nodes[0]
	if role == "tilt" and axis_nodes.size() > 1:
		return axis_nodes[1]
	return axis_nodes[0]

func _apply_dmx_visual_frame(dmx_fixture_runtime: DmxFixtureRuntime, receiver, delta_sec: float) -> Dictionary:
	if dmx_fixture_runtime == null:
		return {"updated": 0, "skipped": 0, "universes_changed": 0, "fixtures_considered": 0, "controls": []}
	if _fixture_light_apply_service == null:
		_fixture_light_apply_service = FixtureLightApplyServiceScript.new()
	return dmx_fixture_runtime.apply_visual_frame(receiver, self, _fixture_light_apply_service, delta_sec)

func _apply_live_visual_gobo_to_light(fixture_uuid: String, light: SpotLight3D, visual_gobo_state: Dictionary, live_controls: Dictionary = {}) -> Dictionary:
	if _fixture_gobo_projector == null or light == null or not is_instance_valid(light):
		return {"applied": false, "topology_changed": false}
	var controls: Dictionary = live_controls
	if controls.is_empty():
		_record_live_gobo_diagnostic(fixture_uuid, light, visual_gobo_state, {"controls_found": false})
		return {"applied": false, "topology_changed": false, "controls_found": false}
	var resolved_gobo_controls: Dictionary = _resolve_gobo_controls(controls)
	var gobo_source_controls: Dictionary = {
		"capabilities": controls.get("capabilities", {}),
		"gobo_norm": visual_gobo_state.get("gobo_norm", controls.get("gobo_norm", 0.0)),
		"gobo_raw_value": controls.get("gobo_raw_value", 0),
		"gobo_resolution_bits": controls.get("gobo_resolution_bits", 8),
		"gobo_index_norm": visual_gobo_state.get("gobo_index_norm", controls.get("gobo_index_norm", 0.0)),
		"has_gobo_index": controls.get("has_gobo_index", false),
		"gobo_rotation_norm": visual_gobo_state.get("gobo_rotation_norm", controls.get("gobo_rotation_norm", 0.0)),
		"has_gobo_rotation": controls.get("has_gobo_rotation", false),
		"gobo_rotation_deg": controls.get("gobo_rotation_deg", float(_visual_settings.get("gobo_rotation_deg", 0.0))),
		"gobo_debug_override_enabled": controls.get("gobo_debug_override_enabled", false),
		"gobo_debug_comparison_mode": controls.get("gobo_debug_comparison_mode", 0),
		"gobo_debug_shake_enabled": controls.get("gobo_debug_shake_enabled", false),
		"gobo_debug_shake_amplitude_deg": controls.get("gobo_debug_shake_amplitude_deg", 0.0),
		"gobo_debug_shake_frequency_hz": controls.get("gobo_debug_shake_frequency_hz", 0.0),
		"gobo_debug_shake_waveform": controls.get("gobo_debug_shake_waveform", 0),
		"frame_delta_sec": visual_gobo_state.get("frame_delta_sec", controls.get("frame_delta_sec", 0.0)),
		"prefer_native_fog_projector": controls.get("prefer_native_fog_projector", true),
		"gobo_scale": controls.get("gobo_scale", 1.0),
		"gobo_slots": resolved_gobo_controls.get("gobo_slots", []),
		"gobo_runtime_bindings": resolved_gobo_controls.get("gobo_runtime_bindings", []),
		"has_gobo": resolved_gobo_controls.get("has_gobo", false),
		"gobo_ranges": resolved_gobo_controls.get("gobo_ranges", controls.get("gobo_ranges", [])),
	}
	var before_compositions: int = int(_fixture_gobo_projector.get_debug_counters().get("texture_compositions", 0))
	var gobo_controls: Dictionary = BeamOpticsControllerScript.BuildGoboControls(gobo_source_controls, _visual_settings, _cached_beam_defaults)
	var topology_changed: bool = _fixture_gobo_projector.apply_gobo_projection(light, gobo_controls)
	var has_texture_meta: bool = light.has_meta("peraviz_gobo_texture") and light.get_meta("peraviz_gobo_texture") != null
	var debug_counters: Dictionary = _fixture_gobo_projector.get_debug_counters()
	var projector_diagnostics: Dictionary = light.get_meta("peraviz_live_gobo_projector_diagnostics", {}) if light.has_meta("peraviz_live_gobo_projector_diagnostics") else {}
	light.set_meta("peraviz_gobo_debug_counters", debug_counters)
	_record_live_gobo_diagnostic(fixture_uuid, light, visual_gobo_state, {
		"controls_found": true,
		"has_gobo": bool(gobo_controls.get("has_gobo", false)),
		"gobo_slot_count": (gobo_controls.get("gobo_slots", []) as Array).size(),
		"gobo_range_count": (gobo_controls.get("gobo_ranges", []) as Array).size(),
		"runtime_binding_count": (gobo_controls.get("gobo_runtime_bindings", []) as Array).size(),
		"raw_gobo_value": int(gobo_controls.get("gobo_raw_value", -1)),
		"texture_meta_present_after_projector": has_texture_meta,
		"resolved_slot_index": int(projector_diagnostics.get("resolved_slot_index", -1)),
		"texture_path": str(projector_diagnostics.get("texture_path", "")),
		"texture_load_success": bool(projector_diagnostics.get("texture_load_success", false)),
	})
	return {
		"applied": true,
		"topology_changed": topology_changed,
		"motion_state_updated": bool(visual_gobo_state.get("parametric_changed", false)),
		"texture_compositions": int(debug_counters.get("texture_compositions", before_compositions)),
		"texture_meta_present_after_projector": has_texture_meta,
	}

func _record_live_gobo_diagnostic(fixture_uuid: String, light: SpotLight3D, visual_gobo_state: Dictionary, values: Dictionary) -> void:
	var diagnostics: Dictionary = visual_gobo_state.get("diagnostics", {})
	diagnostics.merge(values, true)
	if light != null and is_instance_valid(light):
		light.set_meta("peraviz_live_gobo_diagnostics", diagnostics)
	var key: String = "live_gobo:" + fixture_uuid + ":" + str(diagnostics.get("controls_found", false)) + ":" + str(diagnostics.get("texture_meta_present_after_projector", false))
	if not bool(_visual_settings.get("beam_debug_optics", false)) or _live_gobo_diagnostic_keys.has(key):
		return
	_live_gobo_diagnostic_keys[key] = true
	print("[PeravizLiveGobo] fixture=%s controls=%s has_gobo=%s slots=%d ranges=%d runtime_bindings=%d raw=%d texture_meta=%s" % [fixture_uuid, str(bool(diagnostics.get("controls_found", false))), str(bool(diagnostics.get("has_gobo", false))), int(diagnostics.get("gobo_slot_count", 0)), int(diagnostics.get("gobo_range_count", 0)), int(diagnostics.get("runtime_binding_count", 0)), int(diagnostics.get("raw_gobo_value", -1)), str(bool(diagnostics.get("texture_meta_present_after_projector", false)))])

func _record_live_visual_gobo_beam_result(_fixture_uuid: String, light: SpotLight3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	var diagnostics: Dictionary = light.get_meta("peraviz_live_gobo_diagnostics", {}) if light.has_meta("peraviz_live_gobo_diagnostics") else {}
	diagnostics["beam_gobo_consumed"] = bool(light.get_meta("peraviz_last_beam_gobo_consumed", false))
	diagnostics["beam_renderer_mode"] = str(light.get_meta("peraviz_last_beam_renderer_mode", ""))
	light.set_meta("peraviz_live_gobo_diagnostics", diagnostics)

func _apply_dmx_controls_to_fixture(fixture_uuid: String, controls: Dictionary) -> void:
	if _fixture_light_apply_service == null:
		_fixture_light_apply_service = FixtureLightApplyServiceScript.new()
	_fixture_light_apply_service.apply_dmx_controls_to_fixture(self, fixture_uuid, controls)

func _resolve_capability_bucket(controls: Dictionary, capability_type: String) -> Array:
	return _fixture_light_apply_service.resolve_capability_bucket(controls, capability_type)

func _resolve_first_capability_block(controls: Dictionary, capability_type: String) -> Dictionary:
	return _fixture_light_apply_service.resolve_first_capability_block(controls, capability_type)

func _resolve_pan_tilt_controls(controls: Dictionary) -> Dictionary:
	return _fixture_light_apply_service.resolve_pan_tilt_controls(controls)

func _resolve_dimmer_controls(controls: Dictionary) -> Dictionary:
	return _fixture_light_apply_service.resolve_dimmer_controls(controls)

func _resolve_color_wheel_controls(controls: Dictionary) -> Dictionary:
	return _fixture_light_apply_service.resolve_color_wheel_controls(controls)

func _resolve_gobo_controls(controls: Dictionary) -> Dictionary:
	return _fixture_light_apply_service.resolve_gobo_controls(controls)

func _has_lighting_controls(controls: Dictionary) -> bool:
	return _fixture_light_apply_service.has_lighting_controls(controls)

func _apply_dimmer_feedback_to_fixture(fixture_uuid: String, dimmer: float, controls: Dictionary = {}) -> void:
	_fixture_light_apply_service.apply_dimmer_feedback_to_fixture(self, fixture_uuid, dimmer, controls)

func _prepare_fixture_node_cache(fixture_uuid: String) -> void:
	_get_fixture_geometry_nodes(fixture_uuid)
	_get_fixture_emitter_nodes(fixture_uuid)
	_get_fixture_axis_nodes(fixture_uuid)

func _clear_fixture_node_cache() -> void:
	_fixture_geometry_nodes_cache.clear()
	_fixture_emitter_nodes_cache.clear()
	_fixture_axis_nodes_cache.clear()

func _get_fixture_geometry_nodes(fixture_uuid: String) -> Array:
	if _fixture_geometry_nodes_cache.has(fixture_uuid):
		return _fixture_geometry_nodes_cache.get(fixture_uuid, [])
	var nodes: Array = _to_node3d_array(_scene_registry.get_anchor(fixture_uuid, "geometry_nodes"))
	_fixture_geometry_nodes_cache[fixture_uuid] = nodes
	return nodes

func _get_fixture_emitter_nodes(fixture_uuid: String) -> Array:
	if _fixture_emitter_nodes_cache.has(fixture_uuid):
		return _fixture_emitter_nodes_cache.get(fixture_uuid, [])
	var nodes: Array = _to_node3d_array(_scene_registry.get_anchor(fixture_uuid, "emitters"))
	_fixture_emitter_nodes_cache[fixture_uuid] = nodes
	return nodes

func _get_fixture_axis_nodes(fixture_uuid: String) -> Dictionary:
	if _fixture_axis_nodes_cache.has(fixture_uuid):
		return _fixture_axis_nodes_cache.get(fixture_uuid, {})
	var axis_nodes: Array = _to_node3d_array(_scene_registry.get_anchor(fixture_uuid, "axis"))
	var axis_entry: Dictionary = {
		"pan": _find_axis_for_role(axis_nodes, "pan"),
		"tilt": _find_axis_for_role(axis_nodes, "tilt"),
	}
	_fixture_axis_nodes_cache[fixture_uuid] = axis_entry
	return axis_entry

func _collect_fixture_emissive_materials(fixture_uuid: String, geometry_nodes: Array) -> Array:
	if _fixture_emissive_cache.has(fixture_uuid):
		return _fixture_emissive_cache.get(fixture_uuid, [])

	var materials: Array = []
	for geometry in geometry_nodes:
		_collect_emissive_materials_recursive(geometry, materials)
	_fixture_emissive_cache[fixture_uuid] = materials
	return materials

func _collect_fixture_emitter_lights(fixture_uuid: String, emitter_nodes: Array) -> Array:
	if _fixture_emitter_light_cache.has(fixture_uuid):
		return _fixture_emitter_light_cache.get(fixture_uuid, [])

	var lights: Array = []
	for emitter_node in emitter_nodes:
		if emitter_node == null:
			continue
		var light: SpotLight3D = _find_or_create_emitter_light(emitter_node)
		if light != null:
			lights.append(light)

	_fixture_emitter_light_cache[fixture_uuid] = lights
	return lights

func _resolve_fixture_beam_color(emitter_photometrics: Array, controls: Dictionary) -> Color:
	if emitter_photometrics.is_empty():
		return _derive_emitter_color(DEFAULT_EMITTER_PHOTOMETRICS, controls, BEAM_COLOR_TEMPERATURE_STRENGTH)

	var accumulated_color: Color = Color.BLACK
	var samples: int = 0
	for entry in emitter_photometrics:
		if entry is not Dictionary:
			continue
		accumulated_color += _derive_emitter_color(entry, controls, BEAM_COLOR_TEMPERATURE_STRENGTH)
		samples += 1
	if samples <= 0:
		return _derive_emitter_color(DEFAULT_EMITTER_PHOTOMETRICS, controls, BEAM_COLOR_TEMPERATURE_STRENGTH)
	var inverse_samples: float = 1.0 / float(samples)
	return Color(accumulated_color.r * inverse_samples, accumulated_color.g * inverse_samples, accumulated_color.b * inverse_samples, 1.0)

func _find_or_create_emitter_light(emitter_node: Node3D) -> SpotLight3D:
	var lens_radius: float = _estimate_emitter_lens_radius(emitter_node)
	for child in emitter_node.get_children():
		if child is SpotLight3D and child.name == "PeravizEmitterLight":
			if child.rotation_degrees != EMITTER_LIGHT_DIRECTION_FIX:
				child.rotation_degrees = EMITTER_LIGHT_DIRECTION_FIX
			# Fixture beams use dedicated mesh shaders, so positional shadows stay off by default.
			child.shadow_enabled = false
			child.shadow_bias = 0.05
			child.shadow_normal_bias = 1.2
			child.set_meta("peraviz_lens_radius", lens_radius)
			return child

	var light := SpotLight3D.new()
	light.name = "PeravizEmitterLight"
	light.position = Vector3.ZERO
	light.rotation_degrees = EMITTER_LIGHT_DIRECTION_FIX
	light.light_negative = false
	light.shadow_enabled = false
	light.shadow_bias = 0.05
	light.shadow_normal_bias = 1.2
	light.spot_range = 60.0
	light.spot_angle = 25.0
	light.spot_attenuation = 1.0
	light.set_meta("peraviz_lens_radius", lens_radius)
	emitter_node.add_child(light)
	return light

func _estimate_emitter_lens_radius(emitter_node: Node3D) -> float:
	var default_radius: float = 0.03
	if emitter_node == null:
		return default_radius

	var hinted_radius: float = _estimate_emitter_lens_radius_from_root(emitter_node, true)
	if hinted_radius > 0.0:
		return hinted_radius

	# Some fixtures do not name the lens geometry explicitly; fallback to nearest
	# mesh around the emitter origin so we still keep beam base and lens width aligned.
	var fallback_radius: float = _estimate_emitter_lens_radius_from_root(emitter_node, false)
	if fallback_radius > 0.0:
		return fallback_radius

	if emitter_node.get_parent() is Node3D:
		var parent_node: Node3D = emitter_node.get_parent() as Node3D
		var parent_hinted_radius: float = _estimate_emitter_lens_radius_from_root(parent_node, true)
		if parent_hinted_radius > 0.0:
			return parent_hinted_radius
		var parent_fallback_radius: float = _estimate_emitter_lens_radius_from_root(parent_node, false)
		if parent_fallback_radius > 0.0:
			return parent_fallback_radius
	return default_radius

func _estimate_emitter_lens_radius_from_root(root: Node3D, require_name_hints: bool) -> float:
	if root == null:
		return -1.0
	var candidates: Array = []
	var world_to_root: Transform3D = root.global_transform.affine_inverse()
	_collect_emitter_lens_candidates_recursive(root, world_to_root, require_name_hints, candidates)
	if candidates.is_empty():
		return -1.0

	var best_name_score: int = 1 << 20
	var best_position_score: float = INF
	var best_radius: float = -1.0
	for candidate in candidates:
		if not (candidate is Dictionary):
			continue
		var radius: float = float(candidate.get("radius", -1.0))
		if radius < 0.005:
			continue
		var center: Vector3 = candidate.get("center", Vector3.ZERO)
		var name_score: int = int(candidate.get("name_score", 9999))
		var radial_distance: float = Vector2(center.x, center.y).length()
		var axial_distance: float = abs(center.z)
		var position_score: float = axial_distance * 1.5 + radial_distance
		var name_is_better: bool = name_score < best_name_score
		var same_name: bool = name_score == best_name_score
		var position_is_better: bool = position_score < best_position_score
		var position_tie: bool = is_equal_approx(position_score, best_position_score)
		if name_is_better or (same_name and (position_is_better or (position_tie and radius > best_radius))):
			best_name_score = name_score
			best_position_score = position_score
			best_radius = radius
	return max(best_radius, -1.0)

func _collect_emitter_lens_candidates_recursive(node: Node3D, world_to_root: Transform3D, require_name_hints: bool, output_candidates: Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		if (not require_name_hints) or _is_emitter_lens_mesh(mesh_instance):
			var mesh_bounds: AABB = mesh_instance.get_aabb()
			if mesh_bounds.size != Vector3.ZERO:
				var local_bounds: AABB = world_to_root * (mesh_instance.global_transform * mesh_bounds)
				var candidate_radius: float = _estimate_mesh_aperture_radius(mesh_instance, world_to_root)
				if candidate_radius <= 0.0001:
					candidate_radius = max(local_bounds.size.x, local_bounds.size.y) * 0.5
				if candidate_radius > 0.0001:
					output_candidates.append({
						"center": local_bounds.get_center(),
						"radius": max(candidate_radius, 0.001),
						"name_score": _lens_name_priority(mesh_instance.name)
					})

	for child in node.get_children():
		if child is Node3D:
			_collect_emitter_lens_candidates_recursive(child, world_to_root, require_name_hints, output_candidates)

func _estimate_mesh_aperture_radius(mesh_instance: MeshInstance3D, world_to_root: Transform3D) -> float:
	if mesh_instance == null or mesh_instance.mesh == null:
		return -1.0

	var best_radius: float = -1.0
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var local_vertices: Array = []
		local_vertices.resize(vertices.size())
		var min_abs_z: float = INF
		for i in range(vertices.size()):
			var root_local: Vector3 = world_to_root * (mesh_instance.global_transform * vertices[i])
			local_vertices[i] = root_local
			min_abs_z = min(min_abs_z, abs(root_local.z))

		if not is_finite(min_abs_z):
			continue
		var z_tolerance: float = max(0.002, min_abs_z * 0.5)
		var surface_radius: float = -1.0
		for v in local_vertices:
			var point: Vector3 = v
			if abs(abs(point.z) - min_abs_z) > z_tolerance:
				continue
			var radial: float = Vector2(point.x, point.y).length()
			surface_radius = max(surface_radius, radial)
		if surface_radius > best_radius:
			best_radius = surface_radius

	return best_radius

func _lens_name_priority(node_name: String) -> int:
	var name_hint: String = node_name.to_lower()
	if name_hint.contains("lens"):
		return 0
	if name_hint.contains("glass"):
		return 1
	if name_hint.contains("front"):
		return 2
	if name_hint.contains("emitter"):
		return 3
	if name_hint.contains("beam"):
		return 4
	return 5

func _is_emitter_lens_mesh(mesh_instance: MeshInstance3D) -> bool:
	var name_hint: String = mesh_instance.name.to_lower()
	return name_hint.contains("lens") or name_hint.contains("glass") or name_hint.contains("emitter") or name_hint.contains("beam")

func _get_fixture_emitter_photometrics(fixture_uuid: String) -> Array:
	if _fixture_emitter_photometrics.has(fixture_uuid):
		return _fixture_emitter_photometrics.get(fixture_uuid, [])
	var entries: Variant = _scene_registry.get_anchor(fixture_uuid, "emitter_photometrics")
	if entries is Array:
		_fixture_emitter_photometrics[fixture_uuid] = entries
		return entries
	var empty: Array = []
	_fixture_emitter_photometrics[fixture_uuid] = empty
	return empty

func _extract_emitter_photometrics(item: Dictionary) -> Dictionary:
	var data: Dictionary = DEFAULT_EMITTER_PHOTOMETRICS.duplicate(true)
	if bool(item.get("has_luminous_flux", false)):
		data["luminous_flux"] = float(item.get("luminous_flux", data["luminous_flux"]))
	if bool(item.get("has_color_temperature", false)):
		data["has_color_temperature"] = true
		data["color_temperature"] = float(item.get("color_temperature", data["color_temperature"]))
	if bool(item.get("has_beam_angle", false)):
		data["beam_angle"] = float(item.get("beam_angle", data["beam_angle"]))
	if bool(item.get("has_field_angle", false)):
		data["field_angle"] = float(item.get("field_angle", data["field_angle"]))
	if bool(item.get("has_beam_radius", false)):
		data["beam_radius"] = float(item.get("beam_radius", data["beam_radius"]))
		data["beam_radius_from_gdtf"] = true
	if bool(item.get("has_dominant_wavelength", false)):
		data["dominant_wavelength"] = float(item.get("dominant_wavelength", 0.0))
	return data

func _get_render_ready_values(controls: Dictionary) -> PackedFloat32Array:
	var values: Variant = controls.get("render_ready_values", PackedFloat32Array())
	return values if values is PackedFloat32Array else PackedFloat32Array()

func _render_ready_color(values: PackedFloat32Array) -> Color:
	if values.size() < 9:
		return Color.WHITE
	return Color(clamp(values[4], 0.0, 1.0), clamp(values[5], 0.0, 1.0), clamp(values[6], 0.0, 1.0), 1.0)

func _build_cached_beam_params(light: SpotLight3D, beam_angle: float, beam_color: Color, normalized_dimmer: float, scaled_intensity: float, lens_radius: float, beam_defaults: Dictionary) -> Dictionary:
	var cache_key: String = "%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%d" % [
		beam_angle,
		beam_color.r,
		beam_color.g,
		beam_color.b,
		lens_radius,
		light.spot_range,
		1 if light.visible else 0,
	]
	var params: Dictionary
	if _beam_params_template_cache.has(cache_key):
		params = (_beam_params_template_cache.get(cache_key, {}) as Dictionary).duplicate(false)
	else:
		params = BeamOpticsControllerScript.BuildBeamParams(
			light,
			beam_angle,
			beam_color,
			0.0,
			0.0,
			lens_radius,
			_visual_settings,
			beam_defaults,
			beam_defaults
		)
		if _beam_params_template_cache.size() >= BEAM_PARAMS_TEMPLATE_CACHE_LIMIT:
			_beam_params_template_cache.clear()
		_beam_params_template_cache[cache_key] = params.duplicate(false)
	params["normalized_dimmer"] = clamp(normalized_dimmer, 0.0, 1.0)
	params["scaled_intensity"] = scaled_intensity
	params["beam_intensity"] = scaled_intensity
	return params

func _apply_emitter_light_state(light: SpotLight3D, photometric: Dictionary, normalized_dimmer: float, controls: Dictionary = {}) -> void:
	var last_state: Dictionary = _get_or_create_emitter_last_state(light)
	var render_ready_values: PackedFloat32Array = _get_render_ready_values(controls)
	var has_render_ready: bool = render_ready_values.size() >= 9
	var luminous_flux: float = max(float(photometric.get("luminous_flux", 10000.0)), 0.0)
	var beam_angle: float = render_ready_values[3] if has_render_ready else clamp(float(photometric.get("beam_angle", 25.0)), 0.1, EMITTER_LIGHT_MAX_BEAM_ANGLE_DEG)
	var field_angle: float = clamp(float(photometric.get("field_angle", beam_angle)), beam_angle, EMITTER_LIGHT_MAX_BEAM_ANGLE_DEG)
	var dimmer_controls: Dictionary = _resolve_dimmer_controls(controls)
	if not has_render_ready and bool(dimmer_controls.get("has_zoom", false)):
		var zoom_norm: float = clamp(float(dimmer_controls.get("zoom_norm", 0.0)), 0.0, 1.0)
		var zoom_limits: Dictionary = _resolve_zoom_beam_limits(light, controls)
		var zoom_min_angle: float = float(zoom_limits.get("min_beam_angle", EMITTER_ZOOM_DEFAULT_MIN_BEAM_ANGLE_DEG))
		var zoom_max_angle: float = float(zoom_limits.get("max_beam_angle", EMITTER_ZOOM_DEFAULT_MAX_BEAM_ANGLE_DEG))
		beam_angle = lerp(zoom_min_angle, zoom_max_angle, zoom_norm)
		field_angle = max(field_angle, beam_angle)
	var beam_radius_m: float = max(float(photometric.get("beam_radius", 0.05)), 0.001)

	_set_light_property_bool(light, "visible", normalized_dimmer > 0.0001, last_state)
	var base_light_energy: float = render_ready_values[0] if has_render_ready else luminous_flux * normalized_dimmer * EMITTER_LIGHT_ENERGY_SCALE
	_set_light_meta_float(light, "peraviz_base_light_energy", base_light_energy, last_state)
	var light_energy: float = base_light_energy * float(_visual_settings.get("spot_multiplier", 1.0))
	_set_light_property_float(light, "light_energy", light_energy, last_state)
	var beam_half_angle_deg: float = render_ready_values[2] if has_render_ready else beam_angle * 0.5
	# Godot 4.2 SpotLight3D.spot_angle behaves as cone half-angle in degrees.
	# Keep zoom/beam limits as full GDTF aperture, and convert here for light projection.
	_set_light_property_float(light, "spot_angle", beam_half_angle_deg, last_state)
	var spot_attenuation: float = clamp(beam_angle / max(field_angle, 0.1), EMITTER_LIGHT_SPOT_ATTENUATION_MIN, EMITTER_LIGHT_SPOT_ATTENUATION_MAX)
	var beam_slope: float = tan(deg_to_rad(beam_half_angle_deg))
	var nominal_spot_range: float = beam_radius_m * EMITTER_LIGHT_RANGE_BEAM_RADIUS_MULTIPLIER * EMITTER_BEAM_LENGTH_SCALE
	var max_spot_range_from_footprint: float = EMITTER_LIGHT_MAX_RANGE_M
	if beam_slope > 0.0001:
		max_spot_range_from_footprint = max(EMITTER_LIGHT_MAX_FOOTPRINT_RADIUS_M / beam_slope, EMITTER_LIGHT_MIN_EFFECTIVE_RANGE_M)
	var cone_range: float = clamp(min(nominal_spot_range, max_spot_range_from_footprint), EMITTER_LIGHT_MIN_EFFECTIVE_RANGE_M, EMITTER_LIGHT_MAX_RANGE_M)
	# SpotLight3D footprint follows transform by default in Godot; this extension only
	# avoids early floor clipping on steep tilt while keeping cone visuals unchanged.
	_set_light_property_float(light, "spot_range", clamp(cone_range * EMITTER_LIGHT_FOOTPRINT_RANGE_MULTIPLIER, EMITTER_LIGHT_MIN_EFFECTIVE_RANGE_M, EMITTER_LIGHT_MAX_RANGE_M), last_state)
	_set_light_property_float(light, "spot_attenuation", spot_attenuation, last_state)
	var light_color: Color = _render_ready_color(render_ready_values) if has_render_ready else _derive_emitter_color(photometric, controls)
	_set_light_property_color(light, "light_color", light_color, last_state)
	var beam_color: Color = light_color if has_render_ready else _derive_emitter_color(photometric, controls, BEAM_COLOR_TEMPERATURE_STRENGTH)
	var beam_radius_from_gdtf: bool = bool(photometric.get("beam_radius_from_gdtf", false))
	var source_beam_radius: float = beam_radius_m if beam_radius_from_gdtf else -1.0
	var lens_radius: float = max(float(light.get_meta("peraviz_lens_radius", 0.03)), 0.005)
	if source_beam_radius > 0.0:
		lens_radius = max(source_beam_radius, 0.005)
	_set_light_meta_float(light, "peraviz_beam_base_intensity", clamp(normalized_dimmer, 0.0, 1.0), last_state)
	_set_light_meta_variant(light, "peraviz_beam_angle_source", "gdtf_full_angle_deg", last_state)
	var scaled_intensity: float = clamp(render_ready_values[7], 0.0, BEAM_INTENSITY_MAX) if has_render_ready else clamp(normalized_dimmer * float(_visual_settings.get("beam_multiplier", 20.0)), 0.0, BEAM_INTENSITY_MAX)
	var beam_defaults: Dictionary = _cached_beam_defaults
	var beam_params: Dictionary = _build_cached_beam_params(light, beam_angle, beam_color, normalized_dimmer, scaled_intensity, lens_radius, beam_defaults)
	beam_params["fade_end_ratio"] = EMITTER_CONE_FADE_END_RATIO
	beam_params["intensity_visibility_threshold"] = BEAM_INTENSITY_VISIBILITY_THRESHOLD
	beam_params["distance_cull_m"] = BEAM_DISTANCE_CULL_M
	beam_params["use_native_fog_projector_gobos"] = bool(_visual_settings.get("use_native_fog_projector_gobos", true))
	beam_params["volumetric_fog_density"] = float(_visual_settings.get("volumetric_fog_density", 0.0))
	beam_params["intensity_max"] = BEAM_INTENSITY_MAX
	var gobo_topology_changed: bool = false
	var changed_capability_types: Dictionary = controls.get("changed_capability_types", {})
	var skip_gobo_projection: bool = bool(controls.get("skip_gobo_projection", false))
	var gobo_capability_changed: bool = changed_capability_types.is_empty() or bool(changed_capability_types.get("gobo", false))
	if _fixture_gobo_projector != null and gobo_capability_changed and not skip_gobo_projection:
		var resolved_gobo_controls: Dictionary = _resolve_gobo_controls(controls)
		var gobo_source_controls: Dictionary = {
			"capabilities": controls.get("capabilities", {}),
			"gobo_norm": controls.get("gobo_norm", 0.0),
			"gobo_raw_value": controls.get("gobo_raw_value", 0),
			"gobo_resolution_bits": controls.get("gobo_resolution_bits", 8),
			"gobo_index_norm": controls.get("gobo_index_norm", 0.0),
			"has_gobo_index": controls.get("has_gobo_index", false),
			"gobo_rotation_deg": controls.get("gobo_rotation_deg", 0.0),
			"gobo_debug_override_enabled": controls.get("gobo_debug_override_enabled", false),
			"gobo_debug_comparison_mode": controls.get("gobo_debug_comparison_mode", 0),
			"gobo_debug_shake_enabled": controls.get("gobo_debug_shake_enabled", false),
			"gobo_debug_shake_amplitude_deg": controls.get("gobo_debug_shake_amplitude_deg", 0.0),
			"gobo_debug_shake_frequency_hz": controls.get("gobo_debug_shake_frequency_hz", 0.0),
			"gobo_debug_shake_waveform": controls.get("gobo_debug_shake_waveform", 0),
			"frame_delta_sec": controls.get("frame_delta_sec", 0.0),
			"prefer_native_fog_projector": controls.get("prefer_native_fog_projector", true),
			"gobo_scale": controls.get("gobo_scale", 1.0),
			"gobo_slots": resolved_gobo_controls.get("gobo_slots", []),
			"gobo_runtime_bindings": resolved_gobo_controls.get("gobo_runtime_bindings", []),
			"has_gobo": resolved_gobo_controls.get("has_gobo", false),
			"gobo_ranges": resolved_gobo_controls.get("gobo_ranges", controls.get("gobo_ranges", [])),
		}
		var gobo_controls: Dictionary = BeamOpticsControllerScript.BuildGoboControls(gobo_source_controls, _visual_settings, beam_defaults)
		var gobo_phase_start: int = Time.get_ticks_usec()
		gobo_topology_changed = _fixture_gobo_projector.apply_gobo_projection(light, gobo_controls)
		if _fixture_light_apply_service != null:
			_fixture_light_apply_service._track_phase("gobo_update", gobo_phase_start)
		_set_light_meta_variant(light, "peraviz_last_gobo_key", str(gobo_controls.get("key", "")), last_state)
		var applied_gobo_rotation_deg: float = float(light.get_meta("peraviz_gobo_applied_rotation_deg", beam_params.get("gobo_rotation_deg", 0.0)))
		beam_params["gobo_rotation_deg"] = applied_gobo_rotation_deg
	elif _fixture_gobo_projector != null:
		var applied_rotation: float = float(light.get_meta("peraviz_gobo_applied_rotation_deg", beam_params.get("gobo_rotation_deg", 0.0)))
		beam_params["gobo_rotation_deg"] = applied_rotation
	if gobo_topology_changed:
		_emitter_mesh_rebuild_count += 1
		_cleanup_light_beam_renderers(light)
	_set_light_property_float(light, "light_volumetric_fog_energy", float(_visual_settings.get("light_volumetric_fog_energy", 12.0)) * float(_visual_settings.get("haze_density_multiplier", 0.22)), last_state)
	var beam_phase_start: int = Time.get_ticks_usec()
	_update_beam_for_light(light, beam_params)
	if _fixture_light_apply_service != null:
		_fixture_light_apply_service._track_phase("beam_update", beam_phase_start)
	_emitter_parametric_update_count += 1
	if _fixture_gobo_projector != null:
		light.set_meta("peraviz_gobo_debug_counters", _fixture_gobo_projector.get_debug_counters())
	light.set_meta("peraviz_emitter_debug_counters", {
		"mesh_rebuilds": _emitter_mesh_rebuild_count,
		"parametric_updates": _emitter_parametric_update_count,
	})

func _get_or_create_emitter_last_state(light: SpotLight3D) -> Dictionary:
	var key: int = light.get_instance_id()
	if not _fixture_emitter_last_state.has(key):
		_fixture_emitter_last_state[key] = {}
	return _fixture_emitter_last_state.get(key, {})

func _is_close_float(a: float, b: float, epsilon: float = EMITTER_LIGHT_STATE_EPSILON) -> bool:
	return abs(a - b) < epsilon

func _is_close_color(a: Color, b: Color, epsilon: float = EMITTER_LIGHT_COLOR_EPSILON) -> bool:
	return _is_close_float(a.r, b.r, epsilon) and _is_close_float(a.g, b.g, epsilon) and _is_close_float(a.b, b.b, epsilon) and _is_close_float(a.a, b.a, epsilon)

func _track_property_change(applied: bool) -> void:
	if applied:
		_debug_properties_applied += 1
	else:
		_debug_properties_skipped += 1


func _set_light_property_float(light: SpotLight3D, property_name: String, value: float, last_state: Dictionary) -> void:
	var cache_key: String = "prop:" + property_name
	var previous: float = float(last_state.get(cache_key, INF))
	if _is_close_float(previous, value):
		_track_property_change(false)
		return
	if _apply_light_server_float(light, property_name, value):
		last_state[cache_key] = value
		_track_property_change(true)
	else:
		_track_property_change(false)

func _set_light_property_bool(light: SpotLight3D, property_name: String, value: bool, last_state: Dictionary) -> void:
	var cache_key: String = "prop:" + property_name
	var has_previous: bool = last_state.has(cache_key)
	if has_previous and bool(last_state.get(cache_key, false)) == value:
		_track_property_change(false)
		return
	if _apply_light_server_bool(light, property_name, value):
		last_state[cache_key] = value
		_track_property_change(true)
	else:
		_track_property_change(false)

func _set_light_property_color(light: SpotLight3D, property_name: String, value: Color, last_state: Dictionary) -> void:
	var cache_key: String = "prop:" + property_name
	if last_state.has(cache_key) and _is_close_color(last_state.get(cache_key, Color.BLACK), value):
		_track_property_change(false)
		return
	if _apply_light_server_color(light, property_name, value):
		last_state[cache_key] = value
		_track_property_change(true)
	else:
		_track_property_change(false)

func _apply_light_server_float(light: SpotLight3D, property_name: String, value: float) -> bool:
	var param: int = _get_light_server_float_param(property_name)
	if param == -1:
		push_warning("Unsupported light float property for RenderingServer update: %s" % property_name)
		return false
	var light_rid: RID = _get_light_base_rid(light)
	if not light_rid.is_valid():
		return false
	RenderingServer.light_set_param(light_rid, param, value)
	return true

func _get_light_server_float_param(property_name: String) -> int:
	match property_name:
		"light_energy":
			return RenderingServer.LIGHT_PARAM_ENERGY
		"light_volumetric_fog_energy":
			return RenderingServer.LIGHT_PARAM_VOLUMETRIC_FOG_ENERGY
		"spot_angle":
			return RenderingServer.LIGHT_PARAM_SPOT_ANGLE
		"spot_range":
			return RenderingServer.LIGHT_PARAM_RANGE
		"spot_attenuation":
			return RenderingServer.LIGHT_PARAM_SPOT_ATTENUATION
		_:
			return -1

func _apply_light_server_bool(light: SpotLight3D, property_name: String, value: bool) -> bool:
	if property_name == "visible":
		var instance_rid: RID = light.get_instance() if light != null and is_instance_valid(light) else RID()
		if not instance_rid.is_valid():
			return false
		RenderingServer.instance_set_visible(instance_rid, value)
		return true
	push_warning("Unsupported light bool property for RenderingServer update: %s" % property_name)
	return false

func _apply_light_server_color(light: SpotLight3D, property_name: String, value: Color) -> bool:
	if property_name == "light_color":
		var light_rid: RID = _get_light_base_rid(light)
		if not light_rid.is_valid():
			return false
		RenderingServer.light_set_color(light_rid, value)
		return true
	push_warning("Unsupported light color property for RenderingServer update: %s" % property_name)
	return false

func _get_light_base_rid(light: SpotLight3D) -> RID:
	if light == null or not is_instance_valid(light):
		return RID()
	return light.get_base()

func _set_light_meta_float(light: SpotLight3D, meta_key: String, value: float, last_state: Dictionary) -> void:
	var cache_key: String = "meta:" + meta_key
	var previous: float = float(last_state.get(cache_key, INF))
	if _is_close_float(previous, value):
		_track_property_change(false)
		return
	last_state[cache_key] = value
	light.set_meta(meta_key, value)
	_track_property_change(true)

func _set_light_meta_variant(light: SpotLight3D, meta_key: String, value: Variant, last_state: Dictionary) -> void:
	var cache_key: String = "meta:" + meta_key
	if last_state.has(cache_key) and last_state[cache_key] == value:
		_track_property_change(false)
		return
	last_state[cache_key] = value
	light.set_meta(meta_key, value)
	_track_property_change(true)

func _resolve_zoom_beam_limits(light: SpotLight3D, controls: Dictionary) -> Dictionary:
	# min/max beam angles are kept as full GDTF beam apertures (not half-angle).
	var min_beam_angle: float = EMITTER_ZOOM_DEFAULT_MIN_BEAM_ANGLE_DEG
	var max_beam_angle: float = EMITTER_ZOOM_DEFAULT_MAX_BEAM_ANGLE_DEG
	var dimmer_controls: Dictionary = _resolve_dimmer_controls(controls)

	if bool(dimmer_controls.get("has_zoom_physical_limits", false)):
		min_beam_angle = float(dimmer_controls.get("zoom_physical_min_degrees", min_beam_angle))
		max_beam_angle = float(dimmer_controls.get("zoom_physical_max_degrees", max_beam_angle))
	else:
		var lens_radius: float = max(float(light.get_meta("peraviz_lens_radius", 0.0)), 0.0)
		if lens_radius > 0.0:
			var lens_angle: float = rad_to_deg(2.0 * atan(lens_radius / EMITTER_ZOOM_LENS_RANGE_REFERENCE_M))
			min_beam_angle = max(lens_angle, 0.1)

	if max_beam_angle < min_beam_angle:
		var swap_value: float = min_beam_angle
		min_beam_angle = max_beam_angle
		max_beam_angle = swap_value

	min_beam_angle = clamp(min_beam_angle, 0.1, EMITTER_LIGHT_MAX_BEAM_ANGLE_DEG)
	max_beam_angle = clamp(max_beam_angle, min_beam_angle, EMITTER_LIGHT_MAX_BEAM_ANGLE_DEG)
	return {
		"min_beam_angle": min_beam_angle,
		"max_beam_angle": max_beam_angle,
	}

func _create_emitter_beam_cone() -> MeshInstance3D:
	return _create_emitter_beam_cone_with_material("PeravizBeamCone", _create_emitter_beam_material())

func _create_emitter_beam_mid_cone() -> MeshInstance3D:
	return _create_emitter_beam_cone_with_material("PeravizBeamMidCone", _create_emitter_beam_mid_material())

func _create_emitter_beam_core_cone() -> MeshInstance3D:
	return _create_emitter_beam_cone_with_material("PeravizBeamCoreCone", _create_emitter_beam_core_material())

func _create_emitter_beam_cone_with_material(cone_name: String, material: ShaderMaterial) -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	cone.name = cone_name
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.visible = false
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.01
	cone_mesh.bottom_radius = 0.2
	cone_mesh.height = 1.0
	cone.mesh = cone_mesh
	cone.rotation_degrees.x = 90.0
	cone.material_override = material
	return cone

func _create_emitter_beam_material() -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_opaque;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

uniform vec4 base_color : source_color = vec4(1.0, 0.95, 0.85, 0.5);
uniform float falloff_power : hint_range(0.1, 10.0) = 8.0;

uniform float facing_boost : hint_range(0.0, 10.0) = 1.5;
uniform float facing_power : hint_range(0.1, 20.0) = 4.0;
uniform float boost_along_y : hint_range(0.0, 10.0) = 1.0;

uniform float feather_sharpness : hint_range(0.1, 20.0) = 4.0;
uniform float feather_intensity : hint_range(0.0, 1.0) = 1.0;

uniform float near_fade_start : hint_range(0.0, 50.0) = 0.01;
uniform float near_fade_end : hint_range(0.0, 50.0) = 1.0;
uniform float far_fade_start : hint_range(0.1, 100.0) = 25.0;
uniform float far_fade_end : hint_range(0.1, 100.0) = 80.0;

uniform float max_brightness : hint_range(1.0, 50.0) = 10.0;

uniform bool depth_feather_enabled = true;
uniform float depth_fade_distance : hint_range(0.01, 5.0) = 0.5;

varying vec3 vertex_view;

void vertex() {
	vertex_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(vertex_view, 1.0);
}

float get_linear_depth(float raw_depth, mat4 inv_proj_mat) {
	return 1.0 / (raw_depth * inv_proj_mat[2][3] + inv_proj_mat[3][3]);
}

void fragment() {
	float dist = length(vertex_view);

	float near_alpha = smoothstep(near_fade_start, near_fade_end, dist);
	float far_alpha = 1.0 - smoothstep(far_fade_start, far_fade_end, dist);
	float dist_fade = near_alpha * far_alpha;

	if (dist_fade < 0.001) discard;

	float apex_fade = pow(max(1.0 - UV.y, 0.001), falloff_power);
	float base_brightness = base_color.a * apex_fade;

	vec3 N = normalize(NORMAL);
	vec3 V = normalize(-vertex_view);
	float ndotv = max(0.0, dot(N, V));
	float location_weight = pow(max(1.0 - UV.y, 0.0), boost_along_y);
	float facing_multiplier = 1.0 + (facing_boost * location_weight * pow(ndotv, facing_power));

	float brightness = base_brightness * facing_multiplier;
	brightness = min(brightness, max_brightness);

	float feather_alpha = mix(1.0 - feather_intensity, 1.0, pow(ndotv, feather_sharpness));

	float depth_mult = 1.0;
	if (depth_feather_enabled) {
		float scene_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
		if (scene_depth < 0.9999) {
			float scene_linear = get_linear_depth(scene_depth, INV_PROJECTION_MATRIX);
			float frag_linear = -vertex_view.z;
			float diff = scene_linear - frag_linear;
			depth_mult = smoothstep(0.0, depth_fade_distance, diff);
		}
	}

	float final_alpha = feather_alpha * depth_mult * dist_fade;

	ALBEDO = base_color.rgb * brightness;
	ALPHA = clamp(final_alpha * base_color.a, 0.0, 1.0);

	if (ALPHA < 0.001) {
		ALBEDO = vec3(0.0);
	}
}
"""
	shader_material.shader = shader
	return shader_material

func _create_emitter_beam_mid_material() -> ShaderMaterial:
	return _create_emitter_beam_material()

func _create_emitter_beam_core_material() -> ShaderMaterial:
	return _create_emitter_beam_material()

func _update_emitter_beam_cone(light: SpotLight3D, beam_angle: float, beam_range: float, beam_color: Color, normalized_dimmer: float, gdtf_beam_radius: float = -1.0) -> void:
	if not light.has_meta("peraviz_beam_cone"):
		light.set_meta("peraviz_beam_cone", _create_emitter_beam_cone())
	if not light.has_meta("peraviz_beam_cone_mid"):
		light.set_meta("peraviz_beam_cone_mid", _create_emitter_beam_mid_cone())
	if not light.has_meta("peraviz_beam_cone_core"):
		light.set_meta("peraviz_beam_cone_core", _create_emitter_beam_core_cone())

	var cone: MeshInstance3D = light.get_meta("peraviz_beam_cone") as MeshInstance3D
	var mid_cone: MeshInstance3D = light.get_meta("peraviz_beam_cone_mid") as MeshInstance3D
	var core_cone: MeshInstance3D = light.get_meta("peraviz_beam_cone_core") as MeshInstance3D
	if cone == null and mid_cone == null and core_cone == null:
		return
	if cone != null and cone.get_parent() == null:
		light.add_child(cone)
	if mid_cone != null and mid_cone.get_parent() == null:
		light.add_child(mid_cone)
	if core_cone != null and core_cone.get_parent() == null:
		light.add_child(core_cone)

	var intensity: float = clamp(normalized_dimmer, 0.0, 1.0)
	light.set_meta("peraviz_beam_base_intensity", intensity)
	var beam_is_visible: bool = intensity > 0.015
	if cone != null:
		cone.visible = beam_is_visible
	if mid_cone != null:
		mid_cone.visible = beam_is_visible
	if core_cone != null:
		core_cone.visible = beam_is_visible

	var beam_multiplier: float = float(_visual_settings.get("beam_multiplier", 20.0))
	var scaled_intensity: float = clamp(intensity * beam_multiplier, 0.0, BEAM_INTENSITY_MAX)
	var beam_half_angle_deg: float = beam_angle * 0.5
	var radius: float = tan(deg_to_rad(beam_half_angle_deg)) * beam_range
	var lens_radius: float = max(float(light.get_meta("peraviz_lens_radius", 0.03)), 0.005)
	if gdtf_beam_radius > 0.0:
		lens_radius = max(gdtf_beam_radius, 0.005)
	var bottom_radius: float = clamp(radius, 0.03, EMITTER_CONE_MAX_BASE_RADIUS_M)

	_update_beam_cone_geometry(cone, lens_radius, bottom_radius, beam_range, 1.0)
	_update_beam_cone_geometry(mid_cone, lens_radius, bottom_radius, beam_range, 0.7)
	_update_beam_cone_geometry(core_cone, lens_radius, bottom_radius, beam_range, 0.45)

	var beam_color_with_alpha := Color(beam_color.r, beam_color.g, beam_color.b, 1.0)
	_update_beam_cone_material(cone, beam_color_with_alpha, scaled_intensity, beam_range, 1.0, 1.0)
	_update_beam_cone_material(mid_cone, beam_color_with_alpha, scaled_intensity, beam_range, 1.25, 1.25)
	_update_beam_cone_material(core_cone, beam_color_with_alpha, scaled_intensity, beam_range, 1.5, 1.5)

func _update_beam_cone_geometry(cone: MeshInstance3D, lens_radius: float, bottom_radius: float, beam_range: float, radius_scale: float) -> void:
	if cone == null:
		return
	var cone_mesh: CylinderMesh = cone.mesh as CylinderMesh
	if cone_mesh == null:
		return
	cone_mesh.top_radius = max(lens_radius * radius_scale, 0.003)
	cone_mesh.bottom_radius = clamp(bottom_radius * radius_scale, 0.02, EMITTER_CONE_MAX_BASE_RADIUS_M)
	cone_mesh.height = beam_range
	cone.position = Vector3(0.0, 0.0, -beam_range * 0.5)

func _update_beam_cone_material(cone: MeshInstance3D, beam_color: Color, scaled_intensity: float, beam_range: float, alpha_scale: float, brightness_scale: float) -> void:
	if cone == null:
		return
	var material: ShaderMaterial = cone.material_override as ShaderMaterial
	if material == null:
		return
	var intensity_alpha: float = lerp(0.0, 0.5 * alpha_scale, scaled_intensity)
	material.set_shader_parameter("base_color", Color(beam_color.r, beam_color.g, beam_color.b, intensity_alpha))
	material.set_shader_parameter("falloff_power", 8.0)
	material.set_shader_parameter("facing_boost", 1.5)
	material.set_shader_parameter("facing_power", 4.0)
	material.set_shader_parameter("boost_along_y", 1.0)
	material.set_shader_parameter("feather_sharpness", 4.0)
	material.set_shader_parameter("feather_intensity", 1.0)
	material.set_shader_parameter("near_fade_start", 0.01)
	material.set_shader_parameter("near_fade_end", min(max(1.0, beam_range * 0.04), 50.0))
	material.set_shader_parameter("far_fade_start", min(max(25.0, beam_range * 0.45), 100.0))
	material.set_shader_parameter("far_fade_end", min(max(80.0, beam_range * 0.9), 100.0))
	material.set_shader_parameter("depth_feather_enabled", true)
	material.set_shader_parameter("depth_fade_distance", 0.5)
	material.set_shader_parameter("max_brightness", lerp(1.0, 10.0 * brightness_scale, scaled_intensity))

func _derive_emitter_color(photometric: Dictionary, controls: Dictionary = {}, color_temperature_strength: float = 1.0) -> Color:
	var base_color: Color
	var cmy_filter: Dictionary = _resolve_cmy_filter(controls)
	if bool(cmy_filter.get("has_cmy", false)):
		# CMY color-mixing fixtures are expected to start from an approximately
		# white source. Using photometric color temperature as the base here can
		# bias the mix (e.g. weak red output on cool bases).
		base_color = Color.WHITE
	else:
		if bool(photometric.get("has_color_temperature", false)):
			base_color = _color_temperature_to_rgb(
				float(photometric.get("color_temperature", 6000.0)),
				clamp(color_temperature_strength, 0.0, 1.0)
			)
		else:
			# Keep default emitters visually neutral.
			# Dominant wavelength from photometrics is often too spectral/peaky for
			# runtime beam feedback and can introduce a persistent blue cast.
			base_color = Color.WHITE

	var filter_color: Color = cmy_filter.get("color", Color.WHITE)
	return Color(base_color.r * filter_color.r, base_color.g * filter_color.g, base_color.b * filter_color.b, 1.0)

func _resolve_cmy_filter(controls: Dictionary) -> Dictionary:
	var color_controls: Dictionary = _resolve_color_wheel_controls(controls)
	var cyan: float = clamp(float(color_controls.get("cyan_norm", 0.0)), 0.0, 1.0)
	var magenta: float = clamp(float(color_controls.get("magenta_norm", 0.0)), 0.0, 1.0)
	var yellow: float = clamp(float(color_controls.get("yellow_norm", 0.0)), 0.0, 1.0)
	var filter_color := Color(1.0 - cyan, 1.0 - magenta, 1.0 - yellow, 1.0)
	return {
		"color": filter_color,
		"has_cmy": cyan > 0.0001 or magenta > 0.0001 or yellow > 0.0001,
	}

func _color_temperature_to_rgb(temperature_kelvin: float, strength: float = 1.0) -> Color:
	var clamped_strength: float = clamp(strength, 0.0, 1.0)
	var clamped_temperature: float = clamp(temperature_kelvin, 1000.0, 12000.0)
	var warm_threshold_kelvin: float = 3200.0
	var cool_threshold_kelvin: float = 8500.0
	var warm_extreme_kelvin: float = 2000.0
	var cool_extreme_kelvin: float = 11000.0

	var warm_factor: float = inverse_lerp(warm_threshold_kelvin, warm_extreme_kelvin, clamped_temperature)
	var cool_factor: float = inverse_lerp(cool_threshold_kelvin, cool_extreme_kelvin, clamped_temperature)
	var extreme_factor: float = max(warm_factor, cool_factor)
	if extreme_factor <= 0.0 or clamped_strength <= 0.0:
		return Color.WHITE

	var t: float = clamped_temperature / 100.0
	var red: float
	var green: float
	var blue: float
	if t <= 66.0:
		red = 255.0
		green = 99.4708025861 * log(t) - 161.1195681661
		if t <= 19.0:
			blue = 0.0
		else:
			blue = 138.5177312231 * log(t - 10.0) - 305.0447927307
	else:
		red = 329.698727446 * pow(t - 60.0, -0.1332047592)
		green = 288.1221695283 * pow(t - 60.0, -0.0755148492)
		blue = 255.0
	var kelvin_color := Color(clamp(red / 255.0, 0.0, 1.0), clamp(green / 255.0, 0.0, 1.0), clamp(blue / 255.0, 0.0, 1.0))
	var tint_mix: float = clamp(extreme_factor * clamped_strength, 0.0, 1.0)
	return Color.WHITE.lerp(kelvin_color, tint_mix)

func _wavelength_to_rgb(wavelength_nm: float) -> Color:
	var wavelength: float = clamp(wavelength_nm, 380.0, 780.0)
	var red: float = 0.0
	var green: float = 0.0
	var blue: float = 0.0
	if wavelength < 440.0:
		red = -(wavelength - 440.0) / (440.0 - 380.0)
		blue = 1.0
	elif wavelength < 490.0:
		green = (wavelength - 440.0) / (490.0 - 440.0)
		blue = 1.0
	elif wavelength < 510.0:
		green = 1.0
		blue = -(wavelength - 510.0) / (510.0 - 490.0)
	elif wavelength < 580.0:
		red = (wavelength - 510.0) / (580.0 - 510.0)
		green = 1.0
	elif wavelength < 645.0:
		red = 1.0
		green = -(wavelength - 645.0) / (645.0 - 580.0)
	else:
		red = 1.0

	var factor: float = 1.0
	if wavelength < 420.0:
		factor = 0.3 + 0.7 * ((wavelength - 380.0) / (420.0 - 380.0))
	elif wavelength > 700.0:
		factor = 0.3 + 0.7 * ((780.0 - wavelength) / (780.0 - 700.0))
	return Color(clamp(red * factor, 0.0, 1.0), clamp(green * factor, 0.0, 1.0), clamp(blue * factor, 0.0, 1.0))

func _collect_emissive_materials_recursive(node: Node3D, output_materials: Array) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		for surface_index in range(mesh_instance.get_surface_override_material_count()):
			var override_material: Material = mesh_instance.get_surface_override_material(surface_index)
			_maybe_add_emissive_material(override_material, output_materials)
		if mesh_instance.material_override != null:
			_maybe_add_emissive_material(mesh_instance.material_override, output_materials)
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var mesh_material: Material = mesh_instance.mesh.surface_get_material(surface_index)
				_maybe_add_emissive_material(mesh_material, output_materials)

	for child in node.get_children():
		if child is Node3D:
			_collect_emissive_materials_recursive(child, output_materials)

func _maybe_add_emissive_material(material: Material, output_materials: Array) -> void:
	if material == null:
		return
	if not (material is BaseMaterial3D):
		return
	var base_material: BaseMaterial3D = material
	if output_materials.has(base_material):
		return
	if base_material.emission_enabled or base_material.emission != Color.BLACK:
		output_materials.append(base_material)

func _print_emitter_debug_vectors(fixture_uuid: String, reason: String, pan: float, tilt: float, dimmer: float) -> void:
	var emitter_nodes: Array = _to_node3d_array(_scene_registry.get_anchor(fixture_uuid, "emitters"))
	for emitter in emitter_nodes:
		var emitter_direction: Vector3 = (-emitter.global_basis.z).normalized()
		print("[PeravizFixtureTest] fixture=", fixture_uuid,
			" reason=", reason,
			" emitter=", emitter.name,
			" dir=", emitter_direction,
			" pan=", pan,
			" tilt=", tilt,
			" dimmer=", dimmer)

func _to_node3d_array(value: Variant) -> Array:
	var nodes: Array = []
	if value is Node3D:
		nodes.append(value)
		return nodes
	if value is Array:
		for item in value:
			if item is Node3D and is_instance_valid(item):
				nodes.append(item)
	return nodes

func _count_valid_nodes(value: Variant) -> int:
	if value is Node:
		return 1 if is_instance_valid(value) else 0
	if value is Array:
		var total: int = 0
		for item in value:
			total += _count_valid_nodes(item)
		return total
	return 0

func _resolve_fixture_uuid(node_id: String, parent_lookup: Dictionary, type_lookup: Dictionary, cache: Dictionary) -> String:
	if cache.has(node_id):
		return str(cache.get(node_id, ""))

	var node_type: String = str(type_lookup.get(node_id, ""))
	if node_type == "fixture":
		cache[node_id] = node_id
		return node_id

	var parent_id: String = str(parent_lookup.get(node_id, ""))
	if parent_id.is_empty() or parent_id == node_id:
		cache[node_id] = ""
		return ""

	var fixture_uuid: String = _resolve_fixture_uuid(parent_id, parent_lookup, type_lookup, cache)
	cache[node_id] = fixture_uuid
	return fixture_uuid

func _expand_loaded_bounds_from_node(node: Node3D) -> void:
	if node is MeshInstance3D:
		_expand_loaded_bounds(node)

	for child in node.get_children():
		if child is Node3D:
			_expand_loaded_bounds_from_node(child)

func _expand_loaded_bounds(mesh_instance: MeshInstance3D) -> void:
	var mesh_bounds: AABB = mesh_instance.get_aabb()
	var world_bounds: AABB = mesh_instance.global_transform * mesh_bounds
	if not _has_loaded_bounds:
		_loaded_bounds = world_bounds
		_has_loaded_bounds = true
		return

	_loaded_bounds = _loaded_bounds.merge(world_bounds)

func _focus_loaded_scene() -> void:
	if not _has_loaded_bounds:
		return

	if camera.has_method("focus_on_aabb"):
		camera.call("focus_on_aabb", _loaded_bounds)


func _setup_fixture_inspection_panel() -> void:
	if _fixture_inspection_panel != null and is_instance_valid(_fixture_inspection_panel):
		return
	if user_module == null:
		return
	_fixture_inspection_panel = FixtureInspectionPanelScript.new()
	_fixture_inspection_panel.name = "FixtureInspectionPanel"
	if dmx_controls_mount != null and dmx_controls_mount.get_parent() == user_module:
		user_module.add_child(_fixture_inspection_panel)
		user_module.move_child(_fixture_inspection_panel, dmx_controls_mount.get_index())
	else:
		user_module.add_child(_fixture_inspection_panel)
	_refresh_fixture_inspection_panel()

func _refresh_fixture_inspection_panel() -> void:
	if _fixture_inspection_panel == null or not is_instance_valid(_fixture_inspection_panel):
		return
	var rows: Array = []
	if _dmx_controller != null:
		rows = _dmx_controller.get_fixture_rows()
	_fixture_inspection_panel.refresh(rows)

func _clear_fixture_inspection_panel() -> void:
	if _fixture_inspection_panel == null or not is_instance_valid(_fixture_inspection_panel):
		return
	_fixture_inspection_panel.refresh([])

func _setup_dmx_controls() -> void:
	_dmx_controller.setup_controls()

func _resolve_dmx_controls_host() -> Control:
	if dmx_controls_mount != null and is_instance_valid(dmx_controls_mount):
		return dmx_controls_mount
	if app_shell != null and app_shell.has_method("get_modules_container"):
		return app_shell.get_modules_container() as Control
	return null

func bridge_set_side_panel_open(is_open: bool) -> void:
	if app_shell != null:
		app_shell.set_side_panel_open(is_open)

func bridge_set_active_section(section_name: StringName) -> void:
	if app_shell != null:
		app_shell.set_active_section(section_name)

func bridge_register_section(section_name: StringName, section_node: CanvasItem) -> void:
	if app_shell != null:
		app_shell.register_section(section_name, section_node)

func bridge_get_dmx_controls_host() -> Control:
	return _resolve_dmx_controls_host()

func bridge_setup_dmx_controls() -> void:
	_setup_dmx_controls()

func _setup_dmx_fixture_runtime() -> void:
	_dmx_controller.setup_fixture_runtime(_loader, _scene_registry, self, _fixture_row_provider)

func _refresh_dmx_fixture_bindings() -> void:
	var summary: Dictionary = _dmx_controller.refresh_fixture_bindings()
	_refresh_fixture_inspection_panel()
	var unbound_count: int = int(summary.get("unbound", 0))
	if _status_presenter != null and unbound_count > 0:
		_status_presenter.set_scene_state_warning_unbound(unbound_count)

func _process(delta: float) -> void:
	if _dmx_controller != null:
		_dmx_controller.process_dmx(delta)

func _exit_tree() -> void:
	_save_user_preferences()
	if _dmx_controller != null:
		_dmx_controller.exit_tree()

func _sync_selected_fixture_badge() -> void:
	if _status_presenter == null or _fixture_debug_controller == null:
		return
	var selected_fixture_uuid: String = _fixture_debug_controller.get_selected_fixture_uuid()
	if selected_fixture_uuid == _selected_fixture_badge_uuid:
		return
	_selected_fixture_badge_uuid = selected_fixture_uuid
	_status_presenter.set_selected_fixture_badge(selected_fixture_uuid)

func _on_dmx_status_changed(running: bool, receiving_signal: bool) -> void:
	if _status_presenter == null:
		return
	_status_presenter.set_dmx_badge(running, receiving_signal)

func _on_dmx_start_failed(error_message: String) -> void:
	if _status_presenter == null:
		return
	var message: String = "DMX start failed"
	if not error_message.is_empty():
		message = "%s (%s)" % [message, error_message]
	_status_presenter.show_toast(message)

func bridge_get_fixture_light_phase_metrics() -> Dictionary:
	if _fixture_light_apply_service == null:
		return {}
	return _fixture_light_apply_service.get_phase_metrics()

func bridge_record_dmx_decode_phase(elapsed_usec: int) -> void:
	if _fixture_light_apply_service == null:
		_fixture_light_apply_service = FixtureLightApplyServiceScript.new()
	_fixture_light_apply_service.record_dmx_decode_elapsed(elapsed_usec)
