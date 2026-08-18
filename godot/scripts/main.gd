extends Node3D

## Aim Trainer - Godot 客户端版
## 三种模式 / 3D 靶场 / 计分 / 管理员辅助功能，逻辑与网页版对齐。

const MODE_SIXSHOT := "sixshot"
const MODE_FOURSHOT := "fourshot"
const MODE_TRACKING := "tracking"
const MODE_GRIDSHOT := "gridshot"

const MODES := {
	MODE_SIXSHOT: {"name": "六目标", "count": 6, "color": Color(1.0, 0.42, 0.37), "score": 10, "delay": 0.4},
	MODE_FOURSHOT: {"name": "四目标", "count": 4, "color": Color(0.95, 0.55, 0.35), "score": 10, "delay": 0.5},
	MODE_TRACKING: {"name": "跟踪", "count": 1, "color": Color(0.31, 0.76, 1.0), "score": 25, "delay": 0.35},
	MODE_GRIDSHOT: {"name": "极速切换", "count": 1, "color": Color(1.0, 0.76, 0.3), "score": 15, "delay": 0.2}
}

const RAD_PER_PIXEL := deg_to_rad(0.07)
const PITCH_LIMIT := deg_to_rad(80.0)
const ADMIN_HASH := "3bacef24"

const GAME_YAW := {
	"瓦洛兰特": 0.0700,
	"CS2": 0.0220,
	"Apex": 0.0220,
	"守望先锋2": 0.0066,
	"彩虹六号": 0.0055,
	"使命召唤": 0.0066
}

const SMOOTH_PRESETS := {
	"responsive": [0.25, 16.0],
	"balanced": [0.1, 8.0],
	"stable": [0.05, 4.0]
}
const CLIENT_VERSION := "1.2.0"

var mode := MODE_SIXSHOT
var duration := 60
var size_mult := 1.0
var speed_mult := 1.0
var sens := 1.0
var fov_setting := 90.0
var crosshair_len := 7.0
var crosshair_gap := 12.0
var crosshair_thickness := 2.0
var crosshair_dot := 0.0
var crosshair_opacity := 1.0
var crosshair_color := Color(0.43, 0.91, 0.65)
var difficulty := "medium"
var count_mult := 1.0
var spawn_side := "front"
var smooth_mode := "balanced"
var control_mode := "lock"
var res_setting := "1280x1000"
var fullscreen := false
var stretch_display := false

var admin_unlocked := false
var triggerbot := false
var assist := false
var assist_fov := deg_to_rad(12.0)
var assist_strength := 0.4

var running := false
var paused := false
var finished := false
var time_left := 0.0
var kills := 0
var shots := 0.0
var hits := 0.0
var misses := 0
var score := 0
var start_real := 0.0
var reaction_total := 0.0
var reaction_count := 0
var aim_err_total := 0.0
var aim_err_count := 0
var flick_count := 0
var first_shots := 0
var first_hits := 0

var mouse_down := false
var dragging := false
var mouse_captured := false
var yaw := 0.0
var pitch := 0.0
var target_yaw := 0.0
var target_pitch := 0.0
var skip_until := 0
var first_move_after_lock := true
var last_auto_fire := 0
var last_hitmarker := 0

var cam: Camera3D
var viewmodel: Node3D
var recoil := 0.0
const VIEWMODEL_BASE := Vector3(0.28, -0.24, -0.55)
var preview_mode := false
var preview_captured := false
var preview_start_ms := 0
var calibrating := false
var calib_pixels := 0.0
var calib_recording := false
var calib_result := 0.0
var calibration_screen: Control
var calib_status: Label
var calib_result_label: Label
var calib_apply_btn: Button
var convert_screen: Control
var convert_src_opt: OptionButton
var convert_input: LineEdit
var convert_out: Label
var crosshair_screen: Control
var ch_sliders: Array = []
var ch_labels: Array = []
var sens_slider: HSlider
var sens_edit: LineEdit
var canvas: CanvasLayer
var blockers: Array[StaticBody3D] = []
var targets: Array = []
var target_bodies: Dictionary = {}
var cfg := ConfigFile.new()
var accounts_cfg := ConfigFile.new()
var current_user := ""
var auto_login := false
var saved_name := ""
var saved_pass := ""
var cloud_url := "http://123.207.58.61:3000"
var cloud_logged_in := false
var cloud_pass := ""
var cloud_best := {}
var http: HTTPRequest
var http_queue: Array = []
var http_busy := false
var http_action := ""
var pending_cloud := ""
var pending_name := ""
var pending_pass := ""
var login_screen: Control
var leaderboard_screen: Control
var user_label: Label
var new_user_input: LineEdit
var auto_login_cb: CheckBox
var lb_mode_opt: OptionButton
var lb_list: VBoxContainer
var login_pass_input: LineEdit
var login_msg: Label
var cloud_url_input: LineEdit
var cloud_login_btn: Button
var update_label: Label
var update_btn: Button

var hud: Control
var menu: Control
var pause_overlay: Control
var results: Control
var admin_panel: Control

var hud_timer: Label
var hud_score: Label
var hud_acc: Label
var hud_kills: Label
var hud_shots: Label
var hud_assist: Label
var hud_misses: Label
var crosshair_parts: Array = []
var fov_value_label: Label
var hitmarker_a: ColorRect
var hitmarker_b: ColorRect

var sounds := {}

func _ready() -> void:
	_load_accounts()
	_load_settings_from_cfg()
	_setup_3d()
	_setup_ui()
	preview_mode = OS.get_cmdline_user_args().has("--preview")
	if not preview_mode:
		_check_update()
	if preview_mode:
		_enter_preview()
	if not preview_mode and auto_login and saved_name != "" and saved_pass != "":
		_show_login()
		new_user_input.text = saved_name
		login_pass_input.text = saved_pass
		login_msg.text = "正在自动登录…"
		_cloud_login()
	else:
		_show_login()

func _load_accounts() -> void:
	accounts_cfg.load("user://accounts.cfg")
	auto_login = bool(accounts_cfg.get_value("accounts", "auto_login", false))
	saved_name = str(accounts_cfg.get_value("accounts", "saved_name", ""))
	saved_pass = str(accounts_cfg.get_value("accounts", "saved_pass", ""))
	cloud_url = str(accounts_cfg.get_value("accounts", "cloud_url", "http://123.207.58.61:3000"))

func _save_accounts() -> void:
	accounts_cfg.set_value("accounts", "auto_login", auto_login)
	accounts_cfg.set_value("accounts", "saved_name", saved_name)
	accounts_cfg.set_value("accounts", "saved_pass", saved_pass)
	accounts_cfg.set_value("accounts", "cloud_url", cloud_url)
	accounts_cfg.save("user://accounts.cfg")

func _load_settings_from_cfg() -> void:
	cfg = ConfigFile.new()
	cfg.load("user://settings.cfg")
	sens = float(cfg.get_value("settings", "sens", 1.0))
	fov_setting = clampf(float(cfg.get_value("settings", "fov", 90.0)), 70.0, 110.0)
	var old_size := str(cfg.get_value("settings", "crosshair_size", ""))
	if old_size == "small":
		crosshair_len = 5.0
		crosshair_gap = 8.0
		crosshair_thickness = 2.0
		crosshair_dot = 4.0
	elif old_size == "large":
		crosshair_len = 9.0
		crosshair_gap = 16.0
		crosshair_thickness = 3.0
		crosshair_dot = 8.0
	else:
		crosshair_len = 7.0
		crosshair_gap = 12.0
		crosshair_thickness = 2.0
		crosshair_dot = 0.0
	crosshair_len = clampf(float(cfg.get_value("settings", "ch_len", crosshair_len)), 3.0, 24.0)
	crosshair_gap = clampf(float(cfg.get_value("settings", "ch_gap", crosshair_gap)), 0.0, 32.0)
	crosshair_thickness = clampf(float(cfg.get_value("settings", "ch_thickness", crosshair_thickness)), 1.0, 6.0)
	crosshair_dot = clampf(float(cfg.get_value("settings", "ch_dot", crosshair_dot)), 0.0, 14.0)
	crosshair_opacity = clampf(float(cfg.get_value("settings", "ch_opacity", crosshair_opacity)), 0.1, 1.0)
	crosshair_color = cfg.get_value("settings", "crosshair_color", Color(0.43, 0.91, 0.65))
	difficulty = str(cfg.get_value("settings", "difficulty", "medium"))
	if difficulty not in ["easy", "medium", "hard", "expert", "custom"]:
		difficulty = "medium"
	count_mult = clampf(float(cfg.get_value("settings", "count_mult", 1.0)), 0.5, 2.0)
	duration = int(cfg.get_value("settings", "duration", 60))
	size_mult = clampf(float(cfg.get_value("settings", "size", 0.7)), 0.5, 1.0)
	speed_mult = float(cfg.get_value("settings", "speed", 1.0))
	spawn_side = str(cfg.get_value("settings", "side", "front"))
	if spawn_side not in ["front", "back", "left", "right", "all"]:
		spawn_side = "front"
	smooth_mode = str(cfg.get_value("settings", "smooth", "balanced"))
	control_mode = str(cfg.get_value("settings", "control", "lock"))
	res_setting = str(cfg.get_value("settings", "res", "1280x1000"))
	fullscreen = bool(cfg.get_value("settings", "fullscreen", false))
	stretch_display = bool(cfg.get_value("settings", "stretch", false))
	triggerbot = bool(cfg.get_value("admin", "triggerbot", false))
	assist = bool(cfg.get_value("admin", "assist", false))
	assist_fov = deg_to_rad(float(cfg.get_value("admin", "assist_fov", 12.0)))
	assist_strength = float(cfg.get_value("admin", "assist_strength", 0.4))
	admin_unlocked = bool(cfg.get_value("admin", "unlocked", false))

func _save_config() -> void:
	cfg.set_value("settings", "sens", sens)
	cfg.set_value("settings", "fov", fov_setting)
	cfg.set_value("settings", "ch_len", crosshair_len)
	cfg.set_value("settings", "ch_gap", crosshair_gap)
	cfg.set_value("settings", "ch_thickness", crosshair_thickness)
	cfg.set_value("settings", "ch_dot", crosshair_dot)
	cfg.set_value("settings", "ch_opacity", crosshair_opacity)
	cfg.set_value("settings", "crosshair_color", crosshair_color)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("settings", "count_mult", count_mult)
	cfg.set_value("settings", "duration", duration)
	cfg.set_value("settings", "size", size_mult)
	cfg.set_value("settings", "speed", speed_mult)
	cfg.set_value("settings", "side", spawn_side)
	cfg.set_value("settings", "smooth", smooth_mode)
	cfg.set_value("settings", "control", control_mode)
	cfg.set_value("settings", "res", res_setting)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("settings", "stretch", stretch_display)
	cfg.set_value("admin", "triggerbot", triggerbot)
	cfg.set_value("admin", "assist", assist)
	cfg.set_value("admin", "assist_fov", rad_to_deg(assist_fov))
	cfg.set_value("admin", "assist_strength", assist_strength)
	cfg.set_value("admin", "unlocked", admin_unlocked)
	cfg.save("user://settings.cfg")

