extends Node3D

## Aim Trainer - Godot 客户端版
## 三种模式 / 3D 靶场 / 计分 / 管理员辅助功能，逻辑与网页版对齐。

const MODE_SIXSHOT := "sixshot"
const MODE_TRACKING := "tracking"
const MODE_GRIDSHOT := "gridshot"

const MODES := {
	MODE_SIXSHOT: {"name": "六目标", "count": 6, "color": Color(1.0, 0.42, 0.37), "score": 10, "delay": 0.4},
	MODE_TRACKING: {"name": "跟踪", "count": 1, "color": Color(0.31, 0.76, 1.0), "score": 25, "delay": 0.35},
	MODE_GRIDSHOT: {"name": "极速切换", "count": 1, "color": Color(1.0, 0.76, 0.3), "score": 15, "delay": 0.2}
}

const RAD_PER_PIXEL := deg_to_rad(0.07)
const PITCH_LIMIT := deg_to_rad(80.0)
const ADMIN_HASH := "3bacef24"

const SMOOTH_PRESETS := {
	"responsive": [0.25, 16.0],
	"balanced": [0.1, 8.0],
	"stable": [0.05, 4.0]
}

var mode := MODE_SIXSHOT
var duration := 60
var size_mult := 1.0
var speed_mult := 1.0
var sens := 1.0
var spawn_side := "front"
var smooth_mode := "balanced"
var control_mode := "lock"

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
var score := 0
var start_real := 0.0

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
var canvas: CanvasLayer
var blockers: Array[StaticBody3D] = []
var targets: Array = []
var target_bodies: Dictionary = {}
var cfg := ConfigFile.new()

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
var hitmarker_a: ColorRect
var hitmarker_b: ColorRect

var sounds := {}

func _ready() -> void:
	_load_config()
	_setup_3d()
	_setup_ui()
	_update_menu_values()

func _load_config() -> void:
	cfg.load("user://aimtrainer.cfg")
	sens = float(cfg.get_value("settings", "sens", 1.0))
	duration = int(cfg.get_value("settings", "duration", 60))
	size_mult = float(cfg.get_value("settings", "size", 1.0))
	speed_mult = float(cfg.get_value("settings", "speed", 1.0))
	spawn_side = str(cfg.get_value("settings", "side", "front"))
	smooth_mode = str(cfg.get_value("settings", "smooth", "balanced"))
	control_mode = str(cfg.get_value("settings", "control", "lock"))
	triggerbot = bool(cfg.get_value("admin", "triggerbot", false))
	assist = bool(cfg.get_value("admin", "assist", false))
	assist_fov = deg_to_rad(float(cfg.get_value("admin", "assist_fov", 12.0)))
	assist_strength = float(cfg.get_value("admin", "assist_strength", 0.4))

func _save_config() -> void:
	cfg.set_value("settings", "sens", sens)
	cfg.set_value("settings", "duration", duration)
	cfg.set_value("settings", "size", size_mult)
	cfg.set_value("settings", "speed", speed_mult)
	cfg.set_value("settings", "side", spawn_side)
	cfg.set_value("settings", "smooth", smooth_mode)
	cfg.set_value("settings", "control", control_mode)
	cfg.set_value("admin", "triggerbot", triggerbot)
	cfg.set_value("admin", "assist", assist)
	cfg.set_value("admin", "assist_fov", rad_to_deg(assist_fov))
	cfg.set_value("admin", "assist_strength", assist_strength)
	cfg.save("user://aimtrainer.cfg")

func best_key() -> String:
	return "%s-%d-%s-%s-%s" % [mode, duration, str(size_mult), str(speed_mult), spawn_side]

