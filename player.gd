class_name VoxelPlayer
extends CharacterBody3D
## 第一人称玩家：重力 / 步行 / 跳跃 / 视角 / 手部模型 / 出生与重生

const WALK_SPEED := 5.5
const GRAVITY := 25.0
const JUMP_SPEED := 8.2
const LOOK_DEG_PER_SCREEN_H := 200.0
const LOOK_SMOOTH := 28.0
const EYE_HEIGHT := 1.55
const HAND_BASE := Vector3(0.44, -0.42, -0.86)

var terrain: VoxelLodTerrain
var camera: Camera3D
var viewer: VoxelViewer
var hand_root: Node3D

var yaw := 0.0
var pitch := -6.0
var yaw_target := 0.0
var pitch_target := -6.0

## 摇杆输出：x = 右, y = 后（屏幕坐标习惯）
var input_vec := Vector2.ZERO
## 按住跳跃（手机长按 = 落地就再跳）
var jump_held := false
var jump_requested := false
var spawn_point := Vector3(0, 120, 70)

var _stuck_time := 0.0
var _unstuck_cd := 0.0
var _swing_tween: Tween
var _bob_t := 0.0
var hp := 100.0
var hunger := 100.0
var _prev_vy := 0.0
var _hurt_cd := 0.0

const HUNGER_RATE := 0.10      # 每秒掉 0.1，约 16 分钟耗尽
const FALL_SAFE := 11.0        # 低于这个落地速度不掉血
const HUNGER_DAMAGE := 1.2     # 饿到 0 后每秒扣血

signal died
signal damaged(amount: float)

var _probe_t := 0.0
var _bury_count := 0
var _tool: VoxelTool
var held_block: MeshInstance3D
var held_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(70.0)
	floor_snap_length = 0.55
	floor_stop_on_slope = false

	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position.y = 0.875
	add_child(shape)

	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 68.0
	camera.far = 600.0
	camera.near = 0.03
	add_child(camera)

	# 地形区块由 VoxelViewer 驱动，挂在相机（= 玩家眼睛）下
	viewer = VoxelViewer.new()
	viewer.view_distance = 192
	viewer.requires_visuals = true
	viewer.requires_collisions = true
	camera.add_child(viewer)

	if terrain != null:
		_tool = terrain.get_voxel_tool()

	_build_hand()
	apply_look()


func _build_hand() -> void:
	hand_root = Node3D.new()
	hand_root.position = HAND_BASE
	hand_root.rotation = Vector3(0.12, -0.18, 0.0)
	camera.add_child(hand_root)

	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.20, 0.24, 0.30)
	sleeve_mat.roughness = 0.95

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.72, 0.57, 0.47)
	skin_mat.roughness = 0.85

	var tool_mat := StandardMaterial3D.new()
	tool_mat.albedo_color = Color(0.58, 0.61, 0.64)
	tool_mat.metallic = 0.45
	tool_mat.roughness = 0.5

	var sleeve_mesh := BoxMesh.new()
	sleeve_mesh.size = Vector3(0.095, 0.095, 0.32)
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = sleeve_mesh
	sleeve.material_override = sleeve_mat
	sleeve.position = Vector3(0.0, 0.0, 0.16)
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_root.add_child(sleeve)

	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.125, 0.115, 0.16)
	var palm := MeshInstance3D.new()
	palm.mesh = palm_mesh
	palm.material_override = skin_mat
	palm.position = Vector3(0.0, 0.01, -0.08)
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_root.add_child(palm)

	held_mat = StandardMaterial3D.new()
	held_mat.albedo_color = Color(0.45, 0.39, 0.29)
	var held_mesh := BoxMesh.new()
	held_mesh.size = Vector3(0.16, 0.16, 0.16)
	held_block = MeshInstance3D.new()
	held_block.mesh = held_mesh
	held_block.material_override = held_mat
	held_block.position = Vector3(0.0, 0.03, -0.20)
	held_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_root.add_child(held_block)

	var tool_mesh := BoxMesh.new()
	tool_mesh.size = Vector3(0.075, 0.075, 0.20)
	var tool := MeshInstance3D.new()
	tool.mesh = tool_mesh
	tool.material_override = tool_mat
	tool.position = Vector3(0.0, 0.015, -0.21)
	tool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand_root.add_child(tool)


func set_held_color(c: Color, has_item: bool) -> void:
	if held_mat == null or held_block == null:
		return
	held_mat.albedo_color = c
	held_block.visible = has_item


