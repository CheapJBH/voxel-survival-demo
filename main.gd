extends Node3D
## 移动端 voxel demo：物理步行 + 昼夜循环 + 挖填
## 触屏：左下浮动摇杆走路、右半屏拖动转视角、右下三颗按钮（跳/挖/填）
## PC 调试：WASD 走、空格跳、右键拖动看、左键挖、F 切换、滚轮切换

const EDIT_RADIUS := 0.85
const REACH := 4.5
const LOOK_DEG_PER_SCREEN_H := 200.0
const JOY_DEADZONE := 0.14
const JOY_R_RATIO := 0.115
const BTN_R_RATIO := 0.058

var terrain: VoxelLodTerrain
var player: VoxelPlayer
var day_night: DayNight
var hud: Label
var overlay: Control
var tool: VoxelTool

var tool_mode := 1  # 1 = 挖, 2 = 填
var edit_ms := 0.0

var _joy_id := -1
var _jump_id := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _joy_radius := 90.0
var _look_id := -1
var _look_last := Vector2.ZERO
var _btn_jump := Vector2.ZERO
var _btn_remove := Vector2.ZERO
var _btn_add := Vector2.ZERO
var _btn_radius := 52.0
var _aim_hit := false
var _aim_timer := 0.0
var _under_timer := 0.0
var _mine_id := -1
var _mining := false
var _mine_pos := Vector3.ZERO
var _mine_progress := 0.0
var _mine_time := 1.0
var _burst: CPUParticles3D
var inventory := Inventory.new()
var _save_timer := 0.0
var _eat_timer := 0.0
var _enemies: Array = []
var _enemy_spawn_t := 0.0
var _name_timer := 0.0
var _cold_t := 0.0
var _bgm: AudioStreamPlayer
var _trees: Array = []
var _torches: Array = []
var _craft_open := false
var _trees_planted := false
const CRAFT_ROW_H := 62.0
const BTN_CRAFT_R := 40.0
const SAVE_DIR := "user://world"
const PLAYER_SAVE := "user://player.json"
var _spawned := false
var _is_mobile := false


