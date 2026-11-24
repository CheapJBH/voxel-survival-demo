class_name Enemy
extends CharacterBody3D
## 夜行方块怪：直线追玩家，靠近就咬

const SPEED := 3.4
const GRAVITY := 25.0
const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 9.0
const ATTACK_CD := 1.1

var target: Node3D
var hp := 30.0
var _attack_t := 0.0
var _body_root: Node3D
var on_death: Callable


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(70.0)
	floor_snap_length = 0.4

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.45, 0.8)
	shape.shape = box
	shape.position.y = 0.725
	add_child(shape)

	_build_model()


func _build_model() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.14, 0.18)
	dark.roughness = 0.9

	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.28, 0.22)

	# 躯干
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.72, 1.0, 0.55)
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = dark
	body.position = Vector3(0, 0.62, 0)
	_body_root.add_child(body)

	# 头
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.62, 0.52, 0.55)
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = dark
	head.position = Vector3(0, 1.36, 0)
	_body_root.add_child(head)

	# 眼睛
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.13, 0.10, 0.06)
	for sx in [-0.14, 0.14]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(sx, 1.40, 0.29)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body_root.add_child(eye)


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = -2.0
	else:
		velocity.y -= GRAVITY * delta

	if target != null and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.6:
			var dir := to / dist
			velocity.x = dir.x * SPEED
			velocity.z = dir.z * SPEED
			# 朝向玩家
			var want := atan2(dir.x, dir.z)
			_boot_rotation(want, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

		move_and_slide()

		_attack_t = maxf(0.0, _attack_t - delta)
		if dist < ATTACK_RANGE and _attack_t <= 0.0:
			_attack_t = ATTACK_CD
			if target.has_method("take_damage"):
				target.take_damage(ATTACK_DAMAGE, false)
	else:
		move_and_slide()


func _boot_rotation(want: float, delta: float) -> void:
	if _body_root == null:
		return
	_body_root.rotation.y = lerp_angle(_body_root.rotation.y, want, 1.0 - exp(-8.0 * delta))


func take_damage(amount: float, _x: bool = false) -> void:
	hp -= amount
	# 受击闪白
	if _body_root != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.25, 0.25)
		for c in _body_root.get_children():
			if c is MeshInstance3D and c.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				c.material_override = mat
	if hp <= 0.0:
		if on_death.is_valid():
			on_death.call(global_position)
		queue_free()
