extends Control
## 开始界面：极简，两个选择（继续 / 新世界）

const PLAYER_SAVE := "user://player.json"
const SAVE_DIR := "user://world"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var title := Label.new()
	title.text = "方 块 生 存"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.93, 0.94, 0.90))
	root.add_child(title)

	var sub := Label.new()
	sub.text = "白天收集，天黑之前回家"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.60, 0.64, 0.60))
	root.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	root.add_child(spacer)

	var has_save := FileAccess.file_exists(PLAYER_SAVE)
	if has_save:
		root.add_child(_make_button("继 续", func() -> void:
			get_tree().change_scene_to_file("res://main.tscn")
		))

	root.add_child(_make_button("新 世 界", func() -> void:
		_wipe_save()
		get_tree().change_scene_to_file("res://main.tscn")
	))

	var hint := Label.new()
	hint.text = "左半屏走动 · 右半屏转视角 · 右下挖/填/跳"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.42, 0.46, 0.44))
	root.add_child(hint)


func _make_button(text: String, on_press: Callable) -> Control:
	var wrapper := CenterContainer.new()
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 62)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(0.92, 0.93, 0.90))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.75, 0.78, 0.74))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.07)
	normal.border_color = Color(1, 1, 1, 0.18)
	normal.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.14)
	hover.border_color = Color(1, 1, 1, 0.35)
	hover.set_border_width_all(1)
	b.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1, 1, 1, 0.22)
	pressed.set_border_width_all(1)
	pressed.border_color = Color(1, 1, 1, 0.45)
	b.add_theme_stylebox_override("pressed", pressed)

	b.pressed.connect(on_press)
	wrapper.add_child(b)
	return wrapper


func _wipe_save() -> void:
	if FileAccess.file_exists(PLAYER_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYER_SAVE))
	var abs_dir := ProjectSettings.globalize_path(SAVE_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		_delete_recursive(abs_dir)


func _delete_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name == "." or name == "..":
			name = da.get_next()
			continue
		var p := path.path_join(name)
		if da.current_is_dir():
			_delete_recursive(p)
		else:
			DirAccess.remove_absolute(p)
		name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
