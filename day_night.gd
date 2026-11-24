class_name DayNight
extends Node
## 昼夜循环：太阳/月亮天体 + 光照 + 环境色 + 天空色

const DAY_LENGTH := 1200.0  # 一天 20 分钟
const BODY_DISTANCE := 420.0

const NIGHT_AMBIENT := Color(0.32, 0.36, 0.52)
const DAY_AMBIENT := Color(0.90, 0.94, 1.0)
const NIGHT_SKY := Color(0.05, 0.06, 0.14)
const DAY_SKY := Color(0.62, 0.76, 0.90)
const DUSK_SKY := Color(0.78, 0.50, 0.34)

var time_of_day := 0.36  # 0..1，0.25 = 06:00
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment

var sun_disc: MeshInstance3D
## 0 = 地表, 1 = 完全在地下（由 main.gd 每帧探测头顶是否有地形）
var underground_target := 0.0
var _under := 0.0
var day_factor := 1.0
var sun_mat: StandardMaterial3D
var moon_disc: MeshInstance3D


func _ready() -> void:
	_build_bodies()


func _build_bodies() -> void:
	sun_mat = StandardMaterial3D.new()
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mat.albedo_color = Color(1.0, 0.99, 0.96)
	sun_mat.emission_enabled = true
	sun_mat.emission = Color(1.0, 0.97, 0.90)
	sun_mat.emission_energy_multiplier = 2.4
	sun_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = 20.0
	sun_mesh.height = 40.0
	sun_mesh.radial_segments = 24
	sun_mesh.rings = 12

	sun_disc = MeshInstance3D.new()
	sun_disc.mesh = sun_mesh
	sun_disc.material_override = sun_mat
	sun_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun_disc)


	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.88, 0.92, 1.0)
	moon_mat.emission_enabled = true
	moon_mat.emission = Color(0.72, 0.80, 1.0)
	moon_mat.emission_energy_multiplier = 1.1

	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 9.0
	moon_mesh.height = 18.0
	moon_mesh.radial_segments = 20
	moon_mesh.rings = 10

	moon_disc = MeshInstance3D.new()
	moon_disc.mesh = moon_mesh
	moon_disc.material_override = moon_mat
	moon_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon_disc)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_under = lerpf(_under, underground_target, 1.0 - exp(-2.5 * delta))
	apply()


func apply() -> void:
	# 太阳沿天球运动：0.25 = 东边日出，0.5 = 头顶偏南，0.75 = 西边日落
	var a := (time_of_day - 0.25) * TAU
	var sun_dir := Vector3(cos(a) * 0.85, sin(a) * 0.78, 0.62).normalized()
	day_factor = clampf(sun_dir.y * 3.4, 0.0, 1.0)

	# 让方向光的 -Z（光传播方向）对准地面 → 节点 +Z 指向太阳
	sun.look_at_from_position(sun_dir * 200.0, Vector3.ZERO, Vector3.UP)
	sun.light_energy = 1.35 * day_factor * (1.0 - 0.35 * _under)
	sun.visible = day_factor > 0.02
	fill.light_energy = lerpf(0.10, 0.32, day_factor)

	env.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, day_factor)
	env.ambient_light_energy = lerpf(1.00, 1.65, day_factor) * (1.0 - 0.10 * _under)

	var sky := NIGHT_SKY.lerp(DAY_SKY, day_factor)
	var dusk := clampf(1.0 - absf(day_factor - 0.28) / 0.28, 0.0, 1.0)
	sky = sky.lerp(DUSK_SKY, dusk * 0.6)
	env.background_color = sky
	env.fog_light_color = sky
	env.fog_density = lerpf(0.0030, 0.010, _under)

	# 天空中的太阳/月亮圆盘，挂在相机四周远处，随昼夜一起升落
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var base := cam.global_position
		sun_disc.global_position = base + sun_dir * BODY_DISTANCE
		# 月亮：翻到太阳对面（夜里升到上空），但仍然保持在玩家前方这一侧
		var moon_dir := Vector3(-sun_dir.x, -sun_dir.y, sun_dir.z)
		if moon_dir.length() < 0.01:
			moon_dir = Vector3(0.0, 1.0, 0.0)
		moon_disc.global_position = base + moon_dir.normalized() * BODY_DISTANCE
		# 太阳本体：贴近地平线时逐渐缩小变淡，自然消失
		var fade := clampf((sun_dir.y + 0.10) / 0.22, 0.0, 1.0)
		sun_disc.visible = fade > 0.01
		sun_disc.scale = Vector3.ONE * (0.55 + 0.45 * fade)
		sun_mat.albedo_color = Color(1.0, 0.99, 0.96, fade)
		moon_disc.visible = sun_dir.y < 0.04


func time_text() -> String:
	var total := time_of_day * 24.0
	var h := int(total)
	var m := int((total - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]


func phase_text() -> String:
	var h := time_of_day * 24.0
	if h < 5.0 or h >= 20.0:
		return "夜"
	elif h < 9.0:
		return "晨"
	elif h < 17.0:
		return "昼"
	return "昏"