func swing() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	hand_root.rotation = Vector3.ZERO
	_swing_tween = create_tween()
	_swing_tween.tween_property(hand_root, "rotation:x", -0.42, 0.07)
	_swing_tween.tween_property(hand_root, "rotation:x", 0.12, 0.17)


func apply_look() -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var dir := Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y))
	camera.look_at(camera.global_position + dir, Vector3.UP)


func _process(delta: float) -> void:
	# 视角阻尼
	var k := 1.0 - exp(-LOOK_SMOOTH * delta)
	if absf(yaw_target - yaw) > 0.0005 or absf(pitch_target - pitch) > 0.0005:
		yaw = lerpf(yaw, yaw_target, k)
		pitch = lerpf(pitch, pitch_target, k)
		apply_look()

	# 手部走路轻微上下摆
	var speed := Vector2(velocity.x, velocity.z).length()
	_bob_t += delta * (3.0 + speed * 1.1)
	var bob_amp := 0.006 * clampf(speed / WALK_SPEED, 0.0, 1.0)
	hand_root.position = HAND_BASE + Vector3(0.0, sin(_bob_t) * bob_amp, 0.0)


func _physics_process(delta: float) -> void:
	var grounded := is_on_floor()

	if grounded:
		velocity.y = -2.0
	else:
		velocity.y -= GRAVITY * delta

	# 水平移动方向取当前视角朝向（用目标角，响应更快）
	var yr := deg_to_rad(yaw_target)
	var fwd := Vector3(sin(yr), 0.0, cos(yr))
	var right := Vector3(-cos(yr), 0.0, sin(yr))
	var wish := fwd * -input_vec.y + right * input_vec.x
	if wish.length() > 1.0:
		wish = wish.normalized()

	var target := wish * WALK_SPEED
	var accel := 26.0 if grounded else 5.0
	var t := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, target.x, t)
	velocity.z = lerpf(velocity.z, target.z, t)

	# 按住就一直跳（落地立刻再起跳）
	if (jump_held or jump_requested) and grounded:
		velocity.y = JUMP_SPEED
	jump_requested = false

	move_and_slide()

	# 卡住自救：有输入但几乎不动且贴地时，自动小跳一下脱困
	_unstuck_cd = maxf(0.0, _unstuck_cd - delta)
	var wanted := input_vec.length() > 0.1
	var horiz := Vector2(velocity.x, velocity.z).length()
	if wanted and grounded and horiz < 0.7 and _unstuck_cd <= 0.0:
		_stuck_time += delta
		if _stuck_time > 0.22:
			# 先尝试「蹭」上去（小凸起/斜坡），不够再跳
			global_position.y += 0.25
			velocity.y = maxf(velocity.y, 3.0)
			_stuck_time = 0.0
			_unstuck_cd = 0.45
	else:
		_stuck_time = 0.0

	# 被地形吞掉/埋在下面时抬回地表
	_probe_t += delta
	if _probe_t > 0.25:
		_probe_t = 0.0
		_unbury()

	# 饥饿与坠落伤害
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	hunger = maxf(0.0, hunger - delta * HUNGER_RATE)
	if hunger <= 0.0 and _hurt_cd <= 0.0:
		take_damage(delta * HUNGER_DAMAGE, false)

	if grounded and _prev_vy < -FALL_SAFE:
		take_damage((-_prev_vy - FALL_SAFE) * 4.0, false)
	_prev_vy = velocity.y

	if global_position.y < -120.0:
		take_damage(999.0, true)


func take_damage(amount: float, _ignore_cd: bool) -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount)
	if hp <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	hp = minf(100.0, hp + amount)


func feed(amount: float) -> void:
	hunger = minf(100.0, hunger + amount)


func _unbury() -> void:
	# 用小球查询玩家躯干是否和地形重叠：站在地面上不会命中（球心离地 0.9m）
	# 这样在山洞里正常走动不会被误判成「被埋」而弹回地面
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))
	q.exclude = [get_rid()]
	var hits := space.intersect_shape(q, 1)
	if hits.size() == 0:
		_bury_count = 0
		return
	global_position.y += 0.4
	velocity = Vector3.ZERO
	_bury_count += 1
	if _bury_count > 14:
		_bury_count = 0
		respawn()


func respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_point
	hp = 100.0
	hunger = 60.0
