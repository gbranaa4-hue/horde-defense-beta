# ============================================================
# GameOverScreen.gd
# ============================================================
# Add as an autoload OR child of your main scene.
# Call GameOverScreen.show_result(winning_team, local_team)
# from your base _on_died() handler.
# ============================================================
extends CanvasLayer

var _panel : Control = null
var _tween : Tween = null


func _ready() -> void:
	layer = 100
	_build()
	_hide_screen()
	
	# Ensure we're visible after building
	visible = true
	_panel.visible = false


func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.88)
	_panel.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.anchor_top = 0.4  # Move up a bit
	vbox.anchor_bottom = 0.6
	vbox.add_theme_constant_override("separation", 28)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = ""
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.name = "Sub"
	sub.text = ""
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var btn_retry := _make_btn("↺  PLAY AGAIN", Color(0.15, 0.38, 0.22))
	var btn_quit := _make_btn("✕  QUIT", Color(0.25, 0.08, 0.08))
	btn_retry.pressed.connect(_on_retry)
	btn_quit.pressed.connect(_on_quit)
	btn_row.add_child(btn_retry)
	btn_row.add_child(btn_quit)


func _make_btn(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 60)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	s.set_content_margin_all(12)
	b.add_theme_stylebox_override("normal", s)
	
	var h := StyleBoxFlat.new()
	h.bg_color = color.lightened(0.2)
	h.set_corner_radius_all(4)
	h.set_content_margin_all(12)
	b.add_theme_stylebox_override("hover", h)
	
	var p := StyleBoxFlat.new()
	p.bg_color = color.lightened(0.3)
	p.set_corner_radius_all(4)
	p.set_content_margin_all(12)
	b.add_theme_stylebox_override("pressed", p)
	
	return b


# Call this from your base _on_died():
# GameOverScreen.show_result(winning_team_id, local_player_team_id)
func show_result(winning_team: int, local_team: int) -> void:
	# Find nodes safely
	var title_node = _find_child_recursive(_panel, "Title")
	var sub_node = _find_child_recursive(_panel, "Sub")
	
	if not title_node or not sub_node:
		push_error("[GameOverScreen] Could not find UI nodes")
		return

	var won = (winning_team == local_team)

	if won:
		title_node.text = "VICTORY!"
		title_node.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
		sub_node.text = "The darkness bows to you.\nYour enemies are ash."
	else:
		title_node.text = "YOU FAILED"
		title_node.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
		sub_node.text = "The night consumed you.\nThere is no hope here."

	# Kill any existing tween
	if _tween and _tween.is_valid():
		_tween.kill()
	
	# Show panel
	_panel.modulate.a = 0.0
	_panel.visible = true
	
	# Pause AFTER setting up visuals, but before tween
	get_tree().paused = true
	
	# Fade in
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.8)
	
	# Ensure mouse can interact with buttons
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in _panel.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if child is Button or (child is Control and child.get_child_count() > 0):
			_set_mouse_filter_recursive(child, Control.MOUSE_FILTER_STOP)


func _find_child_recursive(node: Node, name: String):
	"""Recursively find a child by name"""
	if node.name == name:
		return node
	for child in node.get_children():
		var found = _find_child_recursive(child, name)
		if found:
			return found
	return null


func _set_mouse_filter_recursive(node: Node, filter: int):
	"""Set mouse filter on node and all children"""
	if node is Control:
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)


func _hide_screen() -> void:
	"""Hide the game over screen"""
	if _panel:
		_panel.visible = false
		_panel.modulate.a = 0.0


func _on_retry() -> void:
	# Clean up tween
	if _tween and _tween.is_valid():
		_tween.kill()
	
	# Unpause before reloading
	get_tree().paused = false
	
	# Hide immediately to prevent flicker
	_panel.visible = false
	
	# Reload the scene
	get_tree().reload_current_scene()


func _on_quit() -> void:
	# Clean up
	if _tween and _tween.is_valid():
		_tween.kill()
	
	# Unpause
	get_tree().paused = false
	
	# Quit the game
	get_tree().quit()