class Overlay extends Control:
	const JOY_R := 90.0
	const BTN_R := 52.0

	var host


	func _draw() -> void:
		if not host._spawned:
			return
		var s := size
		var c := s * 0.5
		var font := ThemeDB.fallback_font

		# 准星（命中地形时变亮变大）
		var aim_col := Color(1, 1, 1, 0.85) if host._aim_hit else Color(1, 1, 1, 0.45)
		draw_circle(c, 2.5, aim_col)
		draw_arc(c, 12.0 if host._aim_hit else 9.0, 0.0, TAU, 28, Color(1, 1, 1, 0.26), 1.5, true)

		# 摇杆
		if host._joy_id != -1:
			var o = host._joy_origin
			var r: float = host._joy_radius
			draw_arc(o, r, 0.0, TAU, 48, Color(1, 1, 1, 0.20), 2.0, true)
			draw_circle(o, r * 0.44, Color(1, 1, 1, 0.07))
			draw_circle(o + host._joy_vec * (r * 0.62), r * 0.27, Color(1, 1, 1, 0.28))

		# 挖掘进度环
		if host._mine_progress > 0.02:
			draw_arc(c, 20.0, -PI * 0.5, -PI * 0.5 + TAU * host._mine_progress, 40, Color(1, 1, 0.85, 0.85), 3.5, true)

		# 生命 / 饥饿
		var bar_w := 150.0
		var bar_h := 9.0
		var bx := 18.0
		var by := 42.0
		draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(bx, by, bar_w * clampf(host.player.hp / 100.0, 0.0, 1.0), bar_h), Color(0.80, 0.26, 0.28, 0.92))
		draw_rect(Rect2(bx, by + bar_h + 5.0, bar_w, bar_h), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(bx, by + bar_h + 5.0, bar_w * clampf(host.player.hunger / 100.0, 0.0, 1.0), bar_h), Color(0.86, 0.70, 0.30, 0.92))

		# 快捷栏
		var n := Inventory.SLOT_COUNT
		var cell := 54.0
		var gap := 6.0
		var total := n * cell + float(n - 1) * gap
		var x0 := (s.x - total) * 0.5
		var y0 := s.y - cell - 22.0
		for i in range(n):
			var rx := x0 + float(i) * (cell + gap)
			var sel: bool = i == host.inventory.selected
			draw_rect(Rect2(rx, y0, cell, cell), Color(1, 1, 1, 0.16 if sel else 0.07))
			if sel:
				draw_rect(Rect2(rx, y0, cell, cell), Color(1, 1, 1, 0.55), false, 2.0)
			var slot: Dictionary = host.inventory.slots[i]
			if slot.is_empty():
				continue
			var col := BlockDB.color_of_item(String(slot["id"]))
			_draw_cube_icon(Vector2(rx + cell * 0.5, y0 + cell * 0.44), cell * 0.52, col)
			var cnt := str(int(slot["count"]))
			draw_string(font, Vector2(rx + cell - 8.0 - font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, y0 + cell - 6.0), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))

		# 选中物品名（点击后短暂显示）
		if host._name_timer > 0.0:
			var nm := BlockDB.name_of_item(host.inventory.selected_id())
			if nm != "":
				var alpha := clampf(host._name_timer, 0.0, 1.0)
				var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
				draw_string(font, Vector2(s.x * 0.5 - nw * 0.5, y0 - 14.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9 * alpha))

		# 合成按钮（右上角）
		var cbtn := Vector2(s.x - 76.0, 76.0)
		draw_circle(cbtn, BTN_CRAFT_R, Color(1, 1, 1, 0.10 if not host._craft_open else 0.24))
		draw_arc(cbtn, BTN_CRAFT_R, 0.0, TAU, 40, Color(1, 1, 1, 0.26), 1.5, true)
		var ctw := font.get_string_size("合", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, cbtn + Vector2(-ctw * 0.5, 7), "合", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.85))

		# 合成面板
		if host._craft_open:
			var pr: Rect2 = host._craft_panel_rect()
			draw_rect(pr, Color(0.05, 0.06, 0.08, 0.95))
			draw_rect(pr, Color(1, 1, 1, 0.16), false, 1.5)
			draw_string(font, pr.position + Vector2(24, 42), "合成", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.92))
			draw_string(font, pr.position + Vector2(pr.size.x - 120, 38), "点一下即合成", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.35))
			for i in range(Recipes.LIST.size()):
				var rec: Dictionary = Recipes.LIST[i]
				var rr: Rect2 = host._craft_row_rect(i)
				var ok: bool = Recipes.can_craft(rec, host.inventory)
				draw_rect(rr, Color(1, 1, 1, 0.10 if ok else 0.04))
				draw_string(font, rr.position + Vector2(14, 24), String(rec["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.92 if ok else 0.40))
				draw_string(font, rr.position + Vector2(14, 46), Recipes.need_text(rec), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.45))

		_draw_btn(host._btn_jump, "跳", font)
		_draw_btn(host._btn_remove, "挖", font)
		_draw_btn(host._btn_add, "填", font)


	func _draw_cube_icon(center: Vector2, size_px: float, base: Color) -> void:
		var w := size_px * 0.5
		var h := size_px * 0.30
		var hh := size_px * 0.52
		var top := PackedVector2Array([
			center + Vector2(0, -hh),
			center + Vector2(w, -hh + h),
			center + Vector2(0, -hh + h * 2.0),
			center + Vector2(-w, -hh + h)])
		draw_colored_polygon(top, base.lightened(0.30))
		var left := PackedVector2Array([
			center + Vector2(-w, -hh + h),
			center + Vector2(0, -hh + h * 2.0),
			center + Vector2(0, hh),
			center + Vector2(-w, hh - h)])
		draw_colored_polygon(left, base.darkened(0.30))
		var right := PackedVector2Array([
			center + Vector2(0, -hh + h * 2.0),
			center + Vector2(w, -hh + h),
			center + Vector2(w, hh - h),
			center + Vector2(0, hh)])
		draw_colored_polygon(right, base.darkened(0.10))


	func _draw_btn(center: Vector2, label: String, font: Font) -> void:
		if center == Vector2.ZERO:
			return
		var r: float = host._btn_radius
		draw_circle(center, r, Color(1, 1, 1, 0.07))
		draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 1.5, true)
		var fs := int(clamp(r * 0.42, 15.0, 28.0))
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, center + Vector2(-tw * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.82))