# ---------------------------------------------------------------- 3D
func _setup_3d() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.07, 0.14)
	sky_mat.sky_horizon_color = Color(0.10, 0.16, 0.28)
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.05)
	sky_mat.ground_horizon_color = Color(0.08, 0.12, 0.20)
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.12, 0.20)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.25
	env_node.environment = env
	add_child(env_node)

	var hemi := DirectionalLight3D.new()
	hemi.rotation_degrees = Vector3(-55, -30, 0)
	hemi.light_color = Color(1, 0.95, 0.85)
	hemi.light_energy = 1.7
	hemi.shadow_enabled = true
	hemi.directional_shadow_max_distance = 80.0
	add_child(hemi)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 135, 0)
	fill.light_color = Color(0.35, 0.65, 1.0)
	fill.light_energy = 0.7
	add_child(fill)

	var amb := OmniLight3D.new()
	amb.position = Vector3(0, 6, 0)
	amb.light_color = Color(0.55, 0.65, 0.85)
	amb.light_energy = 0.9
	amb.omni_range = 40.0
	add_child(amb)
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 5, 0)
	probe.extents = Vector3(28, 8, 28)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

	cam = Camera3D.new()
	cam.fov = 90
	cam.near = 0.1
	cam.far = 200.0
	cam.position = Vector3(0, 1.6, 0)
	add_child(cam)
	cam.make_current()
	get_viewport().msaa_3d = Viewport.MSAA_2X
	viewmodel = Node3D.new()
	viewmodel.position = VIEWMODEL_BASE
	cam.add_child(viewmodel)
	var gun := _load_gun_mesh()
	if gun != null:
		viewmodel.add_child(gun)
	viewmodel.visible = false

	var floor_mat := _mat(Color(0.8, 0.85, 1.0), 0.85)
	floor_mat.albedo_texture = make_grid_texture()
	floor_mat.metallic = 0.1
	_add_box(Vector3(64, 0.2, 64), Vector3(0, -0.1, 0), floor_mat)
	var wall_mat := _mat(Color(0.10, 0.13, 0.19), 0.85)
	_add_box(Vector3(64, 14, 1), Vector3(0, 7, -32), wall_mat)
	_add_box(Vector3(64, 14, 1), Vector3(0, 7, 32), wall_mat)
	_add_box(Vector3(1, 14, 64), Vector3(-32, 7, 0), wall_mat)
	_add_box(Vector3(1, 14, 64), Vector3(32, 7, 0), wall_mat)
	_add_box(Vector3(64, 1, 64), Vector3(0, 14.5, 0), wall_mat)
	var pillar_mat := _mat(Color(0.14, 0.18, 0.25), 0.75)
	for p in [Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(-11, 0, 11), Vector3(11, 0, 11)]:
		_add_box(Vector3(2, 9, 2), p + Vector3(0, 4.5, 0), pillar_mat)

	var accent_mat := _mat(Color(0, 0, 0), 0.4)
	accent_mat.emission_enabled = true
	accent_mat.emission = Color(0.25, 0.75, 1.0)
	accent_mat.emission_energy_multiplier = 1.0
	for z in [-31.5, 31.5]:
		_add_deco(Vector3(64, 0.05, 0.08), Vector3(0, 0.03, z), accent_mat)
	for x in [-31.5, 31.5]:
		_add_deco(Vector3(0.08, 0.05, 64), Vector3(x, 0.03, 0), accent_mat)
	for p in [Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(-11, 0, 11), Vector3(11, 0, 11)]:
		_add_deco(Vector3(2.3, 0.08, 2.3), p + Vector3(0, 9.04, 0), accent_mat)

	for s in ["shot", "hit", "kill", "miss", "start", "end"]:
		var player := AudioStreamPlayer.new()
		add_child(player)
		sounds[s] = player

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

func _load_gun_mesh() -> Node3D:
	var gun_scene = load("res://assets/models/glock19/Glock-19.fbx")
	if gun_scene == null:
		return null
	var inst: Node3D = gun_scene.instantiate()
	_tune_gun_materials(inst)
	# 该 FBX 导入后枪口朝 +Z（玩家方向），翻转 180° 使枪口朝正前方
	inst.rotation_degrees = Vector3(0, 180, 0)
	var bb := _scene_aabb(inst)
	var max_dim := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var s := 1.0
	if max_dim > 0.001:
		s = 0.32 / max_dim
		inst.scale = Vector3(s, s, s)
	var center := (bb.position + bb.size * 0.5) * s
	inst.position = Vector3(0.06, -0.10, -0.18) - center
	return inst

func _tune_gun_materials(node: Node3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var mat: StandardMaterial3D = mi.get_active_material(0)
			if mat == null and mi.mesh != null:
				mat = mi.mesh.surface_get_material(0)
			if mat is StandardMaterial3D:
				mat.metallic = 0.6
				mat.roughness = 0.45
				mat.albedo_color = Color(0.55, 0.55, 0.62)
				if mat.normal_texture == null:
					var nt = load("res://assets/models/glock19/textures/mat0_n.png")
					if nt is Texture2D:
						mat.normal_enabled = true
						mat.normal_texture = nt
		elif child is Node3D:
			_tune_gun_materials(child)

func _scene_aabb(node: Node3D) -> AABB:
	var bb := AABB()
	var has := false
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if mi.mesh != null:
				var a := mi.mesh.get_aabb()
				var s := mi.scale
				var moved := AABB(a.position * s + child.position, a.size * s)
				if not has:
					bb = moved
					has = true
				else:
					bb = bb.merge(moved)
		elif child is Node3D:
			var sub := _scene_aabb(child)
			if sub.size.length() > 0.0:
				var s: Vector3 = child.scale
				var moved := AABB(sub.position * s + child.position, sub.size * s)
				if not has:
					bb = moved
					has = true
				else:
					bb = bb.merge(moved)
	return bb

func _add_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(mi)
	body.add_child(col)
	body.position = pos
	add_child(body)
	blockers.append(body)
	return body

func _add_deco(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func make_grid_texture() -> ImageTexture:
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.16, 0.22))
	for i in 8:
		var c := 64 * i
		for j in 512:
			img.set_pixel(j, c, Color(0.20, 0.28, 0.38))
			img.set_pixel(c, j, Color(0.20, 0.28, 0.38))
	return ImageTexture.create_from_image(img)

func make_glow_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 63.5
			var a := clampf(1.0 - d * d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

var glow_tex: ImageTexture

func make_target(color: Color) -> Dictionary:
	var r := 0.34 * size_mult
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24
	sm.rings = 18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.3
	mi.mesh = sm
	mi.material_override = mat
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = r
	col.shape = shape
	body.add_child(mi)
	body.add_child(col)
	var glow := Sprite3D.new()
	glow.texture = glow_tex
	# 光晕大小跟随靶子尺寸（约 2 倍靶子直径）
	glow.pixel_size = (r * 4.0) / 128.0
	glow.modulate = Color(color.r, color.g, color.b, 0.5)
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(glow)
	add_child(body)
	body.position = Vector3(0, -50, 0)
	mi.visible = false
	glow.visible = false
	var t := {
		"body": body, "mesh": mi, "glow": glow, "mat": mat, "radius": r,
		"alive": false, "respawn_at": 0.0, "hp": 100.0,
		"ang_y": 0.0, "ang_p": 0.0, "vy": 0.4, "vp": 0.3,
		"ang_y_min": -PI, "ang_y_max": PI, "pulse": randf() * TAU,
		"spawn_time": 0.0, "shot_done": false
	}
	target_bodies[body] = t
	targets.append(t)
	return t

func set_target_visible(t: Dictionary, vis: bool) -> void:
	t["alive"] = vis
	t["mesh"].visible = vis
	t["glow"].visible = vis

func random_target_pos(exclude: Dictionary) -> Vector3:
	for i in 24:
		var base_yaw := 0.0
		if spawn_side == "back":
			base_yaw = PI
		elif spawn_side == "left":
			base_yaw = PI / 2.0
		elif spawn_side == "right":
			base_yaw = -PI / 2.0
		var world_yaw := 0.0
		if spawn_side == "all":
			world_yaw = randf_range(-PI, PI)
		else:
			# 单面模式收窄到所选方向的正前方约 ±40°
			world_yaw = base_yaw + randf_range(-0.7, 0.7)
		var world_pitch := clampf(pitch + randf_range(-0.42, 0.42), -0.6, 0.85)
		var dir := Vector3(
			-sin(world_yaw) * cos(world_pitch),
			sin(world_pitch),
			-cos(world_yaw) * cos(world_pitch)
		)
		var dist := randf_range(5.5, 11.0)
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * dist)
		q.exclude = [exclude["body"].get_rid()]
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		var target_dist := dist
		if not res.is_empty() and res["position"].distance_to(cam.global_position) < dist - 0.6:
			target_dist = maxf(3.0, res["position"].distance_to(cam.global_position) - 0.6)
		var pos := cam.global_position + dir * target_dist
		pos.y = maxf(pos.y, 0.7)
		var ok := true
		for t in targets:
			if t["alive"] and t["body"].global_position.distance_to(pos) < 2.4:
				ok = false
				break
		if ok:
			return pos
	return Vector3.ZERO

func spawn_target(t: Dictionary) -> void:
	if mode == MODE_TRACKING:
		var base_yaw := 0.0
		if spawn_side == "back":
			base_yaw = PI
		elif spawn_side == "left":
			base_yaw = PI / 2.0
		elif spawn_side == "right":
			base_yaw = -PI / 2.0
		if spawn_side == "all":
			t["ang_y"] = randf_range(-PI, PI)
			t["ang_y_min"] = -PI
			t["ang_y_max"] = PI
		else:
			t["ang_y"] = base_yaw + randf_range(-0.6, 0.6)
			t["ang_y_min"] = base_yaw - 0.8
			t["ang_y_max"] = base_yaw + 0.8
		t["ang_p"] = clampf(pitch + randf_range(-0.2, 0.2), -0.1, 0.7)
		t["vy"] = randf_range(0.35, 0.85) * speed_mult * (1.0 if randf() < 0.5 else -1.0)
		t["vp"] = randf_range(0.25, 0.6) * speed_mult * (1.0 if randf() < 0.5 else -1.0)
		t["hp"] = 100.0
		place_tracking_target(t)
	else:
		var pos := random_target_pos(t)
		if pos == Vector3.ZERO:
			t["respawn_at"] = Time.get_ticks_msec() / 1000.0 + 0.3
			return
		t["body"].position = pos
	t["spawn_time"] = Time.get_ticks_msec() / 1000.0
	t["shot_done"] = false
	set_target_visible(t, true)

func place_tracking_target(t: Dictionary) -> void:
	var dir := Vector3(
		-sin(t["ang_y"]) * cos(t["ang_p"]),
		sin(t["ang_p"]),
		-cos(t["ang_y"]) * cos(t["ang_p"])
	)
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir * 10.0)
	q.exclude = [t["body"].get_rid()]
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var dist := 10.0
	if not res.is_empty() and res["position"].distance_to(cam.global_position) < 9.4:
		dist = maxf(3.0, res["position"].distance_to(cam.global_position) - 0.6)
	var pos := cam.global_position + dir * dist
	pos.y = maxf(pos.y, 0.7)
	t["body"].position = pos

