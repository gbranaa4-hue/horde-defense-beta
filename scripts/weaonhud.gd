# ============================================================
# weapon_hud.gd
# Reads from WeaponManager each frame and displays:
# - Current weapon name
# - Current ammo / max ammo
# Anchored bottom-right corner
# ============================================================
extends Control

# ===============================
# NODES — built in code, no scene needed
# ===============================
var _panel       : PanelContainer
var _weapon_name : Label
var _ammo_label  : Label
var _manager     : WeaponManager = null

# ===============================
# READY
# ===============================
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	# Find WeaponManager in parent chain or tree
	await get_tree().process_frame
	_manager = _find_weapon_manager()

# ===============================
# BUILD UI
# ===============================
func _build_ui() -> void:
	# Anchor bottom-right
	anchor_left   = 1.0
	anchor_top    = 1.0
	anchor_right  = 1.0
	anchor_bottom = 1.0
	offset_left   = -240.0
	offset_top    = -90.0
	offset_right  = -20.0
	offset_bottom = -20.0

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Semi-transparent background
	var style := StyleBoxFlat.new()
	style.bg_color        = Color(0.0, 0.0, 0.0, 0.55)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_weapon_name = Label.new()
	_weapon_name.text = "No Weapon"
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_name.add_theme_font_size_override("font_size", 15)
	_weapon_name.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_weapon_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_weapon_name)

	_ammo_label = Label.new()
	_ammo_label.text = "-- / --"
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 26)
	_ammo_label.add_theme_color_override("font_color", Color.WHITE)
	_ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_ammo_label)

# ===============================
# PROCESS — poll weapon manager
# ===============================
func _process(_delta: float) -> void:
	if not is_instance_valid(_manager):
		_manager = _find_weapon_manager()
		return

	var gun := _manager.get_current_weapon()
	if not is_instance_valid(gun):
		_weapon_name.text = "No Weapon"
		_ammo_label.text  = "-- / --"
		return

	# Weapon name from node name, cleaned up
	_weapon_name.text = gun.name.replace("_", " ")

	# Ammo — read common property names used in BaseGun patterns
	var current_ammo : int = -1
	var max_ammo     : int = -1

	if "current_ammo"   in gun: current_ammo = gun.current_ammo
	elif "ammo"         in gun: current_ammo = gun.ammo
	elif "bullets"      in gun: current_ammo = gun.bullets

	if "max_ammo"       in gun: max_ammo = gun.max_ammo
	elif "clip_size"    in gun: max_ammo = gun.clip_size
	elif "magazine_size"in gun: max_ammo = gun.magazine_size

	if current_ammo == -1 and max_ammo == -1:
		_ammo_label.text = "∞"
	elif max_ammo == -1:
		_ammo_label.text = str(current_ammo)
	else:
		# Color ammo red when low (under 25%)
		var ratio := float(current_ammo) / float(max_ammo) if max_ammo > 0 else 1.0
		var col   := Color.WHITE
		if ratio <= 0.25:
			col = Color(1.0, 0.3, 0.3)
		elif ratio <= 0.5:
			col = Color(1.0, 0.8, 0.2)
		_ammo_label.add_theme_color_override("font_color", col)
		_ammo_label.text = "%d / %d" % [current_ammo, max_ammo]

# ===============================
# FIND WEAPON MANAGER
# ===============================
func _find_weapon_manager() -> WeaponManager:
	# Walk up from CanvasLayer to player, then search downward
	var player := get_tree().get_first_node_in_group("players")
	if not is_instance_valid(player):
		return null
	return _search_for_manager(player)

func _search_for_manager(node: Node) -> WeaponManager:
	if node is WeaponManager:
		return node as WeaponManager
	for child in node.get_children():
		var result := _search_for_manager(child)
		if result:
			return result
	return null