func _ready() -> void:
	terrain = get_node_or_null("VoxelLodTerrain") as VoxelLodTerrain
	if terrain != null:
		var st := VoxelStreamRegionFiles.new()
		var abs_dir := ProjectSettings.globalize_path(SAVE_DIR)
		DirAccess.make_dir_recursive_absolute(abs_dir)
		st.set("directory", abs_dir)
		terrain.stream = st
		tool = terrain.get_voxel_tool()
		if tool != null:
			tool.mode = VoxelTool.MODE_REMOVE

	# 环境 + 光照
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.66, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.80)
	env.ambient_light_energy = 0.88
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.76, 0.90)
	env.fog_density = 0.0040
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	# 环境光遮蔽：让挖出来的坑、山谷、墙根变暗，不再是「一片草」的平面感
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.1
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 140, 0)
	fill.light_energy = 0.30
	fill.shadow_enabled = false
	fill.light_color = Color(0.85, 0.90, 1.0)
	add_child(fill)

	day_night = DayNight.new()
	day_night.sun = sun
	day_night.fill = fill
	day_night.env = env
	add_child(day_night)
	day_night.apply()

	# 玩家
	player = VoxelPlayer.new()
	player.terrain = terrain
	add_child(player)
	player.global_position = Vector3(0, 120, 70)
	player.set_physics_process(false)

	var layer := CanvasLayer.new()
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(18, 14)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_color", Color(0.96, 0.96, 0.92, 0.92))
	layer.add_child(hud)

	overlay = Overlay.new()
	overlay.host = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	_is_mobile = DisplayServer.is_touchscreen_available()

	player.died.connect(_on_player_died)

	_setup_bgm()

	_setup_burst()

	_relayout()
	get_viewport().size_changed.connect(_relayout)

	_spawn()