func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return get_world_3d().direct_space_state.intersect_ray(q)

func _fire() -> void:
	if not running or paused:
		return
	shots += 1.0
	var is_first := shots == 1.0
	if is_first:
		first_shots += 1
	recoil = 1.0
	_play("shot")
	_record_shot_stats()
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 300.0
	var res := _raycast(from, to)
	if res.is_empty():
		misses += 1
		_play("miss")
	else:
		var t = target_bodies.get(res["collider"])
		if t != null and t["alive"]:
			if is_first:
				first_hits += 1
			hits += 1.0
			_show_hitmarker()
			_play("hit")
			_spawn_burst(res["position"], t["mat"].emission)
			_on_kill(t)
		else:
			misses += 1
			_play("miss")
	update_hud()

func _on_kill(t: Dictionary) -> void:
	kills += 1
	score += MODES[mode]["score"]
	t["respawn_at"] = Time.get_ticks_msec() / 1000.0 + MODES[mode]["delay"]
	set_target_visible(t, false)
	_play("kill")

func _update_assist(delta: float) -> void:
	if not assist:
		return
	var best: Dictionary = {}
	for t in targets:
		if not t["alive"]:
			continue
		var dir: Vector3 = (t["body"].global_position - cam.global_position).normalized()
		var ty := atan2(-dir.x, -dir.z)
		var tp := asin(clampf(dir.y, -1.0, 1.0))
		var dy := wrapf(ty - yaw, -PI, PI)
		var dp := tp - pitch
		var d := sqrt(dy * dy + dp * dp)
		if d <= assist_fov and (best.is_empty() or d < best["d"]):
			best = {"d": d, "dy": dy, "dp": dp}
	if best.is_empty():
		return
	var pull := assist_strength * minf(1.0, 10.0 * delta)
	target_yaw += best["dy"] * pull
	target_pitch += best["dp"] * pull
	target_pitch = clampf(target_pitch, -PITCH_LIMIT, PITCH_LIMIT)

func _update_tracking(delta: float) -> void:
	var t = targets[0]
	if not t["alive"]:
		return
	t["ang_y"] += t["vy"] * delta
	t["ang_p"] += t["vp"] * delta
	if t["ang_y"] > t["ang_y_max"] or t["ang_y"] < t["ang_y_min"]:
		t["vy"] *= -1.0
	if t["ang_p"] > 0.65 or t["ang_p"] < -0.1:
		t["vp"] *= -1.0
	t["ang_y"] = clampf(t["ang_y"], t["ang_y_min"], t["ang_y_max"])
	t["ang_p"] = clampf(t["ang_p"], -0.1, 0.65)
	place_tracking_target(t)
	var res := _raycast(cam.global_position, cam.global_position - cam.global_transform.basis.z * 300.0)
	var on_target := false
	if not res.is_empty():
		var hit = target_bodies.get(res["collider"])
		on_target = hit != null and hit["alive"] and hit["body"] == t["body"]
	var holding := mouse_down or (triggerbot and on_target)
	if holding:
		shots += delta
		if on_target:
			hits += delta
			t["hp"] -= 120.0 * delta
			if Time.get_ticks_msec() - last_hitmarker > 140:
				_show_hitmarker()
				last_hitmarker = Time.get_ticks_msec()
			if t["hp"] <= 0.0:
				_on_kill(t)
	update_hud()

# ---------------------------------------------------------------- 游戏流程
func start_round() -> void:
	mode = current_mode
	for t in targets:
		t["body"].queue_free()
	targets.clear()
	target_bodies.clear()
	var cfg_mode: Dictionary = MODES[mode]
	var target_count := 1 if mode == MODE_TRACKING else maxi(1, int(round(float(cfg_mode["count"]) * count_mult)))
	for i in target_count:
		make_target(cfg_mode["color"])
	for t in targets:
		spawn_target(t)
	kills = 0
	shots = 0.0
	hits = 0.0
	misses = 0
	score = 0
	reaction_total = 0.0
	reaction_count = 0
	aim_err_total = 0.0
	aim_err_count = 0
	flick_count = 0
	first_shots = 0
	first_hits = 0
	time_left = float(duration)
	running = true
	paused = false
	finished = false
	start_real = Time.get_ticks_msec() / 1000.0
	menu.visible = false
	results.visible = false
	hud.visible = true
	cam.fov = fov_setting
	if control_mode == "lock":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_play("start")
	update_hud()

func _enter_preview() -> void:
	start_round()
	hud.visible = false
	menu.visible = false
	login_screen.visible = false
	results.visible = false
	pause_overlay.visible = false
	yaw = -0.5
	pitch = -0.42
	target_yaw = yaw
	target_pitch = pitch
	preview_start_ms = Time.get_ticks_msec()
	print("辅助状态: 扳机=", triggerbot, " 吸附=", assist, " FOV=", rad_to_deg(assist_fov), " 强度=", assist_strength)

func end_round() -> void:
	running = false
	finished = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var elapsed := Time.get_ticks_msec() / 1000.0 - start_real
	var acc := 0
	if shots > 0.0:
		acc = int(round(hits / shots * 100.0))
	var avg := 0.0
	if kills > 0:
		avg = elapsed / float(kills)
	var react := 0
	if reaction_count > 0:
		react = int(round(reaction_total / float(reaction_count)))
	var aim_err := 0.0
	if aim_err_count > 0:
		aim_err = aim_err_total / float(aim_err_count)
	var first_acc := 0
	if mode != MODE_TRACKING and first_shots > 0:
		first_acc = int(round(first_hits / float(first_shots) * 100.0))
	var prev_best := int(cloud_best.get(mode, 0))
	var is_best := score > prev_best
	if cloud_logged_in and cloud_pass != "":
		pending_cloud = "score"
		_cloud_request("/api/score", {
			"name": current_user, "password": cloud_pass,
			"mode": mode, "score": score, "kills": kills, "acc": acc, "avg": avg, "react": react, "aim": aim_err, "first": first_acc
		})
	res_score_label.text = str(score)
	res_kills_label.text = str(kills)
	res_acc_label.text = str(acc) + "%"
	res_avg_label.text = "%.2f 秒" % avg if kills > 0 else "—"
	res_best_label.text = str(maxi(prev_best, score))
	res_newbest_label.text = "🎉 新纪录！" if is_best else ""
	res_kps_label.text = "%.2f" % (kills / elapsed if kills > 0 else 0.0)
	res_misses_label.text = str(misses) if mode != MODE_TRACKING else "—"
	res_react_label.text = ("%d ms" % react) if reaction_count > 0 else "—"
	res_aim_label.text = ("%.1f°" % aim_err) if aim_err_count > 0 else "—"
	res_flick_label.text = str(flick_count) if mode != MODE_TRACKING else "—"
	res_first_label.text = ("%d%%" % first_acc) if mode != MODE_TRACKING and first_shots > 0 else "—"
	var grade := "D"
	var grade_color := Color(0.9, 0.45, 0.4)
	if kills > 0:
		var expected := float({"sixshot": 45, "fourshot": 50, "tracking": 110, "gridshot": 100}[mode]) * float(duration) / 60.0
		var perf := float(acc) + 100.0 * clampf(float(kills) / expected, 0.0, 1.0)
		if perf >= 175.0:
			grade = "S"
			grade_color = Color(1.0, 0.84, 0.3)
		elif perf >= 150.0:
			grade = "A"
			grade_color = Color(0.35, 0.9, 0.5)
		elif perf >= 120.0:
			grade = "B"
			grade_color = Color(0.35, 0.75, 1.0)
		elif perf >= 85.0:
			grade = "C"
			grade_color = Color(1.0, 0.65, 0.3)
	res_grade_label.text = "评级 " + grade
	res_grade_label.add_theme_color_override("font_color", grade_color)
	hud.visible = false
	results.visible = true
	_play("end")