# ---------------------------------------------------------------- 3D
func _setup_3d() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.09)
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.09)
	env.fog_density = 0.012
	env_node.environment = env
	add_child(env_node)

	var hemi := DirectionalLight3D.new()
	hemi.rotation_degrees = Vector3(-55, -30, 0)
	hemi.light_color = Color(1, 0.95, 0.85)
	hemi.light_energy = 1.4
	hemi.shadow_enabled = true
	hemi.directional_shadow_max_distance = 80.0
	add_child(hemi)

	var amb := OmniLight3D.new()
	amb.position = Vector3(0, 6, 0)
	amb.light_color = Color(0.55, 0.65, 0.85)
	amb.light_energy = 0.6
	amb.omni_range = 40.0
	add_child(amb)

	cam = Camera3D.new()
	cam.fov = 90
	cam.position = Vector3(0, 1.6, 0)
	add_child(cam)
	cam.make_current()

	var floor_mat := _mat(Color(0.11, 0.13, 0.17), 0.9)
	_add_box(Vector3(64, 0.2, 64), Vector3(0, -0.1, 0), floor_mat)
	var wall_mat := _mat(Color(0.1, 0.13, 0.19), 0.85)
	_add_box(Vector3(64, 14, 1), Vector3(0, 7, -32), wall_mat)
	_add_box(Vector3(64, 14, 1), Vector3(0, 7, 32), wall_mat)
	_add_box(Vector3(1, 14, 64), Vector3(-32, 7, 0), wall_mat)
	_add_box(Vector3(1, 14, 64), Vector3(32, 7, 0), wall_mat)
	_add_box(Vector3(64, 1, 64), Vector3(0, 14.5, 0), wall_mat)
	var pillar_mat := _mat(Color(0.14, 0.18, 0.25), 0.75)
	for p in [Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(-11, 0, 11), Vector3(11, 0, 11)]:
		_add_box(Vector3(2, 9, 2), p + Vector3(0, 4.5, 0), pillar_mat)

	for s in ["shot", "hit", "kill", "miss", "start", "end"]:
		var player := AudioStreamPlayer.new()
		add_child(player)
		sounds[s] = player

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

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
		"ang_y_min": -PI, "ang_y_max": PI, "pulse": randf() * TAU
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
		var world_yaw := 0.0
		if spawn_side == "front":
			world_yaw = yaw + randf_range(-1.2, 1.2)
		else:
			world_yaw = randf_range(-PI, PI)
		var world_pitch := clampf(pitch + randf_range(-0.175, 0.175), -0.1, 0.8)
		var dir := Vector3(
			-sin(world_yaw) * cos(world_pitch),
			sin(world_pitch),
			-cos(world_yaw) * cos(world_pitch)
		)
		var dist := randf_range(6.5, 10.0)
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
			if t["alive"] and t["body"].global_position.distance_to(pos) < 3.0:
				ok = false
				break
		if ok:
			return pos
	return Vector3.ZERO

func spawn_target(t: Dictionary) -> void:
	if mode == MODE_TRACKING:
		t["ang_y"] = yaw + randf_range(-1.0, 1.0) if spawn_side == "front" else randf_range(-PI, PI)
		t["ang_y_min"] = yaw - 1.3 if spawn_side == "front" else -PI
		t["ang_y_max"] = yaw + 1.3 if spawn_side == "front" else PI
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
	_play("shot")
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 300.0
	var res := _raycast(from, to)
	if res.is_empty():
		_play("miss")
	else:
		var t = target_bodies.get(res["collider"])
		if t != null and t["alive"]:
			hits += 1.0
			_show_hitmarker()
			_play("hit")
			_spawn_burst(res["position"], t["mat"].emission)
			_on_kill(t)
		else:
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
	for i in cfg_mode["count"]:
		make_target(cfg_mode["color"])
	for t in targets:
		spawn_target(t)
	kills = 0
	shots = 0.0
	hits = 0.0
	score = 0
	time_left = float(duration)
	running = true
	paused = false
	finished = false
	start_real = Time.get_ticks_msec() / 1000.0
	menu.visible = false
	results.visible = false
	hud.visible = true
	if control_mode == "lock":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_play("start")
	update_hud()

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
	var key := best_key()
	var prev_best := int(cfg.get_value("best", key, 0))
	var is_best := score > prev_best
	if is_best:
		cfg.set_value("best", key, score)
		cfg.save("user://aimtrainer.cfg")
	res_score_label.text = str(score)
	res_kills_label.text = str(kills)
	res_acc_label.text = str(acc) + "%"
	res_avg_label.text = "%.2f 秒" % avg if kills > 0 else "—"
	res_best_label.text = str(maxi(prev_best, score))
	res_newbest_label.text = "🎉 新纪录！" if is_best else ""
	hud.visible = false
	results.visible = true
	_play("end")