func _spawn() -> void:
	player.set_physics_process(false)

	var saved := _load_player_data()
	if saved.has("pos") and saved["pos"] is Array and saved["pos"].size() == 3:
		player.global_position = Vector3(float(saved["pos"][0]), float(saved["pos"][1]), float(saved["pos"][2]))
		player.spawn_point = player.global_position
		inventory.from_dict(saved.get("inv", {}))
		player.hp = float(saved.get("hp", 100.0))
		player.hunger = float(saved.get("hunger", 100.0))
		player.yaw_target = float(saved.get("yaw", 0.0))
		player.yaw = player.yaw_target
		player.pitch_target = float(saved.get("pitch", -6.0))
		player.pitch = player.pitch_target
		player.apply_look()
		day_night.time_of_day = float(saved.get("time", 0.36))
		day_night.apply()
		await get_tree().create_timer(1.2).timeout
		player.set_physics_process(true)
		_plant_trees()
		_spawned = true
		return

	player.global_position = Vector3(0, 78, 70)
	player.spawn_point = player.global_position

	var space := get_world_3d().direct_space_state

	# 等地形碰撞就绪（最多 6 秒，期间 HUD 显示加载提示，不会看着像卡死）
	var ready := false
	for i in range(30):
		var q0 := PhysicsRayQueryParameters3D.create(Vector3(0, 140, 70), Vector3(0, -20, 70))
		q0.exclude = [player.get_rid()]
		if not space.intersect_ray(q0).is_empty():
			ready = true
			break
		await get_tree().create_timer(0.2).timeout

	var best := Vector3(0, 60, 70)
	if ready:
		# 大范围扫描（±120 米），挑最高的开阔位置，避免出生在谷底/沟里
		var cands: Array = []
		for dx in range(-120, 121, 40):
			for dz in range(-120, 121, 40):
				cands.append(Vector3(float(dx), 0.0, float(dz)))
		var best_y := -1.0e20
		for c in cands:
			var from: Vector3 = Vector3(0, 160, 70) + c
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, -20.0, from.z))
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var pos: Vector3 = hit["position"]
			if pos.y <= best_y:
				continue
			# 头顶 10 米不能有遮挡（不是洞里），并且四个方向 8 米外要有地面（不是孤峰尖端）
			var ok := true
			var q2 := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.2, 0), pos + Vector3(0, 10.0, 0))
			q2.exclude = [player.get_rid()]
			if not space.intersect_ray(q2).is_empty():
				ok = false
			if ok:
				var dirs := [Vector3(6, 0, 0), Vector3(-6, 0, 0), Vector3(0, 0, 6), Vector3(0, 0, -6)]
				var heights: Array = []
				for d in dirs:
					var q3 := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 6, 0) + d, pos + Vector3(0, -12, 0) + d)
					q3.exclude = [player.get_rid()]
					var h3 := space.intersect_ray(q3)
					if h3.is_empty():
						ok = false
						break
					heights.append(h3["position"].y)
				# 必须够平坦，别出生在陡坡上（否则一上来就是贴脸斜坡）
				if ok and heights.size() >= 4:
					var mn: float = heights.min()
					var mx: float = heights.max()
					if mx - mn > 2.2:
						ok = false
			if ok:
				best_y = pos.y
				best = pos

	player.global_position = best + Vector3(0, 1.4, 0)
	player.spawn_point = player.global_position

	# 关键：等到「脚下真的有碰撞体」才放开物理，否则会直接穿过地形掉下去
	for i in range(50):
		var qf := PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3(0, 1.2, 0),
			player.global_position - Vector3(0, 3.0, 0)
		)
		qf.exclude = [player.get_rid()]
		if not space.intersect_ray(qf).is_empty():
			break
		await get_tree().create_timer(0.2).timeout

	player.set_physics_process(true)
	await get_tree().create_timer(1.2).timeout
	_plant_trees()
	_spawned = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_game()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_mining = false
		_mine_id = -1
		_joy_id = -1
		_jump_id = -1
		_look_id = -1
		_joy_vec = Vector2.ZERO
		player.input_vec = Vector2.ZERO
		player.jump_held = false


func _craft_panel_rect() -> Rect2:
	var s := get_viewport().get_visible_rect().size
	var ph := float(Recipes.LIST.size()) * CRAFT_ROW_H + 96.0
	return Rect2((s.x - 560.0) * 0.5, (s.y - ph) * 0.5, 560.0, ph)


func _craft_row_rect(i: int) -> Rect2:
	var pr := _craft_panel_rect()
	return Rect2(pr.position.x + 20.0, pr.position.y + 74.0 + float(i) * CRAFT_ROW_H, pr.size.x - 40.0, CRAFT_ROW_H - 10.0)


func _try_craft_at(pos: Vector2) -> void:
	for i in range(Recipes.LIST.size()):
		if _craft_row_rect(i).has_point(pos):
			var rec: Dictionary = Recipes.LIST[i]
			if Recipes.craft(rec, inventory):
				_sync_held_item()
				_name_timer = 2.0
			return


func _sync_held_item() -> void:
	if player == null:
		return
	var id := inventory.selected_id()
	if id == "":
		player.set_held_color(Color(1, 1, 1), false)
	else:
		player.set_held_color(BlockDB.color_of_item(id), true)


func _tree_at(pos: Vector3) -> Dictionary:
	for t in _trees:
		if int(t["hp"]) <= 0:
			continue
		var base: Vector3 = t["pos"]
		if Vector2(pos.x - base.x, pos.z - base.z).length() < 2.6 and pos.y > base.y - 1.0 and pos.y < base.y + 6.5:
			return t
	return {}


func _mine_seconds_for(world_y: float) -> float:
	var base := 0.0
	match BlockDB.id_at(world_y):
		BlockDB.GRASS:
			base = 0.35
		BlockDB.DIRT:
			base = 0.5
		BlockDB.STONE:
			base = 1.0
		_:
			base = 1.6
	if _has_pickaxe():
		base *= 0.55
	return base