# ---------------------------------------------------------------- 输入
func _input(event: InputEvent) -> void:
	# 鼠标转动在 _input 处理：发生在界面层之前，确保任何 UI 都拦不住
	if calibrating:
		if event is InputEventMouseMotion and calib_recording:
			calib_pixels += absf(event.relative.x)
			var deg := calib_pixels * RAD_PER_PIXEL * sens * 180.0 / PI
			calib_status.text = "正在转动… 当前 %.0f°（约 180° 后松开）" % deg
		return
	if event is InputEventMouseMotion:
		if mouse_captured or (control_mode == "drag" and dragging):
			_apply_mouse(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if calibrating:
			if event.button_index == MOUSE_BUTTON_LEFT:
				calib_recording = event.pressed
				if not event.pressed:
					_finish_calibration()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_down = event.pressed
			if event.pressed and running and not paused and mode != MODE_TRACKING:
				if control_mode == "drag" or mouse_captured:
					_fire()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			_key_down(event.keycode)
		else:
			_key_up(event.keycode)

func _apply_mouse(rel: Vector2) -> void:
	if not running or paused:
		return
	if control_mode == "lock" and not mouse_captured:
		return
	if control_mode == "drag" and not dragging:
		return
	if Time.get_ticks_msec() < skip_until:
		return
	if first_move_after_lock:
		first_move_after_lock = false
		if absf(rel.x) > 120.0 or absf(rel.y) > 120.0:
			return
	target_yaw -= rel.x * RAD_PER_PIXEL * sens
	target_pitch -= rel.y * RAD_PER_PIXEL * sens
	target_pitch = clampf(target_pitch, -PITCH_LIMIT, PITCH_LIMIT)

func _key_down(code: Key) -> void:
	if calibrating:
		if code == KEY_ESCAPE:
			_close_calibration()
		return
	if code == KEY_ESCAPE:
		if running and not finished:
			paused = not paused
			if paused:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				pause_overlay.visible = true
			else:
				pause_overlay.visible = false
				if control_mode == "lock":
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				skip_until = Time.get_ticks_msec() + 120
				first_move_after_lock = true
		return
	if admin_unlocked:
		if code == KEY_F1:
			triggerbot = not triggerbot
			_save_config()
			_update_admin_state()
			update_hud()
			print("扳机 = ", triggerbot)
			return
		if code == KEY_F2:
			assist = not assist
			_save_config()
			_update_admin_state()
			update_hud()
			print("吸附 = ", assist)
			return
	if code == KEY_R:
		return
	if code == KEY_B:
		return
	if code == KEY_E:
		return

func _key_up(_code: Key) -> void:
	pass

func _resume_game() -> void:
	if not running or finished:
		return
	paused = false
	pause_overlay.visible = false
	if control_mode == "lock":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	skip_until = Time.get_ticks_msec() + 120
	first_move_after_lock = true

func _quit_to_menu() -> void:
	paused = false
	pause_overlay.visible = false
	running = false
	finished = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hud.visible = false
	menu.visible = true

func _process(delta: float) -> void:
	if preview_mode and not preview_captured and Time.get_ticks_msec() - preview_start_ms > 1000:
		preview_captured = true
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://preview.png")
		get_tree().quit()
	recoil = maxf(0.0, recoil - 4.0 * delta)
	if viewmodel != null:
		viewmodel.visible = running and not paused and not finished
		viewmodel.position = VIEWMODEL_BASE + Vector3(0, 0, recoil * 0.06)
		viewmodel.rotation.x = recoil * 0.05
	var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if captured != mouse_captured:
		mouse_captured = captured
		if mouse_captured:
			skip_until = Time.get_ticks_msec() + 120
			first_move_after_lock = true
			target_yaw = yaw
			target_pitch = pitch
		elif running and not finished and not paused and control_mode == "lock":
			paused = true
			pause_overlay.visible = true

	if running and not paused:
		time_left -= delta
		if mode == MODE_TRACKING:
			_update_tracking(delta)
		if triggerbot and mode != MODE_TRACKING:
			var now_ms := Time.get_ticks_msec()
			if now_ms - last_auto_fire > 200:
				var res := _raycast(cam.global_position, cam.global_position - cam.global_transform.basis.z * 300.0)
				if not res.is_empty():
					var t = target_bodies.get(res["collider"])
					if t != null and t["alive"]:
						last_auto_fire = now_ms
						_fire()
		var now := Time.get_ticks_msec() / 1000.0
		for t in targets:
			if not t["alive"] and now >= t["respawn_at"]:
				spawn_target(t)
			elif t["alive"]:
				t["mat"].emission_energy_multiplier = 0.45 + 0.25 * (0.5 + 0.5 * sin(now * 4.0 + t["pulse"]))
		_update_assist(delta)
		_update_camera(delta)
		update_hud()
		if time_left <= 0.0:
			time_left = 0.0
			end_round()
	elif not running:
		_update_camera(delta)
		cam.rotation.y = yaw
		cam.rotation.x = pitch

func _update_camera(delta: float) -> void:
	var p: Array = SMOOTH_PRESETS[smooth_mode]
	var max_turn := minf(p[0], p[1] * delta)
	yaw += clampf(target_yaw - yaw, -max_turn, max_turn)
	pitch += clampf(target_pitch - pitch, -max_turn, max_turn)
	cam.rotation.y = yaw
	cam.rotation.x = pitch

# ---------------------------------------------------------------- 音效与特效
func _make_tone(freq: float, dur: float, vol: float = 0.3) -> AudioStreamWAV:
	var rate := 22050
	var count := int(dur * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var env := exp(-6.0 * t / dur)
		var s := sin(TAU * freq * t) * vol * env
		var v := int(clampf(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

func _play(sound_name: String) -> void:
	var p: AudioStreamPlayer = sounds.get(sound_name)
	if p == null:
		return
	if sound_name == "shot":
		p.stream = _make_tone(320, 0.08, 0.25)
	elif sound_name == "hit":
		p.stream = _make_tone(880, 0.07, 0.3)
	elif sound_name == "kill":
		p.stream = _make_tone(1040, 0.1, 0.3)
	elif sound_name == "miss":
		p.stream = _make_tone(160, 0.1, 0.2)
	elif sound_name == "start":
		p.stream = _make_tone(520, 0.1, 0.3)
	elif sound_name == "end":
		p.stream = _make_tone(440, 0.2, 0.3)
	p.play()

func _spawn_burst(pos: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = 12
	p.lifetime = 0.35
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.gravity = Vector3(0, -4, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	p.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	p.material_override = mat
	add_child(p)
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- UI

func _setup_ui() -> void:
	glow_tex = make_glow_texture()
	canvas = CanvasLayer.new()
	add_child(canvas)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "微软雅黑", "Noto Sans CJK SC", "sans-serif"])
	theme.default_font = font

	# ---------- 菜单 ----------
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.theme = theme
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(300, 5)
	panel.size = Vector2(680, 990)
	menu.add_child(panel)

	var title := Label.new()
	title.text = "AIM TRAINER"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(0, 24)
	title.size = Vector2(680, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.31, 0.76, 1.0))
	panel.add_child(title)

	var sub := Label.new()
	sub.text = "Godot 客户端版 · 四目标/六目标/跟踪/极速切换 · 灵敏度校准"
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.position = Vector2(0, 78)
	sub.size = Vector2(680, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	panel.add_child(sub)
	user_label = _add_label(panel, "当前用户：", 15, Vector2(420, 26), Vector2(240, 30), HORIZONTAL_ALIGNMENT_RIGHT)

	var y := 120
	_add_label(panel, "选择模式", 16, Vector2(40, y), Vector2(600, 26))
	y += 34
	for m in [MODE_SIXSHOT, MODE_FOURSHOT, MODE_TRACKING, MODE_GRIDSHOT]:
		var btn := Button.new()
		btn.text = MODES[m]["name"]
		var idx := [MODE_SIXSHOT, MODE_FOURSHOT, MODE_TRACKING, MODE_GRIDSHOT].find(m)
		btn.position = Vector2(40 + idx * 155, y)
		btn.size = Vector2(150, 52)
		btn.toggle_mode = true
		btn.button_pressed = (m == current_mode)
		btn.pressed.connect(_on_mode_btn.bind(m, btn))
		panel.add_child(btn)
		mode_buttons[m] = btn
	y += 64

	_add_label(panel, "训练设置", 16, Vector2(40, y), Vector2(600, 26))
	y += 34
	_add_select(panel, "时长", ["30 秒", "60 秒", "120 秒"], _index_of([30, 60, 120], duration), Vector2(40, y), _on_duration)
	y += 40
	_add_label(panel, "难度预设", 14, Vector2(40, y), Vector2(90, 32))
	diff_opt = OptionButton.new()
	diff_opt.position = Vector2(130, y)
	diff_opt.size = Vector2(120, 36)
	for d_name in ["简单", "中等", "困难", "专家", "自定义"]:
		diff_opt.add_item(d_name)
	diff_opt.select({"easy": 0, "medium": 1, "hard": 2, "expert": 3, "custom": 4}[difficulty])
	diff_opt.item_selected.connect(_on_difficulty)
	panel.add_child(diff_opt)
	_add_label(panel, "靶子大小", 14, Vector2(280, y), Vector2(80, 32))
	size_opt = OptionButton.new()
	size_opt.position = Vector2(360, y)
	size_opt.size = Vector2(110, 36)
	for sz_name in ["小", "中", "大"]:
		size_opt.add_item(sz_name)
	size_opt.select(_index_of([0.5, 0.7, 1.0], size_mult))
	size_opt.item_selected.connect(_on_size)
	panel.add_child(size_opt)
	_add_label(panel, "移动速度", 14, Vector2(490, y), Vector2(80, 32))
	speed_opt = OptionButton.new()
	speed_opt.position = Vector2(565, y)
	speed_opt.size = Vector2(100, 36)
	for sp_name in ["慢", "中", "快"]:
		speed_opt.add_item(sp_name)
	speed_opt.select(_index_of([0.6, 1.0, 1.6], speed_mult))
	speed_opt.item_selected.connect(_on_speed)
	panel.add_child(speed_opt)
	y += 40
	_add_select(panel, "生成方向", ["前方（单面）", "后方", "左方", "右方", "环绕（多面）"], {"front": 0, "back": 1, "left": 2, "right": 3, "all": 4}[spawn_side], Vector2(40, y), _on_side)
	y += 40
	_add_select(panel, "视角控制", ["锁定（点击锁定鼠标）", "拖拽（按住右键转动）"], 0 if control_mode == "lock" else 1, Vector2(40, y), _on_control)
	y += 40
	_add_select(panel, "视角平滑", ["跟手", "平衡", "稳定"], {"responsive": 0, "balanced": 1, "stable": 2}[smooth_mode], Vector2(40, y), _on_smooth)
	y += 40
	_add_sens_row(panel, y)
	y += 48
	_add_label(panel, "视野 (FOV)", 14, Vector2(40, y), Vector2(160, 32))
	var cam_fov_slider := _slider(70, 110, 1, fov_setting, Vector2(210, y), Vector2(260, 32))
	cam_fov_slider.value_changed.connect(_on_fov)
	panel.add_child(cam_fov_slider)
	fov_value_label = _add_label(panel, "%d°" % int(fov_setting), 14, Vector2(480, y), Vector2(60, 32))
	y += 40
	_add_label(panel, "分辨率", 14, Vector2(40, y), Vector2(90, 32))
	var res_opt := OptionButton.new()
	res_opt.position = Vector2(130, y)
	res_opt.size = Vector2(170, 36)
	for r in ["1280×720", "1280×1000", "1920×1080", "2560×1440", "1024×768"]:
		res_opt.add_item(r)
	res_opt.select({"1280x720": 0, "1280x1000": 1, "1920x1080": 2, "2560x1440": 3, "1024x768": 4}[res_setting])
	res_opt.item_selected.connect(_on_resolution)
	panel.add_child(res_opt)
	var fs_cb := CheckBox.new()
	fs_cb.text = "全屏"
	fs_cb.button_pressed = fullscreen
	fs_cb.position = Vector2(320, y)
	fs_cb.size = Vector2(80, 36)
	fs_cb.toggled.connect(_on_fullscreen)
	panel.add_child(fs_cb)
	var st_cb := CheckBox.new()
	st_cb.text = "真实拉伸"
	st_cb.button_pressed = stretch_display
	st_cb.position = Vector2(410, y)
	st_cb.size = Vector2(130, 36)
	st_cb.toggled.connect(_on_stretch)
	panel.add_child(st_cb)
	y += 40
	var ch_btn := Button.new()
	ch_btn.text = "准星设置"
	ch_btn.position = Vector2(40, y)
	ch_btn.size = Vector2(140, 36)
	ch_btn.pressed.connect(_open_crosshair_editor)
	panel.add_child(ch_btn)
	_add_label(panel, "颜色", 14, Vector2(220, y), Vector2(60, 32))
	var cc_opt := OptionButton.new()
	cc_opt.position = Vector2(280, y)
	cc_opt.size = Vector2(110, 36)
	var color_names := ["绿", "黄", "红", "白", "青"]
	var colors := [Color(0.43, 0.91, 0.65), Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.4), Color(1, 1, 1), Color(0.3, 0.85, 1.0)]
	var color_idx := 0
	for j in colors.size():
		cc_opt.add_item(color_names[j])
		if colors[j].is_equal_approx(crosshair_color):
			color_idx = j
	cc_opt.select(color_idx)
	cc_opt.item_selected.connect(_on_crosshair_color.bind(colors))
	panel.add_child(cc_opt)
	y += 40

	var start_btn := Button.new()
	start_btn.text = "开始训练"
	start_btn.position = Vector2(40, y)
	start_btn.size = Vector2(430, 54)
	start_btn.pressed.connect(start_round)
	panel.add_child(start_btn)
	var calib_btn := Button.new()
	calib_btn.text = "灵敏度校准"
	calib_btn.position = Vector2(480, y)
	calib_btn.size = Vector2(160, 54)
	calib_btn.pressed.connect(_open_calibration)
	panel.add_child(calib_btn)
	y += 64

	var admin_btn := Button.new()
	admin_btn.text = "管理员"
	admin_btn.position = Vector2(40, y)
	admin_btn.size = Vector2(130, 34)
	admin_btn.pressed.connect(_toggle_admin_login)
	panel.add_child(admin_btn)
	admin_btn_node = admin_btn
	var lb_btn := Button.new()
	lb_btn.text = "排行榜"
	lb_btn.position = Vector2(185, y)
	lb_btn.size = Vector2(130, 34)
	lb_btn.pressed.connect(_show_leaderboard)
	panel.add_child(lb_btn)
	var switch_btn := Button.new()
	switch_btn.text = "切换用户"
	switch_btn.position = Vector2(330, y)
	switch_btn.size = Vector2(130, 34)
	switch_btn.pressed.connect(_logout)
	panel.add_child(switch_btn)
	var conv_btn := Button.new()
	conv_btn.text = "灵敏度换算"
	conv_btn.position = Vector2(475, y)
	conv_btn.size = Vector2(165, 34)
	conv_btn.pressed.connect(_open_converter)
	panel.add_child(conv_btn)

	admin_login = Control.new()
	admin_login.position = Vector2(40, y + 40)
	admin_login.size = Vector2(600, 40)
	admin_login.visible = false
	panel.add_child(admin_login)
	var pass_edit := LineEdit.new()
	pass_edit.name = "admin_pass"
	pass_edit.placeholder_text = "管理员密码"
	pass_edit.secret = true
	pass_edit.position = Vector2(0, 0)
	pass_edit.size = Vector2(340, 36)
	pass_edit.text_submitted.connect(_on_admin_submit)
	admin_login.add_child(pass_edit)
	var pass_ok := Button.new()
	pass_ok.text = "确认"
	pass_ok.position = Vector2(350, 0)
	pass_ok.size = Vector2(90, 36)
	pass_ok.pressed.connect(_on_admin_submit.bind(""))
	admin_login.add_child(pass_ok)
	admin_msg = Label.new()
	admin_msg.name = "admin_msg"
	admin_msg.position = Vector2(0, 40)
	admin_msg.size = Vector2(600, 24)
	admin_msg.add_theme_color_override("font_color", Color(1.0, 0.48, 0.43))
	admin_login.add_child(admin_msg)

	admin_panel = Control.new()
	admin_panel.position = Vector2(40, y + 70)
	admin_panel.size = Vector2(600, 180)
	admin_panel.visible = false
	panel.add_child(admin_panel)
	var tb := CheckBox.new()
	tb.text = "自动开枪（扳机）"
	tb.button_pressed = triggerbot
	tb.position = Vector2(0, 0)
	tb.toggled.connect(_on_triggerbot)
	admin_panel.add_child(tb)
	var ab := CheckBox.new()
	ab.text = "瞄准辅助（吸附）"
	ab.button_pressed = assist
	ab.position = Vector2(0, 36)
	ab.toggled.connect(_on_assist)
	admin_panel.add_child(ab)
	admin_state_label = _add_label(admin_panel, "", 14, Vector2(0, 60), Vector2(560, 24))
	var fov_slider := _slider(5, 30, 1, rad_to_deg(assist_fov), Vector2(0, 76), Vector2(420, 30))
	fov_slider.value_changed.connect(_on_assist_fov)
	admin_panel.add_child(fov_slider)
	assist_fov_label = _add_label(admin_panel, "辅助范围 %d°" % int(rad_to_deg(assist_fov)), 14, Vector2(430, 76), Vector2(160, 30))
	var st_slider := _slider(0.1, 0.8, 0.05, assist_strength, Vector2(0, 116), Vector2(420, 30))
	st_slider.value_changed.connect(_on_assist_strength)
	admin_panel.add_child(st_slider)
	assist_strength_label = _add_label(admin_panel, "辅助强度 %d%%" % int(assist_strength * 100), 14, Vector2(430, 116), Vector2(160, 30))
	var exit_btn := Button.new()
	exit_btn.text = "退出管理员"
	exit_btn.position = Vector2(0, 136)
	exit_btn.size = Vector2(200, 36)
	exit_btn.pressed.connect(_on_admin_exit)
	admin_panel.add_child(exit_btn)
	if admin_unlocked:
		admin_panel.visible = true

	# ---------- 登录 / 用户 ----------
	login_screen = Control.new()
	login_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	login_screen.theme = theme
	login_screen.visible = false
	canvas.add_child(login_screen)
	var login_bg := ColorRect.new()
	login_bg.color = Color(0.02, 0.03, 0.05, 0.96)
	login_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	login_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	login_screen.add_child(login_bg)
	var login_panel := Panel.new()
	login_panel.position = Vector2(390, 90)
	login_panel.size = Vector2(500, 540)
	login_screen.add_child(login_panel)
	_add_label(login_panel, "云端账号登录", 26, Vector2(0, 24), Vector2(500, 40), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(login_panel, "服务器地址", 14, Vector2(40, 80), Vector2(160, 26))
	cloud_url_input = LineEdit.new()
	cloud_url_input.text = cloud_url
	cloud_url_input.placeholder_text = "服务器地址"
	cloud_url_input.position = Vector2(180, 78)
	cloud_url_input.size = Vector2(280, 36)
	login_panel.add_child(cloud_url_input)
	_add_label(login_panel, "用户名", 14, Vector2(40, 130), Vector2(160, 26))
	new_user_input = LineEdit.new()
	new_user_input.placeholder_text = "输入用户名（最多 12 字）"
	new_user_input.max_length = 12
	new_user_input.position = Vector2(180, 128)
	new_user_input.size = Vector2(280, 36)
	new_user_input.text_submitted.connect(_cloud_login)
	login_panel.add_child(new_user_input)
	_add_label(login_panel, "密码", 14, Vector2(40, 180), Vector2(160, 26))
	login_pass_input = LineEdit.new()
	login_pass_input.placeholder_text = "输入密码"
	login_pass_input.secret = true
	login_pass_input.position = Vector2(180, 178)
	login_pass_input.size = Vector2(280, 36)
	login_pass_input.text_submitted.connect(_cloud_login)
	login_panel.add_child(login_pass_input)
	cloud_login_btn = Button.new()
	cloud_login_btn.text = "登录 / 注册"
	cloud_login_btn.position = Vector2(40, 240)
	cloud_login_btn.size = Vector2(420, 48)
	cloud_login_btn.pressed.connect(_cloud_login)
	login_panel.add_child(cloud_login_btn)
	auto_login_cb = CheckBox.new()
	auto_login_cb.text = "自动登录（本机记住账号和密码）"
	auto_login_cb.button_pressed = auto_login
	auto_login_cb.position = Vector2(40, 310)
	auto_login_cb.toggled.connect(_on_auto_login)
	login_panel.add_child(auto_login_cb)
	login_msg = _add_label(login_panel, "", 13, Vector2(40, 350), Vector2(420, 26))
	login_msg.add_theme_color_override("font_color", Color(1.0, 0.48, 0.43))
	update_label = _add_label(login_panel, "", 13, Vector2(40, 430), Vector2(420, 26))
	update_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	update_btn = Button.new()
	update_btn.text = "去下载新版本"
	update_btn.position = Vector2(40, 458)
	update_btn.size = Vector2(200, 38)
	update_btn.visible = false
	update_btn.pressed.connect(_download_update)
	login_panel.add_child(update_btn)
	_add_label(login_panel, "账号、成绩和排行榜全部保存在服务器", 13, Vector2(40, 390), Vector2(420, 30))

	# ---------- 排行榜 ----------
	leaderboard_screen = Control.new()
	leaderboard_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	leaderboard_screen.theme = theme
	leaderboard_screen.visible = false
	canvas.add_child(leaderboard_screen)
	var lb_bg := ColorRect.new()
	lb_bg.color = Color(0.02, 0.03, 0.05, 0.96)
	lb_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaderboard_screen.add_child(lb_bg)
	var lb_panel := Panel.new()
	lb_panel.position = Vector2(340, 70)
	lb_panel.size = Vector2(600, 660)
	leaderboard_screen.add_child(lb_panel)
	_add_label(lb_panel, "排行榜", 28, Vector2(0, 24), Vector2(600, 44), HORIZONTAL_ALIGNMENT_CENTER)
	lb_mode_opt = OptionButton.new()
	lb_mode_opt.position = Vector2(40, 84)
	lb_mode_opt.size = Vector2(220, 36)
	lb_mode_opt.add_item("六目标")
	lb_mode_opt.add_item("四目标")
	lb_mode_opt.add_item("跟踪")
	lb_mode_opt.add_item("极速切换")
	lb_mode_opt.select(0)
	lb_mode_opt.item_selected.connect(_refresh_leaderboard)
	lb_panel.add_child(lb_mode_opt)
	lb_list = VBoxContainer.new()
	lb_list.position = Vector2(40, 140)
	lb_list.size = Vector2(520, 440)
	lb_panel.add_child(lb_list)
	var lb_back := Button.new()
	lb_back.text = "返回"
	lb_back.position = Vector2(240, 590)
	lb_back.size = Vector2(120, 42)
	lb_back.pressed.connect(_close_leaderboard)
	lb_panel.add_child(lb_back)

	# ---------- 灵敏度校准 ----------
	calibration_screen = Control.new()
	calibration_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	calibration_screen.theme = theme
	calibration_screen.visible = false
	canvas.add_child(calibration_screen)
	var calib_bg := ColorRect.new()
	calib_bg.color = Color(0.02, 0.03, 0.05, 0.96)
	calib_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	calib_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calibration_screen.add_child(calib_bg)
	var calib_panel := Panel.new()
	calib_panel.position = Vector2(320, 100)
	calib_panel.size = Vector2(640, 520)
	calibration_screen.add_child(calib_panel)
	_add_label(calib_panel, "灵敏度校准（180° 甩动）", 26, Vector2(0, 26), Vector2(640, 44), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(calib_panel, "用一次自然、完整的甩动从身体一侧甩到另一侧（约 180°）。", 15, Vector2(40, 96), Vector2(560, 30))
	_add_label(calib_panel, "点击开始后鼠标锁定，按住左键甩动，松开后自动计算建议灵敏度。", 15, Vector2(40, 126), Vector2(560, 30))
	calib_status = _add_label(calib_panel, "准备就绪", 22, Vector2(40, 196), Vector2(560, 40), HORIZONTAL_ALIGNMENT_CENTER)
	calib_result_label = _add_label(calib_panel, "", 18, Vector2(40, 256), Vector2(560, 60), HORIZONTAL_ALIGNMENT_CENTER)
	var calib_start := Button.new()
	calib_start.text = "开始校准"
	calib_start.position = Vector2(60, 360)
	calib_start.size = Vector2(200, 50)
	calib_start.pressed.connect(_start_calibration)
	calib_panel.add_child(calib_start)
	calib_apply_btn = Button.new()
	calib_apply_btn.text = "使用建议值"
	calib_apply_btn.position = Vector2(280, 360)
	calib_apply_btn.size = Vector2(200, 50)
	calib_apply_btn.disabled = true
	calib_apply_btn.pressed.connect(_apply_calibration)
	calib_panel.add_child(calib_apply_btn)
	var calib_back := Button.new()
	calib_back.text = "返回"
	calib_back.position = Vector2(500, 360)
	calib_back.size = Vector2(100, 50)
	calib_back.pressed.connect(_close_calibration)
	calib_panel.add_child(calib_back)

	# ---------- 灵敏度换算 ----------
	convert_screen = Control.new()
	convert_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	convert_screen.theme = theme
	convert_screen.visible = false
	canvas.add_child(convert_screen)
	var conv_bg := ColorRect.new()
	conv_bg.color = Color(0.02, 0.03, 0.05, 0.96)
	conv_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	conv_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	convert_screen.add_child(conv_bg)
	var conv_panel := Panel.new()
	conv_panel.position = Vector2(320, 90)
	conv_panel.size = Vector2(640, 600)
	convert_screen.add_child(conv_panel)
	_add_label(conv_panel, "多游戏灵敏度换算", 26, Vector2(0, 24), Vector2(640, 44), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(conv_panel, "按各游戏标准角度系数换算，保持 cm/360 一致，结果仅供参考。", 14, Vector2(40, 78), Vector2(560, 30))
	_add_label(conv_panel, "来源游戏", 15, Vector2(40, 128), Vector2(160, 32))
	convert_src_opt = OptionButton.new()
	convert_src_opt.position = Vector2(200, 126)
	convert_src_opt.size = Vector2(220, 36)
	for g in GAME_YAW:
		convert_src_opt.add_item(g)
	convert_src_opt.select(0)
	convert_src_opt.item_selected.connect(_on_convert_src)
	conv_panel.add_child(convert_src_opt)
	_add_label(conv_panel, "灵敏度", 15, Vector2(40, 178), Vector2(160, 32))
	convert_input = LineEdit.new()
	convert_input.text = "1.000"
	convert_input.position = Vector2(200, 176)
	convert_input.size = Vector2(220, 36)
	convert_input.text_submitted.connect(_on_convert_text)
	conv_panel.add_child(convert_input)
	convert_out = _add_label(conv_panel, "", 15, Vector2(40, 236), Vector2(560, 300))
	var conv_back := Button.new()
	conv_back.text = "返回"
	conv_back.position = Vector2(270, 540)
	conv_back.size = Vector2(120, 44)
	conv_back.pressed.connect(_close_converter)
	conv_panel.add_child(conv_back)

	# ---------- 准星编辑器 ----------
	crosshair_screen = Control.new()
	crosshair_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair_screen.theme = theme
	crosshair_screen.visible = false
	canvas.add_child(crosshair_screen)
	var ch_bg := ColorRect.new()
	ch_bg.color = Color(0.02, 0.03, 0.05, 0.96)
	ch_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ch_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_screen.add_child(ch_bg)
	var ch_panel := Panel.new()
	ch_panel.position = Vector2(320, 80)
	ch_panel.size = Vector2(640, 640)
	crosshair_screen.add_child(ch_panel)
	_add_label(ch_panel, "准星设置", 26, Vector2(0, 24), Vector2(640, 44), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(ch_panel, "实时预览", 14, Vector2(40, 78), Vector2(120, 26))
	var ch_preview := Control.new()
	ch_preview.position = Vector2(160, 70)
	ch_preview.size = Vector2(460, 140)
	ch_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch_panel.add_child(ch_preview)
	ch_preview_parts.clear()
	var pd := ColorRect.new()
	pd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch_preview.add_child(pd)
	ch_preview_parts.append(pd)
	for i in 4:
		var pb := ColorRect.new()
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch_preview.add_child(pb)
		ch_preview_parts.append(pb)
	_style_crosshair(ch_preview_parts, crosshair_gap, crosshair_dot, crosshair_thickness, crosshair_len, crosshair_opacity, crosshair_color)
	var ch_rows := [
		["长度", 3, 24, 1, crosshair_len, "%d"],
		["间隙", 0, 32, 1, crosshair_gap, "%d"],
		["粗细", 1, 6, 1, crosshair_thickness, "%d"],
		["中心点", 0, 14, 1, crosshair_dot, "%d"],
		["透明度", 10, 100, 5, crosshair_opacity * 100.0, "%d%%"]
	]
	var ch_y := 220
	for ci in ch_rows.size():
		var crow: Array = ch_rows[ci]
		_add_label(ch_panel, str(crow[0]), 14, Vector2(40, ch_y), Vector2(160, 32))
		var cs := _slider(float(crow[1]), float(crow[2]), float(crow[3]), float(crow[4]), Vector2(200, ch_y), Vector2(300, 32))
		cs.value_changed.connect(_on_ch_slider.bind(ci))
		ch_panel.add_child(cs)
		ch_sliders.append(cs)
		var cl := _add_label(ch_panel, "", 14, Vector2(520, ch_y), Vector2(80, 32))
		ch_labels.append(cl)
		ch_y += 40
	_sync_crosshair_ui()
	var ch_reset := Button.new()
	ch_reset.text = "重置默认"
	ch_reset.position = Vector2(80, 560)
	ch_reset.size = Vector2(180, 48)
	ch_reset.pressed.connect(_reset_crosshair)
	ch_panel.add_child(ch_reset)
	var ch_done := Button.new()
	ch_done.text = "完成"
	ch_done.position = Vector2(380, 560)
	ch_done.size = Vector2(180, 48)
	ch_done.pressed.connect(_close_crosshair_editor)
	ch_panel.add_child(ch_done)

	# ---------- HUD ----------
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.visible = false
	hud.theme = theme
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	hud_timer = _add_label(hud, "60.0", 40, Vector2(560, 12), Vector2(160, 60), HORIZONTAL_ALIGNMENT_CENTER)
	hud_score = _add_label(hud, "0", 40, Vector2(740, 12), Vector2(120, 60), HORIZONTAL_ALIGNMENT_CENTER)
	hud_score.add_theme_color_override("font_color", Color(0.31, 0.76, 1.0))
	hud_kills = _add_label(hud, "击杀 0", 16, Vector2(480, 70), Vector2(320, 30), HORIZONTAL_ALIGNMENT_CENTER)
	hud_acc = _add_label(hud, "命中率 0%", 16, Vector2(480, 96), Vector2(160, 30), HORIZONTAL_ALIGNMENT_CENTER)
	hud_shots = _add_label(hud, "射击 0", 16, Vector2(640, 96), Vector2(160, 30), HORIZONTAL_ALIGNMENT_CENTER)
	hud_misses = _add_label(hud, "未中 0", 16, Vector2(640, 70), Vector2(160, 30), HORIZONTAL_ALIGNMENT_CENTER)
	hud_first = _add_label(hud, "首枪 —", 16, Vector2(820, 96), Vector2(180, 30), HORIZONTAL_ALIGNMENT_CENTER)
	hud_assist = _add_label(hud, "", 15, Vector2(20, 850), Vector2(400, 30))
	hud_assist.add_theme_color_override("font_color", Color(1.0, 0.76, 0.3))
	var ch := Control.new()
	ch.set_anchors_preset(Control.PRESET_CENTER)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ch)
	crosshair_parts.clear()
	var dot := ColorRect.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(dot)
	crosshair_parts.append(dot)
	for i in 4:
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.add_child(bar)
		crosshair_parts.append(bar)
	apply_crosshair()
	hitmarker_a = ColorRect.new()
	hitmarker_a.color = Color(1, 1, 1)
	hitmarker_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker_a.position = Vector2(-1, -14)
	hitmarker_a.size = Vector2(2, 28)
	hitmarker_a.pivot_offset = Vector2(1, 14)
	hitmarker_a.rotation = deg_to_rad(45)
	hitmarker_a.visible = false
	ch.add_child(hitmarker_a)
	hitmarker_b = ColorRect.new()
	hitmarker_b.color = Color(1, 1, 1)
	hitmarker_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker_b.position = Vector2(-1, -14)
	hitmarker_b.size = Vector2(2, 28)
	hitmarker_b.pivot_offset = Vector2(1, 14)
	hitmarker_b.rotation = deg_to_rad(-45)
	hitmarker_b.visible = false
	ch.add_child(hitmarker_b)

	pause_overlay = Control.new()
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	pause_overlay.theme = theme
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(pause_overlay)
	var pause_bg := ColorRect.new()
	pause_bg.color = Color(0, 0, 0, 0.6)
	pause_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(pause_bg)
	_add_label(pause_overlay, "已暂停", 30, Vector2(440, 300), Vector2(400, 60), HORIZONTAL_ALIGNMENT_CENTER)
	var resume_btn := Button.new()
	resume_btn.text = "继续"
	resume_btn.position = Vector2(560, 380)
	resume_btn.size = Vector2(160, 50)
	resume_btn.pressed.connect(_resume_game)
	pause_overlay.add_child(resume_btn)
	var quit_btn := Button.new()
	quit_btn.text = "退出"
	quit_btn.position = Vector2(560, 445)
	quit_btn.size = Vector2(160, 50)
	quit_btn.pressed.connect(_quit_to_menu)
	pause_overlay.add_child(quit_btn)

	results = Control.new()
	results.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.visible = false
	results.theme = theme
	results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(results)
	var res_bg := ColorRect.new()
	res_bg.color = Color(0.02, 0.03, 0.05, 0.94)
	res_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	res_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	results.add_child(res_bg)
	var res_panel := Panel.new()
	res_panel.position = Vector2(390, 80)
	res_panel.size = Vector2(500, 760)
	results.add_child(res_panel)
	_add_label(res_panel, "训练完成", 28, Vector2(0, 22), Vector2(500, 40), HORIZONTAL_ALIGNMENT_CENTER)
	res_grade_label = _add_label(res_panel, "", 44, Vector2(0, 66), Vector2(500, 56), HORIZONTAL_ALIGNMENT_CENTER)
	res_newbest_label = _add_label(res_panel, "", 16, Vector2(0, 126), Vector2(500, 26), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(res_panel, "得分", 14, Vector2(40, 170), Vector2(120, 24))
	res_score_label = _add_label(res_panel, "", 24, Vector2(40, 194), Vector2(120, 36))
	_add_label(res_panel, "击杀", 14, Vector2(210, 170), Vector2(120, 24))
	res_kills_label = _add_label(res_panel, "", 24, Vector2(210, 194), Vector2(120, 36))
	_add_label(res_panel, "命中率", 14, Vector2(380, 170), Vector2(120, 24))
	res_acc_label = _add_label(res_panel, "", 24, Vector2(380, 194), Vector2(120, 36))
	_add_label(res_panel, "平均每杀", 14, Vector2(40, 260), Vector2(180, 24))
	res_avg_label = _add_label(res_panel, "", 22, Vector2(40, 284), Vector2(180, 36))
	_add_label(res_panel, "最佳成绩", 14, Vector2(280, 260), Vector2(180, 24))
	res_best_label = _add_label(res_panel, "", 22, Vector2(280, 284), Vector2(180, 36))
	_add_label(res_panel, "击杀/秒", 14, Vector2(40, 350), Vector2(180, 24))
	res_kps_label = _add_label(res_panel, "", 22, Vector2(40, 374), Vector2(180, 36))
	_add_label(res_panel, "未命中", 14, Vector2(280, 350), Vector2(180, 24))
	res_misses_label = _add_label(res_panel, "", 22, Vector2(280, 374), Vector2(180, 36))
	_add_label(res_panel, "平均反应", 14, Vector2(40, 440), Vector2(180, 24))
	res_react_label = _add_label(res_panel, "", 22, Vector2(40, 464), Vector2(180, 36))
	_add_label(res_panel, "平均偏差", 14, Vector2(280, 440), Vector2(180, 24))
	res_aim_label = _add_label(res_panel, "", 22, Vector2(280, 464), Vector2(180, 36))
	_add_label(res_panel, "大幅拉枪", 14, Vector2(40, 530), Vector2(180, 24))
	res_flick_label = _add_label(res_panel, "", 22, Vector2(40, 554), Vector2(180, 36))
	_add_label(res_panel, "首枪命中", 14, Vector2(280, 530), Vector2(180, 24))
	res_first_label = _add_label(res_panel, "", 22, Vector2(280, 554), Vector2(180, 36))
	var again := Button.new()
	again.text = "再来一次"
	again.position = Vector2(60, 640)
	again.size = Vector2(180, 50)
	again.pressed.connect(start_round)
	res_panel.add_child(again)
	var back := Button.new()
	back.text = "返回菜单"
	back.position = Vector2(260, 640)
	back.size = Vector2(180, 50)
	back.pressed.connect(_back_to_menu)
	res_panel.add_child(back)
	_apply_display()

var current_mode := MODE_SIXSHOT
var mode_buttons := {}
var admin_btn_node: Button
var admin_login: Control
var admin_msg: Label
var admin_state_label: Label
var assist_fov_label: Label
var assist_strength_label: Label
var res_score_label: Label
var res_kills_label: Label
var res_acc_label: Label
var res_avg_label: Label
var res_best_label: Label
var res_newbest_label: Label
var res_kps_label: Label
var res_misses_label: Label
var res_react_label: Label
var res_aim_label: Label
var res_flick_label: Label
var res_first_label: Label
var res_grade_label: Label
var hud_first: Label
var diff_opt: OptionButton
var size_opt: OptionButton
var speed_opt: OptionButton
var ch_preview_parts: Array = []

func _add_label(parent: Control, text: String, font_size: int, pos: Vector2, size: Vector2, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func _add_select(parent: Control, title: String, items: Array, selected: int, pos: Vector2, cb: Callable) -> void:
	_add_label(parent, title, 14, pos, Vector2(180, 32))
	var opt := OptionButton.new()
	opt.position = pos + Vector2(190, 0)
	opt.size = Vector2(240, 36)
	for it in items:
		opt.add_item(it)
	opt.select(selected)
	opt.item_selected.connect(cb)
	parent.add_child(opt)

func _slider(min_v: float, max_v: float, step: float, value: float, pos: Vector2, size: Vector2) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.position = pos
	s.size = size
	return s

func _add_sens_row(parent: Control, y: int) -> void:
	_add_label(parent, "灵敏度（无畏契约）", 14, Vector2(40, y), Vector2(180, 32))
	var slider := _slider(0.05, 10.0, 0.001, sens, Vector2(230, y), Vector2(240, 32))
	sens_slider = slider
	slider.value_changed.connect(_on_sens_slider)
	parent.add_child(slider)
	var edit := LineEdit.new()
	sens_edit = edit
	edit.text = "%.3f" % sens
	edit.position = Vector2(480, y)
	edit.size = Vector2(90, 34)
	edit.text_submitted.connect(_on_sens_text)
	parent.add_child(edit)

func _index_of(arr: Array, value: Variant) -> int:
	return arr.find(value) if arr.find(value) >= 0 else 0

# ---------------------------------------------------------------- UI 回调
func _on_mode_btn(m: String, _btn: Button) -> void:
	current_mode = m
	for key in mode_buttons:
		mode_buttons[key].button_pressed = (key == m)

func _on_duration(idx: int) -> void:
	duration = [30, 60, 120][idx]
	_save_config()

func _on_size(idx: int) -> void:
	size_mult = [0.5, 0.7, 1.0][idx]
	if difficulty != "custom":
		difficulty = "custom"
		if diff_opt != null:
			diff_opt.select(4)
	_save_config()

func _on_speed(idx: int) -> void:
	speed_mult = [0.6, 1.0, 1.6][idx]
	if difficulty != "custom":
		difficulty = "custom"
		if diff_opt != null:
			diff_opt.select(4)
	_save_config()

func _on_side(idx: int) -> void:
	spawn_side = ["front", "back", "left", "right", "all"][idx]
	_save_config()

func _on_control(idx: int) -> void:
	control_mode = "lock" if idx == 0 else "drag"
	_save_config()

func _on_smooth(idx: int) -> void:
	smooth_mode = ["responsive", "balanced", "stable"][idx]
	_save_config()

func _on_sens_slider(v: float) -> void:
	sens = clampf(v, 0.05, 10.0)
	if sens_edit != null:
		sens_edit.text = "%.3f" % sens
	_save_config()

func _on_sens_text(text: String) -> void:
	var v := float(text)
	if is_finite(v) and v > 0.0:
		sens = clampf(v, 0.05, 10.0)
		if sens_slider != null:
			sens_slider.value = sens
		_save_config()

func _on_fov(v: float) -> void:
	fov_setting = v
	fov_value_label.text = "%d°" % int(v)
	if cam != null:
		cam.fov = v
	_save_config()

func _on_difficulty(idx: int) -> void:
	difficulty = ["easy", "medium", "hard", "expert", "custom"][idx]
	if difficulty != "custom":
		var presets := {
			"easy": [1.0, 0.6, 0.5],
			"medium": [0.7, 1.0, 1.0],
			"hard": [0.5, 1.4, 1.5],
			"expert": [0.5, 1.8, 2.0]
		}
		var p: Array = presets[difficulty]
		size_mult = p[0]
		speed_mult = p[1]
		count_mult = p[2]
		if size_opt != null:
			size_opt.select(_index_of([0.5, 0.7, 1.0], size_mult))
		if speed_opt != null:
			speed_opt.select(_index_of([0.6, 1.0, 1.6], speed_mult))
	_save_config()

func _on_crosshair_color(idx: int, colors: Array) -> void:
	crosshair_color = colors[idx]
	apply_crosshair()
	_save_config()

func _toggle_admin_login() -> void:
	if admin_unlocked:
		admin_panel.visible = true
	else:
		admin_login.visible = not admin_login.visible
		admin_msg.text = ""

func _on_admin_submit(_text: String) -> void:
	var edit := admin_login.get_node("admin_pass") as LineEdit
	if hash_str(edit.text) == ADMIN_HASH:
		admin_unlocked = true
		_save_config()
		admin_login.visible = false
		admin_panel.visible = true
		admin_msg.text = ""
		edit.text = ""
		print("管理员解锁成功")
	else:
		admin_msg.text = "密码错误"

func _on_admin_exit() -> void:
	admin_unlocked = false
	_save_config()
	admin_panel.visible = false

func _on_triggerbot(on: bool) -> void:
	triggerbot = on
	_save_config()
	_update_admin_state()
	print("扳机 = ", triggerbot)

func _on_assist(on: bool) -> void:
	assist = on
	_save_config()
	_update_admin_state()
	print("吸附 = ", assist)

func _update_admin_state() -> void:
	if admin_state_label == null:
		return
	admin_state_label.text = "当前状态：扳机 %s · 吸附 %s" % ["开" if triggerbot else "关", "开" if assist else "关"]

func _on_assist_fov(v: float) -> void:
	assist_fov = deg_to_rad(v)
	assist_fov_label.text = "辅助范围 %d°" % int(v)
	_save_config()

func _on_assist_strength(v: float) -> void:
	assist_strength = v
	assist_strength_label.text = "辅助强度 %d%%" % int(v * 100)
	_save_config()

func _back_to_menu() -> void:
	results.visible = false
	menu.visible = true

# ---------- 用户系统 ----------
func _show_login() -> void:
	login_screen.visible = true
	menu.visible = false
	cloud_url_input.text = cloud_url
	login_msg.text = ""

func _enter_app(user_name: String) -> void:
	current_user = user_name
	user_label.text = "当前用户：" + user_name
	login_screen.visible = false
	menu.visible = true
	_update_admin_state()

func _logout() -> void:
	current_user = ""
	cloud_logged_in = false
	cloud_pass = ""
	_show_login()

func _on_auto_login(on: bool) -> void:
	auto_login = on
	if not auto_login:
		saved_pass = ""
	_save_accounts()

func _cloud_request(path: String, payload: Dictionary) -> void:
	http_queue.append({"path": path, "payload": payload, "post": true, "action": pending_cloud})
	_http_pump()

func _cloud_get(path: String) -> void:
	http_queue.append({"path": path, "payload": {}, "post": false, "action": pending_cloud})
	_http_pump()

func _http_pump() -> void:
	if http_busy or http_queue.is_empty():
		return
	if http == null:
		http = HTTPRequest.new()
		http.timeout = 10.0
		add_child(http)
		http.request_completed.connect(_on_cloud_response)
	var item: Dictionary = http_queue.pop_front()
	http_busy = true
	http_action = str(item.get("action", ""))
	var err := OK
	if item.get("post", false):
		err = http.request(cloud_url + str(item["path"]), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(item["payload"]))
	else:
		err = http.request(cloud_url + str(item["path"]), [], HTTPClient.METHOD_GET)
	if err != OK:
		http_busy = false
		login_msg.text = "无法连接服务器"
		_http_pump()

func _check_update() -> void:
	pending_cloud = "version"
	_cloud_get("/api/version")

func _download_update() -> void:
	OS.shell_open(cloud_url + "/download/aim-trainer.zip")

func _cloud_login(_text: String = "") -> void:
	var user_name := new_user_input.text.strip_edges()
	var password := login_pass_input.text
	if user_name == "" or password == "":
		login_msg.text = "请输入昵称和密码"
		return
	pending_name = user_name
	pending_pass = password
	pending_cloud = "login"
	_cloud_request("/api/login", {"name": user_name, "password": password})

func _on_cloud_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var data := {}
	if text != "":
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	if http_action == "login":
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.get("ok", false):
			_cloud_login_ok(pending_name, pending_pass, data)
		else:
			var err := str(data.get("error", "登录失败"))
			if err.contains("用户名或密码错误"):
				pending_cloud = "register"
				_cloud_request("/api/register", {"name": pending_name, "password": pending_pass})
			else:
				login_msg.text = err
	elif http_action == "register":
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.get("ok", false):
			_cloud_login_ok(pending_name, pending_pass, {})
		else:
			login_msg.text = str(data.get("error", "注册失败"))
	elif http_action == "score":
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			cloud_best[mode] = int(data.get("best", cloud_best.get(mode, 0)))
	elif http_action == "version":
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var v := str(data.get("version", ""))
			if v != "" and v != CLIENT_VERSION:
				update_label.text = "发现新版本 v%s（当前 v%s）" % [v, CLIENT_VERSION]
				update_btn.visible = true
	elif http_action == "leaderboard":
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_fill_cloud_leaderboard(data)
		else:
			login_msg.text = ""
			for child in lb_list.get_children():
				child.queue_free()
			var l := Label.new()
			l.text = "无法连接服务器"
			l.add_theme_font_size_override("font_size", 18)
			lb_list.add_child(l)
	http_busy = false
	_http_pump()

func _cloud_login_ok(user_name: String, password: String, data: Dictionary) -> void:
	cloud_logged_in = true
	cloud_pass = password
	var best_variant = data.get("best", {})
	cloud_best = best_variant if typeof(best_variant) == TYPE_DICTIONARY else {}
	saved_name = user_name
	if auto_login:
		saved_pass = password
	else:
		saved_pass = ""
	_save_accounts()
	login_msg.text = "云端登录成功：" + user_name
	_enter_app(user_name)

func _show_leaderboard() -> void:
	leaderboard_screen.visible = true
	_refresh_leaderboard(lb_mode_opt.selected)

func _close_leaderboard() -> void:
	leaderboard_screen.visible = false

func _refresh_leaderboard(idx: int) -> void:
	for child in lb_list.get_children():
		child.queue_free()
	var mode_key: String = [MODE_SIXSHOT, MODE_FOURSHOT, MODE_TRACKING, MODE_GRIDSHOT][idx]
	if not cloud_logged_in:
		var need_login := Label.new()
		need_login.text = "请先登录云端账号"
		need_login.add_theme_font_size_override("font_size", 18)
		lb_list.add_child(need_login)
		return
	pending_cloud = "leaderboard"
	var loading := Label.new()
	loading.text = "加载中…"
	loading.add_theme_font_size_override("font_size", 18)
	lb_list.add_child(loading)
	_cloud_get("/api/leaderboard?mode=" + mode_key)

func _fill_cloud_leaderboard(data: Dictionary) -> void:
	for child in lb_list.get_children():
		child.queue_free()
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		var l := Label.new()
		l.text = "暂无成绩"
		l.add_theme_font_size_override("font_size", 18)
		lb_list.add_child(l)
		return
	for i in mini(entries.size(), 10):
		var e: Dictionary = entries[i]
		var l := Label.new()
		l.text = "%d.  %s    %d 分" % [i + 1, str(e.get("name", "?")), int(e.get("score", 0))]
		l.add_theme_font_size_override("font_size", 18)
		lb_list.add_child(l)

func hash_str(s: String) -> String:
	var h := 5381
	for i in s.length():
		h = ((h << 5) + h) ^ s.unicode_at(i)
	return "%x" % (h & 0xFFFFFFFF)

func _show_hitmarker() -> void:
	hitmarker_a.visible = true
	hitmarker_b.visible = true
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(_hide_hitmarker)

func _hide_hitmarker() -> void:
	hitmarker_a.visible = false
	hitmarker_b.visible = false

func apply_crosshair() -> void:
	_style_crosshair(crosshair_parts, crosshair_gap, crosshair_dot, crosshair_thickness, crosshair_len, crosshair_opacity, crosshair_color)
	if ch_preview_parts.size() >= 5:
		_style_crosshair(ch_preview_parts, crosshair_gap, crosshair_dot, crosshair_thickness, crosshair_len, crosshair_opacity, crosshair_color)

func _style_crosshair(parts: Array, gap: float, dot_size: float, bar_w: float, bar_len: float, opacity: float, color: Color) -> void:
	if parts.is_empty():
		return
	var dot: ColorRect = parts[0]
	if dot_size > 0.5:
		dot.position = Vector2(-dot_size / 2.0, -dot_size / 2.0)
		dot.size = Vector2(dot_size, dot_size)
		dot.visible = true
	else:
		dot.visible = false
	for i in 4:
		var bar: ColorRect = parts[i + 1]
		if i < 2:
			bar.size = Vector2(bar_w, bar_len)
			bar.position = Vector2(-bar_w / 2.0, -gap - bar_len) if i == 0 else Vector2(-bar_w / 2.0, gap)
		else:
			bar.size = Vector2(bar_len, bar_w)
			bar.position = Vector2(-gap - bar_len, -bar_w / 2.0) if i == 2 else Vector2(gap, -bar_w / 2.0)
	for part in parts:
		part.color = Color(color.r, color.g, color.b, opacity)

func update_hud() -> void:
	if hud_timer == null:
		return
	hud_timer.text = "%.1f" % maxf(time_left, 0.0)
	hud_score.text = str(score)
	var acc := 0
	if shots > 0.0:
		acc = int(round(hits / shots * 100.0))
	hud_acc.text = "命中率 %d%%" % acc
	hud_kills.text = "击杀 %d" % kills
	hud_shots.text = ("射击 %d" % int(shots)) if mode != MODE_TRACKING else ("射击 %.1f s" % shots)
	hud_misses.text = "未中 " + (str(misses) if mode != MODE_TRACKING else "—")
	if mode != MODE_TRACKING and first_shots > 0:
		hud_first.text = "首枪 %d%%" % int(round(first_hits / float(first_shots) * 100.0))
	else:
		hud_first.text = "首枪 —"
	var parts := []
	if triggerbot:
		parts.append("扳机")
	if assist:
		parts.append("吸附")
	hud_assist.text = "辅助: " + ("、".join(PackedStringArray(parts)) if not parts.is_empty() else "关")

# ---------------------------------------------------------------- 新增功能（v1.1.0）
func _record_shot_stats() -> void:
	if mode == MODE_TRACKING:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var best_d := TAU
	var best_t: Dictionary = {}
	for t in targets:
		if not t["alive"]:
			continue
		var dir: Vector3 = (t["body"].global_position - cam.global_position).normalized()
		var ty := atan2(-dir.x, -dir.z)
		var tp := asin(clampf(dir.y, -1.0, 1.0))
		var d := sqrt(pow(wrapf(ty - yaw, -PI, PI), 2.0) + pow(tp - pitch, 2.0))
		if d < best_d:
			best_d = d
			best_t = t
	if best_d >= TAU:
		return
	aim_err_total += rad_to_deg(best_d)
	aim_err_count += 1
	if best_d > deg_to_rad(6.0):
		flick_count += 1
	if not best_t["shot_done"]:
		best_t["shot_done"] = true
		reaction_total += maxf(0.0, now - float(best_t["spawn_time"])) * 1000.0
		reaction_count += 1

# ---------------------------------------------------------------- 准星编辑器（v1.2.0）
func _open_crosshair_editor() -> void:
	_sync_crosshair_ui()
	apply_crosshair()
	crosshair_screen.visible = true

func _close_crosshair_editor() -> void:
	crosshair_screen.visible = false

func _reset_crosshair() -> void:
	crosshair_len = 7.0
	crosshair_gap = 12.0
	crosshair_thickness = 2.0
	crosshair_dot = 0.0
	crosshair_opacity = 1.0
	_sync_crosshair_ui()
	apply_crosshair()
	_save_config()

func _sync_crosshair_ui() -> void:
	if ch_sliders.is_empty() or ch_labels.is_empty():
		return
	ch_sliders[0].value = crosshair_len
	ch_sliders[1].value = crosshair_gap
	ch_sliders[2].value = crosshair_thickness
	ch_sliders[3].value = crosshair_dot
	ch_sliders[4].value = crosshair_opacity * 100.0
	ch_labels[0].text = "%d" % int(crosshair_len)
	ch_labels[1].text = "%d" % int(crosshair_gap)
	ch_labels[2].text = "%d" % int(crosshair_thickness)
	ch_labels[3].text = "关" if crosshair_dot < 0.5 else "%d" % int(crosshair_dot)
	ch_labels[4].text = "%d%%" % int(round(crosshair_opacity * 100.0))

func _on_ch_slider(v: float, idx: int) -> void:
	match idx:
		0:
			crosshair_len = v
		1:
			crosshair_gap = v
		2:
			crosshair_thickness = v
		3:
			crosshair_dot = v
		4:
			crosshair_opacity = v / 100.0
	_sync_crosshair_ui()
	apply_crosshair()
	_save_config()

# ---------------------------------------------------------------- 灵敏度校准（180° 甩动）
func _open_calibration() -> void:
	calibrating = false
	calib_pixels = 0.0
	calib_recording = false
	calib_result = 0.0
	calib_status.text = "准备就绪"
	calib_result_label.text = ""
	calib_apply_btn.disabled = true
	calibration_screen.visible = true

func _close_calibration() -> void:
	calibrating = false
	calib_recording = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	calibration_screen.visible = false

func _start_calibration() -> void:
	calib_pixels = 0.0
	calib_recording = false
	calib_result = 0.0
	calibrating = true
	calib_status.text = "按住鼠标左键，完成一次 180° 甩动后松开"
	calib_result_label.text = ""
	calib_apply_btn.disabled = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _finish_calibration() -> void:
	calibrating = false
	calib_recording = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var deg := calib_pixels * RAD_PER_PIXEL * sens * 180.0 / PI
	if calib_pixels < 200.0 or deg < 30.0:
		calib_status.text = "甩动幅度太小或太快，请重新开始"
		calib_result_label.text = ""
		calib_apply_btn.disabled = true
		return
	var suggested := clampf(sens * (180.0 / deg), 0.05, 10.0)
	calib_result = roundf(suggested * 1000.0) / 1000.0
	calib_status.text = "校准完成：本次甩动转了 %.0f°" % deg
	calib_result_label.text = "建议灵敏度：%.3f（当前 %.3f）" % [calib_result, sens]
	calib_apply_btn.disabled = false

func _apply_calibration() -> void:
	if calib_result <= 0.0:
		return
	sens = calib_result
	if sens_slider != null:
		sens_slider.value = sens
	if sens_edit != null:
		sens_edit.text = "%.3f" % sens
	_save_config()
	calib_result_label.text = "已应用：%.3f" % sens
	calib_apply_btn.disabled = true

# ---------------------------------------------------------------- 多游戏灵敏度换算
func _open_converter() -> void:
	convert_screen.visible = true
	if convert_input != null:
		convert_input.text = "%.3f" % sens
	_refresh_converter()

func _close_converter() -> void:
	convert_screen.visible = false

func _on_convert_src(_idx: int) -> void:
	_refresh_converter()

func _on_convert_text(_text: String) -> void:
	_refresh_converter()

func _refresh_converter() -> void:
	var val := float(convert_input.text)
	if val <= 0.0 or val > 20.0:
		convert_out.text = "请输入 0.001 ~ 20 之间的灵敏度"
		return
	var names := ["瓦洛兰特", "CS2", "Apex", "守望先锋2", "彩虹六号", "使命召唤"]
	var src: String = names[convert_src_opt.selected]
	var src_yaw: float = GAME_YAW[src]
	var lines := PackedStringArray()
	for g in names:
		var yaw: float = GAME_YAW[g]
		var v := val * src_yaw / yaw
		v = roundf(v * 1000.0) / 1000.0
		var cm := 360.0 / (yaw * v) / 800.0 * 2.54
		lines.append("%s：%.3f    （cm/360 @800DPI：%.1f）" % [g, v, cm])
	convert_out.text = "\n".join(lines)

# ---------------------------------------------------------------- 分辨率与拉伸
func _on_resolution(idx: int) -> void:
	var keys := ["1280x720", "1280x1000", "1920x1080", "2560x1440", "1024x768"]
	res_setting = keys[idx]
	_save_config()
	_apply_display()

func _on_fullscreen(on: bool) -> void:
	fullscreen = on
	_save_config()
	_apply_display()

func _on_stretch(on: bool) -> void:
	stretch_display = on
	_save_config()
	_apply_display()

func _apply_display() -> void:
	var win := get_window()
	if fullscreen:
		win.mode = Window.MODE_FULLSCREEN
	else:
		win.mode = Window.MODE_WINDOWED
		var parts := res_setting.split("x")
		if parts.size() == 2:
			win.size = Vector2i(int(parts[0]), int(parts[1]))
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE if stretch_display else Window.CONTENT_SCALE_ASPECT_EXPAND