# ---------------------------------------------------------------- 输入
func _input(event: InputEvent) -> void:
	# 鼠标转动在 _input 处理：发生在界面层之前，确保任何 UI 都拦不住
	if event is InputEventMouseMotion:
		if mouse_captured or (control_mode == "drag" and dragging):
			_apply_mouse(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
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
	if code == KEY_R:
		return
	if code == KEY_B:
		return
	if code == KEY_E:
		return

func _key_up(_code: Key) -> void:
	pass

func _process(delta: float) -> void:
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
	panel.position = Vector2(300, 10)
	panel.size = Vector2(680, 880)
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
	sub.text = "Godot 客户端版 · 与网页版功能对齐"
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.position = Vector2(0, 78)
	sub.size = Vector2(680, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	panel.add_child(sub)

	var y := 120
	_add_label(panel, "选择模式", 16, Vector2(40, y), Vector2(600, 26))
	y += 34
	for m in [MODE_SIXSHOT, MODE_TRACKING, MODE_GRIDSHOT]:
		var btn := Button.new()
		btn.text = MODES[m]["name"]
		btn.position = Vector2(40 + ([MODE_SIXSHOT, MODE_TRACKING, MODE_GRIDSHOT].find(m)) * 200, y)
		btn.size = Vector2(190, 52)
		btn.toggle_mode = true
		btn.button_pressed = (m == current_mode)
		btn.pressed.connect(_on_mode_btn.bind(m, btn))
		panel.add_child(btn)
		mode_buttons[m] = btn
	y += 72

	_add_label(panel, "训练设置", 16, Vector2(40, y), Vector2(600, 26))
	y += 34
	_add_select(panel, "时长", ["30 秒", "60 秒", "120 秒"], _index_of([30, 60, 120], duration), Vector2(40, y), _on_duration)
	y += 44
	_add_select(panel, "靶子大小", ["小", "中", "大"], _index_of([0.7, 1.0, 1.4], size_mult), Vector2(40, y), _on_size)
	y += 44
	_add_select(panel, "移动速度", ["慢", "中", "快"], _index_of([0.6, 1.0, 1.6], speed_mult), Vector2(40, y), _on_speed)
	y += 44
	_add_select(panel, "靶子生成", ["单面（前方）", "多面（环绕）"], 0 if spawn_side == "front" else 1, Vector2(40, y), _on_side)
	y += 44
	_add_select(panel, "视角控制", ["锁定（点击锁定鼠标）", "拖拽（按住右键转动）"], 0 if control_mode == "lock" else 1, Vector2(40, y), _on_control)
	y += 44
	_add_select(panel, "视角平滑", ["跟手", "平衡", "稳定"], {"responsive": 0, "balanced": 1, "stable": 2}[smooth_mode], Vector2(40, y), _on_smooth)
	y += 44
	_add_sens_row(panel, y)
	y += 52

	var start_btn := Button.new()
	start_btn.text = "开始训练"
	start_btn.position = Vector2(40, y)
	start_btn.size = Vector2(600, 54)
	start_btn.pressed.connect(start_round)
	panel.add_child(start_btn)
	y += 70

	var admin_btn := Button.new()
	admin_btn.text = "管理员"
	admin_btn.position = Vector2(40, y)
	admin_btn.size = Vector2(140, 34)
	admin_btn.pressed.connect(_toggle_admin_login)
	panel.add_child(admin_btn)
	admin_btn_node = admin_btn

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
	hud_assist = _add_label(hud, "", 15, Vector2(20, 850), Vector2(400, 30))
	hud_assist.add_theme_color_override("font_color", Color(1.0, 0.76, 0.3))
	var ch := Control.new()
	ch.set_anchors_preset(Control.PRESET_CENTER)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ch)
	var dot := ColorRect.new()
	dot.color = Color(0.43, 0.91, 0.65)
	dot.position = Vector2(-3, -3)
	dot.size = Vector2(6, 6)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(dot)
	for off in [Vector2(-1, -14), Vector2(-1, 8), Vector2(-14, -1), Vector2(8, -1)]:
		var bar := ColorRect.new()
		bar.color = Color(0.43, 0.91, 0.65)
		bar.position = off
		bar.size = Vector2(2, 6) if off.x == -1 else Vector2(6, 2)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.add_child(bar)
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
	var pause_label := _add_label(pause_overlay, "已暂停 · 按 Esc 继续", 30, Vector2(440, 320), Vector2(400, 60), HORIZONTAL_ALIGNMENT_CENTER)
	pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	res_panel.position = Vector2(390, 120)
	res_panel.size = Vector2(500, 460)
	results.add_child(res_panel)
	_add_label(res_panel, "训练完成", 30, Vector2(0, 30), Vector2(500, 50), HORIZONTAL_ALIGNMENT_CENTER)
	res_newbest_label = _add_label(res_panel, "", 18, Vector2(0, 80), Vector2(500, 30), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(res_panel, "得分", 14, Vector2(40, 130), Vector2(120, 24))
	res_score_label = _add_label(res_panel, "", 26, Vector2(40, 154), Vector2(120, 40))
	_add_label(res_panel, "击杀", 14, Vector2(210, 130), Vector2(120, 24))
	res_kills_label = _add_label(res_panel, "", 26, Vector2(210, 154), Vector2(120, 40))
	_add_label(res_panel, "命中率", 14, Vector2(380, 130), Vector2(120, 24))
	res_acc_label = _add_label(res_panel, "", 26, Vector2(380, 154), Vector2(120, 40))
	_add_label(res_panel, "平均每杀", 14, Vector2(40, 240), Vector2(180, 24))
	res_avg_label = _add_label(res_panel, "", 24, Vector2(40, 264), Vector2(180, 40))
	_add_label(res_panel, "最佳成绩", 14, Vector2(280, 240), Vector2(180, 24))
	res_best_label = _add_label(res_panel, "", 24, Vector2(280, 264), Vector2(180, 40))
	var again := Button.new()
	again.text = "再来一次"
	again.position = Vector2(60, 360)
	again.size = Vector2(180, 50)
	again.pressed.connect(start_round)
	res_panel.add_child(again)
	var back := Button.new()
	back.text = "返回菜单"
	back.position = Vector2(260, 360)
	back.size = Vector2(180, 50)
	back.pressed.connect(_back_to_menu)
	res_panel.add_child(back)

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
	var slider := _slider(0.05, 10.0, 0.05, sens, Vector2(230, y), Vector2(240, 32))
	slider.value_changed.connect(_on_sens_slider)
	parent.add_child(slider)
	var edit := LineEdit.new()
	edit.text = "%.2f" % sens
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
	size_mult = [0.7, 1.0, 1.4][idx]
	_save_config()

func _on_speed(idx: int) -> void:
	speed_mult = [0.6, 1.0, 1.6][idx]
	_save_config()

func _on_side(idx: int) -> void:
	spawn_side = "front" if idx == 0 else "all"
	_save_config()

func _on_control(idx: int) -> void:
	control_mode = "lock" if idx == 0 else "drag"
	_save_config()

func _on_smooth(idx: int) -> void:
	smooth_mode = ["responsive", "balanced", "stable"][idx]
	_save_config()

func _on_sens_slider(v: float) -> void:
	sens = clampf(v, 0.05, 10.0)
	_save_config()

func _on_sens_text(text: String) -> void:
	var v := float(text)
	if is_finite(v) and v > 0.0:
		sens = clampf(v, 0.05, 10.0)
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
		admin_login.visible = false
		admin_panel.visible = true
		admin_msg.text = ""
		edit.text = ""
	else:
		admin_msg.text = "密码错误"

func _on_admin_exit() -> void:
	admin_unlocked = false
	admin_panel.visible = false

func _on_triggerbot(on: bool) -> void:
	triggerbot = on
	_save_config()
	_update_admin_state()

func _on_assist(on: bool) -> void:
	assist = on
	_save_config()
	_update_admin_state()

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

func _update_menu_values() -> void:
	pass

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
	var parts := []
	if triggerbot:
		parts.append("扳机")
	if assist:
		parts.append("吸附")
	hud_assist.text = "辅助: " + ("、".join(PackedStringArray(parts)) if not parts.is_empty() else "关")