func _setup_bgm() -> void:
	_bgm = AudioStreamPlayer.new()
	var st = load("res://audio/bgm.mp3")
	if st != null:
		if st is AudioStreamMP3:
			st.loop = true
		_bgm.stream = st
	_bgm.volume_db = -11.0
	add_child(_bgm)
	if _bgm.stream != null:
		_bgm.play()


func _setup_burst() -> void:
	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 16
	_burst.lifetime = 0.65
	_burst.explosiveness = 0.95
	_burst.direction = Vector3(0, 1, 0)
	_burst.spread = 75.0
	_burst.initial_velocity_min = 2.0
	_burst.initial_velocity_max = 5.5
	_burst.gravity = Vector3(0, -9.8, 0)
	_burst.scale_amount_min = 0.5
	_burst.scale_amount_max = 1.3
	var m := BoxMesh.new()
	m.size = Vector3(0.11, 0.11, 0.11)
	_burst.mesh = m
	add_child(_burst)


func _burst_at(pos: Vector3, color: Color) -> void:
	if _burst == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	_burst.material_override = mat
	_burst.global_position = pos
	_burst.restart()


func _relayout() -> void:
	var s := get_viewport().get_visible_rect().size
	_joy_radius = max(64.0, s.y * JOY_R_RATIO)
	_btn_radius = max(42.0, s.y * BTN_R_RATIO)
	var margin := _btn_radius + 40.0
	var gap := _btn_radius * 2.0 + 16.0
	_btn_add = Vector2(s.x - margin, s.y - margin)
	_btn_remove = Vector2(s.x - margin, s.y - margin - gap)
	_btn_jump = Vector2(s.x - margin, s.y - margin - gap * 2.0)


func _process(delta: float) -> void:
	if hud == null:
		return

	# 准星命中检测（降频，物理射线对 concave 碰撞体偏贵）
	_update_enemies(delta)

	# 夜晚失温：露天时缓慢掉血，躲进地下就安全
	if day_night.day_factor < 0.12 and day_night._under < 0.5 and not _near_torch():
		_cold_t += delta
		if _cold_t >= 1.0:
			_cold_t = 0.0
			player.take_damage(0.8, false)
	else:
		_cold_t = 0.0

	if _name_timer > 0.0:
		_name_timer -= delta

	# 自动存档 / 自动进食
	_save_timer += delta
	if _save_timer > 30.0:
		_save_timer = 0.0
		_save_game()
	_eat_timer += delta
	if _eat_timer > 1.0:
		_eat_timer = 0.0
		if player.hunger < 45.0:
			if inventory.count_of("cooked_berry") > 0:
				if inventory.remove("cooked_berry", 1):
					player.feed(48.0)
			elif inventory.count_of("berry") > 0:
				if inventory.remove("berry", 1):
					player.feed(26.0)

	# 挖掘进度
	if _mining:
		var mh: Variant = _raycast_center()
		if mh == null:
			_mine_progress = maxf(0.0, _mine_progress - delta * 2.0)
		else:
			var mp: Vector3 = mh["position"]
			if _mine_pos.distance_to(mp) > 0.7:
				_mine_pos = mp
				_mine_time = _mine_seconds_for(mp.y)
				_mine_progress = 0.0
			_mine_progress += delta / maxf(_mine_time, 0.05)
			if _mine_progress >= 1.0:
				_mine_progress = 0.0
				_do_mine(mp)
	else:
		_mine_progress = maxf(0.0, _mine_progress - delta * 3.0)

	_under_timer += delta
	if _under_timer > 0.4 and day_night != null:
		_under_timer = 0.0
		var space := get_world_3d().direct_space_state
		# 从高空往下打：命中的面在玩家头顶上方 → 说明玩家在地表之下
		var top := player.global_position + Vector3(0, 60, 0)
		var uq := PhysicsRayQueryParameters3D.create(top, player.global_position)
		uq.exclude = [player.get_rid()]
		var uhit := space.intersect_ray(uq)
		var under := 0.0
		if not uhit.is_empty():
			var hy: float = uhit["position"].y
			if hy > player.global_position.y + 1.0:
				under = 1.0
		day_night.underground_target = under

	_aim_timer += delta
	if _aim_timer > 0.35:
		_aim_timer = 0.0
		_aim_hit = _raycast_center() != null

	if not _spawned:
		hud.text = "正在生成地形…"
		overlay.queue_redraw()
		return

	hud.text = "FPS %d   编辑 %.2f ms   %s %s   位置 %.0f,%.0f,%.0f   %s" % [
		Engine.get_frames_per_second(),
		edit_ms,
		day_night.time_text(),
		day_night.phase_text(),
		player.global_position.x, player.global_position.y, player.global_position.z,
		"挖" if tool_mode == 1 else "填"
	]
	overlay.queue_redraw()


func _raycast_center() -> Variant:
	var s := get_viewport().get_visible_rect().size
	var cam := player.camera
	var from := cam.project_ray_origin(s * 0.5)
	var dir := cam.project_ray_normal(s * 0.5)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH)
	q.exclude = [player.get_rid()]
	q.collision_mask = 1 | 4
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit


func _unhandled_input(event: InputEvent) -> void:
	var s := get_viewport().get_visible_rect().size
	if _btn_add == Vector2.ZERO:
		_relayout()
	var deg_per_px := LOOK_DEG_PER_SCREEN_H / maxf(1.0, s.y)

	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			# 合成按钮
			if touch.position.distance_to(Vector2(s.x - 76.0, 76.0)) <= BTN_CRAFT_R * 1.2:
				_craft_open = not _craft_open
				return
			# 合成面板
			if _craft_open:
				if not _craft_panel_rect().has_point(touch.position):
					_craft_open = false
				else:
					_try_craft_at(touch.position)
				return

			# 快捷栏区域（底部中间）
			var cell := 54.0
			var gap := 6.0
			var bar_total := float(Inventory.SLOT_COUNT) * cell + float(Inventory.SLOT_COUNT - 1) * gap
			var bar_x0 := (s.x - bar_total) * 0.5
			var bar_y0 := s.y - cell - 22.0
			if touch.position.y >= bar_y0 and touch.position.y <= bar_y0 + cell and touch.position.x >= bar_x0 and touch.position.x <= bar_x0 + bar_total:
				var idx := int((touch.position.x - bar_x0) / (cell + gap))
				if idx >= 0 and idx < Inventory.SLOT_COUNT:
					inventory.selected = idx
					_name_timer = 2.2
					_sync_held_item()
				return

			if touch.position.distance_to(_btn_jump) <= _btn_radius * 1.15:
				_jump_id = touch.index
				player.jump_held = true
			elif touch.position.distance_to(_btn_remove) <= _btn_radius * 1.15:
				_mine_id = touch.index
				_mining = true
			elif touch.position.distance_to(_btn_add) <= _btn_radius * 1.15:
				_edit(false)
			elif touch.position.x < s.x * 0.45 and _joy_id == -1:
				_joy_id = touch.index
				_joy_origin = touch.position
				_joy_vec = Vector2.ZERO
				player.input_vec = Vector2.ZERO
			elif _look_id == -1:
				_look_id = touch.index
				_look_last = touch.position
		else:
			if touch.index == _mine_id:
				_mine_id = -1
				_mining = false
				_mine_progress = 0.0
			elif touch.index == _jump_id:
				_jump_id = -1
				player.jump_held = false
			elif touch.index == _joy_id:
				_joy_id = -1
				_joy_vec = Vector2.ZERO
				player.input_vec = Vector2.ZERO
			elif touch.index == _look_id:
				_look_id = -1
		return

	var drag := event as InputEventScreenDrag
	if drag != null:
		if drag.index == _joy_id:
			var d: Vector2 = drag.position - _joy_origin
			var len := d.length()
			if len > _joy_radius:
				_joy_origin += d / len * (len - _joy_radius)
				d = d / len * _joy_radius
			var v := d / _joy_radius
			if v.length() < JOY_DEADZONE:
				_joy_vec = Vector2.ZERO
			else:
				_joy_vec = v.normalized() * ((v.length() - JOY_DEADZONE) / (1.0 - JOY_DEADZONE))
			player.input_vec = _joy_vec
		elif drag.index == _look_id:
			var delta: Vector2 = drag.position - _look_last
			_look_last = drag.position
			player.yaw_target -= delta.x * deg_per_px
			player.pitch_target = clampf(player.pitch_target - delta.y * deg_per_px, -89.0, 89.0)
		return

	# 手机端只认触摸事件，忽略触摸模拟出的鼠标事件
	if _is_mobile:
		return

	# PC 调试
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mining = event.pressed
		if not event.pressed:
			_mine_progress = 0.0
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		player.yaw_target -= event.relative.x * deg_per_px
		player.pitch_target = clampf(player.pitch_target - event.relative.y * deg_per_px, -89.0, 89.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			tool_mode = 1
			if tool != null:
				tool.mode = VoxelTool.MODE_REMOVE
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			tool_mode = 2
			if tool != null:
				tool.mode = VoxelTool.MODE_ADD
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			tool_mode = 2 if tool_mode == 1 else 1
			if tool != null:
				tool.mode = VoxelTool.MODE_REMOVE if tool_mode == 1 else VoxelTool.MODE_ADD


func _physics_process(_delta: float) -> void:
	if player == null or hud == null:
		return
	# PC 键盘
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		v.y -= 1
	if Input.is_key_pressed(KEY_S):
		v.y += 1
	if Input.is_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_key_pressed(KEY_D):
		v.x += 1
	if v != Vector2.ZERO:
		player.input_vec = v.normalized()
	elif _joy_id == -1:
		player.input_vec = Vector2.ZERO
	player.jump_held = Input.is_key_pressed(KEY_SPACE) or _jump_id != -1


func _plant_trees() -> void:
	if _trees_planted or terrain == null:
		return
	_trees_planted = true
	var tool := terrain.get_voxel_tool()
	if tool == null:
		return
	var space := get_world_3d().direct_space_state
	tool.mode = VoxelTool.MODE_ADD
	for i in range(9):
		var ang := randf() * TAU
		var dist := randf_range(14.0, 40.0)
		var base := player.global_position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, 40, 0), base - Vector3(0, 20, 0))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var g: Vector3 = hit["position"]
		for k in range(4):
			tool.do_sphere(g + Vector3(0, 0.9 + float(k) * 1.0, 0), 0.55)
		tool.do_sphere(g + Vector3(0, 4.3, 0), 1.5)
		tool.do_sphere(g + Vector3(0, 5.3, 0), 1.05)
		_trees.append({"pos": g, "hp": 7})


func _place_torch(pos: Vector3) -> void:
	var t := Node3D.new()
	add_child(t)
	t.global_position = pos

	var stick := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.48, 0.11)
	stick.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.34, 0.24, 0.14)
	sm.roughness = 0.95
	stick.material_override = sm
	t.add_child(stick)

	var flame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.17, 0.17, 0.17)
	flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.76, 0.36)
	flame.material_override = fmat
	flame.position.y = 0.32
	t.add_child(flame)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.79, 0.48)
	light.light_energy = 2.4
	light.omni_range = 9.5
	light.shadow_enabled = false
	t.add_child(light)

	_torches.append(t)


func _near_torch() -> bool:
	for t in _torches:
		if is_instance_valid(t) and t.global_position.distance_to(player.global_position) < 9.5:
			return true
	return false


func _has_pickaxe() -> bool:
	return inventory.count_of("pickaxe") > 0


func _update_enemies(delta: float) -> void:
	var night := day_night.day_factor < 0.15
	if not night:
		for e in _enemies:
			if is_instance_valid(e):
				e.queue_free()
		_enemies.clear()
		return

	# 清理已释放的
	var alive: Array = []
	for e in _enemies:
		if is_instance_valid(e):
			alive.append(e)
	_enemies = alive

	_enemy_spawn_t += delta
	if _enemy_spawn_t > 7.0 and _enemies.size() < 5:
		_enemy_spawn_t = 0.0
		_spawn_enemy()


func _spawn_enemy() -> void:
	var space := get_world_3d().direct_space_state
	for attempt in range(6):
		var ang := randf() * TAU
		var dist := randf_range(18.0, 28.0)
		var base := player.global_position + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, 40, 0), base + Vector3(0, -20, 0))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var e := Enemy.new()
		e.target = player
		e.on_death = _on_enemy_died
		add_child(e)
		e.global_position = Vector3(base.x, hit["position"].y + 1.2, base.z)
		_enemies.append(e)
		return


func _on_enemy_died(pos: Vector3) -> void:
	inventory.add("bone", randi_range(1, 2))
	_burst_at(pos + Vector3(0, 0.8, 0), Color(0.88, 0.86, 0.78))
	_sync_held_item()


func _on_player_died() -> void:
	# 死亡：背包物品打对折，回出生点
	for i in range(Inventory.SLOT_COUNT):
		var sl: Dictionary = inventory.slots[i]
		if sl.is_empty():
			continue
		var c := int(sl["count"]) / 2
		if c <= 0:
			inventory.slots[i] = {}
		else:
			sl["count"] = c
	player.respawn()


func _save_game() -> void:
	if player == null or day_night == null:
		return
	var d := {
		"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"yaw": player.yaw_target,
		"pitch": player.pitch_target,
		"hp": player.hp,
		"hunger": player.hunger,
		"inv": inventory.to_dict(),
		"time": day_night.time_of_day,
	}
	var f := FileAccess.open(PLAYER_SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
	# 让 voxel 把玩家改动刷到磁盘（异步，后台线程写 region 文件）
	if terrain != null:
		terrain.save_modified_blocks()


func _load_player_data() -> Dictionary:
	if not FileAccess.file_exists(PLAYER_SAVE):
		return {}
	var f := FileAccess.open(PLAYER_SAVE, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _do_mine(pos: Vector3) -> void:
	if tool == null:
		return
	# 准星对着敌人时优先攻击
	var mh: Variant = _raycast_center()
	if mh != null:
		var col = mh.get("collider")
		if col is Enemy:
			var dmg := 22.0 if inventory.count_of("sword") > 0 else 12.0
			col.take_damage(dmg)
			return
	var t0 := Time.get_ticks_usec()
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(pos, EDIT_RADIUS)
	# 再往上挖一个球：保证挖出来的通道有 2 米高，人能钻进去（否则洞只有 1.7 米，比人还矮）
	tool.do_sphere(pos + Vector3(0, 1.15, 0), EDIT_RADIUS * 0.92)
	edit_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var tree := _tree_at(pos)
	if not tree.is_empty():
		tree["hp"] = int(tree["hp"]) - 1
		_burst_at(pos, Color(0.42, 0.30, 0.18))
		inventory.add("wood", randi_range(1, 2))
		_sync_held_item()
		return

	var block_id := BlockDB.id_at(pos.y)
	var info: Dictionary = BlockDB.INFO[block_id]
	_burst_at(pos, info["color"])
	# 掉落
	var inv: Inventory = inventory
	inv.add(String(info["drop"]), randi_range(2, 4))
	if block_id == BlockDB.GRASS and randf() < 0.4:
		inv.add("berry", 1)
	_sync_held_item()


func _edit(remove: bool) -> void:
	if tool == null:
		return
	if not remove:
		var item := inventory.selected_id()
		if item == "" or item == "berry" or item == "cooked_berry" or item == "pickaxe":
			return
		var hit0: Variant = _raycast_center()
		if hit0 == null:
			return
		if item == "torch":
			if inventory.remove(item, 1):
				_place_torch(hit0["position"] + Vector3(0, 0.25, 0))
				_sync_held_item()
			return
		if not inventory.remove(item, 1):
			return
	var hit: Variant = _raycast_center()
	if hit == null:
		return
	var t0 := Time.get_ticks_usec()
	tool.mode = VoxelTool.MODE_REMOVE if remove else VoxelTool.MODE_ADD
	tool.do_sphere(hit["position"], EDIT_RADIUS)
	edit_ms = (Time.get_ticks_usec() - t0) / 1000.0
	player.swing()
	tool_mode = 1 if remove else 2
