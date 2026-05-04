# ============================================================
# hud.gd
# ============================================================
extends Control
class_name HUD

# ===============================
# UI ELEMENTS
# ===============================
var health_bar        : ProgressBar
var health_label      : Label
var base_health_bar   : ProgressBar
var base_health_label : Label
var ammo_label        : Label
var gun_name_label    : Label
var zombies_label     : Label
var money_label       : Label
var prep_timer_label  : Label
var ready_button      : Button
var crosshair         : Label
var _hurt_flash       : ColorRect = null
var _flash_tween      : Tween     = null

# ===============================
# GAME REFS
# ===============================
var player       : Node = null
var base         : Node = null
var game_manager : Node = null
var team_id      : int  = 1
var current_gun  : Node = null

# ===============================
# STATE
# ===============================
var is_ready    : bool = false
var shop_open   : bool = false
var prep_active : bool = true

var _last_enemy_count : int   = -1
var _last_ammo        : int   = -1
var _last_max_ammo    : int   = -1
var _last_hp          : float = -1.0
var _last_max_hp      : float = -1.0
var _last_base_hp     : float = -1.0
var _last_base_max_hp : float = -1.0

# ===============================
# READY
# ===============================
func _ready() -> void:
	print("HUD INIT")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	visible = true

	_build_ui()
	await get_tree().process_frame
	add_to_group("ui")
	_find_refs()
	_connect_signals()
	_sync_all()

	print("HUD READY")

# ===============================
# BUILD UI
# ===============================
func _build_ui() -> void:
	var top_left := VBoxContainer.new()
	top_left.anchor_left = 0.02
	top_left.anchor_top  = 0.02
	add_child(top_left)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(220, 18)
	top_left.add_child(health_bar)

	health_label = Label.new()
	top_left.add_child(health_label)

	base_health_bar = ProgressBar.new()
	base_health_bar.custom_minimum_size = Vector2(220, 14)
	top_left.add_child(base_health_bar)

	base_health_label = Label.new()
	top_left.add_child(base_health_label)

	var top_right := VBoxContainer.new()
	top_right.anchor_left = 0.75
	top_right.anchor_top  = 0.02
	add_child(top_right)

	money_label      = Label.new()
	top_right.add_child(money_label)

	zombies_label    = Label.new()
	top_right.add_child(zombies_label)

	prep_timer_label = Label.new()
	top_right.add_child(prep_timer_label)

	var bottom_left := VBoxContainer.new()
	bottom_left.anchor_left = 0.02
	bottom_left.anchor_top  = 0.80
	add_child(bottom_left)

	gun_name_label = Label.new()
	bottom_left.add_child(gun_name_label)

	ammo_label = Label.new()
	bottom_left.add_child(ammo_label)

	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 28)

	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical   = Control.GROW_DIRECTION_BOTH

	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	crosshair.custom_minimum_size = Vector2(32, 32)
	crosshair.position            = Vector2(-16, -16)

	add_child(crosshair)

	ready_button = Button.new()
	ready_button.text          = "READY"
	ready_button.anchor_left   = 0.4
	ready_button.anchor_top    = 0.9
	ready_button.anchor_right  = 0.6
	ready_button.anchor_bottom = 0.97
	add_child(ready_button)

	# Hurt flash — full screen red overlay, drawn on top of everything
	_hurt_flash               = ColorRect.new()
	_hurt_flash.color         = Color(1, 0, 0, 0)
	_hurt_flash.anchor_left   = 0.0
	_hurt_flash.anchor_top    = 0.0
	_hurt_flash.anchor_right  = 1.0
	_hurt_flash.anchor_bottom = 1.0
	_hurt_flash.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_hurt_flash.z_index       = 50
	add_child(_hurt_flash)

# ===============================
# FIND REFS
# ===============================
func _find_refs() -> void:
	player       = get_tree().get_first_node_in_group("players")
	game_manager = get_tree().get_first_node_in_group("game_manager")

	if is_instance_valid(player) and "team_id" in player:
		team_id = player.team_id

	for b in get_tree().get_nodes_in_group("bases"):
		if is_instance_valid(b) and b.get("team_id") == team_id:
			base = b
			break

	if is_instance_valid(base):
		print("HUD: base found — ", base.name)
	else:
		push_warning("HUD: no base found for team_id %d" % team_id)

# ===============================
# CONNECT SIGNALS
# ===============================
func _connect_signals() -> void:
	if is_instance_valid(player):
		_try_connect(player, "health_changed", _on_player_health_changed)

	if is_instance_valid(base):
		_try_connect(base, "health_changed", _on_base_health_changed)

	if is_instance_valid(game_manager):
		_try_connect(game_manager, "money_changed",        _on_money_changed)
		_try_connect(game_manager, "prep_time_updated",    _on_prep_time_updated)
		_try_connect(game_manager, "ready_updated",        _on_ready_updated)
		_try_connect(game_manager, "match_started_signal", _on_match_started)

	if is_instance_valid(ready_button):
		_try_connect(ready_button, "pressed", _on_ready_pressed)

	if is_instance_valid(player) and "weapon_manager" in player:
		var wm : Node = player.weapon_manager
		if is_instance_valid(wm):
			_try_connect(wm, "weapon_changed", _on_weapon_changed)

func _try_connect(node: Node, sig: String, callable: Callable) -> void:
	if not node.has_signal(sig):
		return
	var s : Signal = node.get(sig)
	if not s.is_connected(callable):
		s.connect(callable)

# ===============================
# INITIAL SYNC
# ===============================
func _sync_all() -> void:
	if is_instance_valid(player):
		var hp  : float = _get_float(player, "health")
		var mhp : float = _get_float(player, "max_health")
		if mhp > 0.0:
			_update_player_health(hp, mhp)

	if is_instance_valid(base):
		var bhp  : float = _get_float(base, "health_value")
		var bmhp : float = _get_float(base, "max_health")
		if bmhp > 0.0:
			_update_base_health(bhp, bmhp)
		else:
			await get_tree().process_frame
			_update_base_health(
				_get_float(base, "health_value"),
				_get_float(base, "max_health")
			)

	if is_instance_valid(game_manager):
		_on_money_changed(team_id, game_manager.get_gold(team_id))

	if is_instance_valid(player) and "weapon_manager" in player:
		var wm : Node = player.weapon_manager
		if is_instance_valid(wm) and wm.has_method("get_current_weapon"):
			var gun = wm.get_current_weapon()
			if is_instance_valid(gun):
				_apply_gun(gun)

# ===============================
# PROCESS — polling fallbacks
# ===============================
func _process(_delta: float) -> void:
	if is_instance_valid(crosshair):
		crosshair.visible = not shop_open

	var enemy_count := _count_enemies()
	if enemy_count != _last_enemy_count:
		_last_enemy_count  = enemy_count
		zombies_label.text = "Enemies: %d" % enemy_count

	if is_instance_valid(player):
		var hp  : float = _get_float(player, "health")
		var mhp : float = _get_float(player, "max_health")
		if hp != _last_hp or mhp != _last_max_hp:
			_on_player_health_changed(hp, mhp)

	if is_instance_valid(base):
		var bhp  : float = _get_float(base, "health_value")
		var bmhp : float = _get_float(base, "max_health")
		if bhp != _last_base_hp or bmhp != _last_base_max_hp:
			_on_base_health_changed(bhp, bmhp)

	_poll_ammo()

# ===============================
# HEALTH CALLBACKS
# ===============================
func _on_player_health_changed(cur: float, max_val: float) -> void:
	if _last_hp > 0.0 and cur < _last_hp:
		_trigger_hurt_flash()
	_update_player_health(cur, max_val)

func _update_player_health(cur: float, max_val: float) -> void:
	_last_hp             = cur
	_last_max_hp         = max_val
	health_bar.max_value = max_val
	health_bar.value     = cur
	health_label.text    = "HP: %d / %d" % [int(cur), int(max_val)]

func _on_base_health_changed(cur: float, max_val: float) -> void:
	_update_base_health(cur, max_val)

func _update_base_health(cur: float, max_val: float) -> void:
	if max_val <= 0.0:
		return
	_last_base_hp             = cur
	_last_base_max_hp         = max_val
	base_health_bar.max_value = max_val
	base_health_bar.value     = cur
	base_health_label.text    = "Base: %d / %d" % [int(cur), int(max_val)]

# ===============================
# HURT FLASH
# ===============================
func _trigger_hurt_flash() -> void:
	if not is_instance_valid(_hurt_flash):
		return
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_hurt_flash.color = Color(1, 0, 0, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_hurt_flash, "color", Color(1, 0, 0, 0), 0.4)

# ===============================
# WEAPON
# ===============================
func _on_weapon_changed(gun: Node) -> void:
	_apply_gun(gun)

func _apply_gun(gun: Node) -> void:
	current_gun    = gun
	_last_ammo     = -1
	_last_max_ammo = -1

	if not is_instance_valid(gun):
		gun_name_label.text = "Gun: None"
		ammo_label.text     = "Ammo: -"
		return

	gun_name_label.text = "Gun: %s" % gun.name.replace("_", " ")

	if gun.has_signal("ammo_changed"):
		var sig : Signal = gun.ammo_changed
		if not sig.is_connected(_on_ammo_changed):
			sig.connect(_on_ammo_changed)

	_poll_ammo()

func _poll_ammo() -> void:
	if not is_instance_valid(current_gun):
		return

	var a : int = -1
	if "current_ammo" in current_gun:
		a = _get_int(current_gun, "current_ammo")
	elif "ammo" in current_gun:
		a = _get_int(current_gun, "ammo")

	if a == -1:
		return

	var ma : int = _get_int(current_gun, "max_ammo") if "max_ammo" in current_gun else -1

	if a != _last_ammo or ma != _last_max_ammo:
		_on_ammo_changed(a, ma)

func _on_ammo_changed(cur: int, max_val: int) -> void:
	_last_ammo     = cur
	_last_max_ammo = max_val

	if max_val <= 0:
		ammo_label.add_theme_color_override("font_color", Color.WHITE)
		ammo_label.text = "Ammo: %d" % cur
		return

	var ratio : float = float(cur) / float(max_val)
	var col   : Color = Color.WHITE
	if ratio   <= 0.25: col = Color(1.0, 0.3, 0.3)
	elif ratio <= 0.5:  col = Color(1.0, 0.8, 0.2)
	ammo_label.add_theme_color_override("font_color", col)
	ammo_label.text = "Ammo: %d / %d" % [cur, max_val]

# ===============================
# MONEY + TIMER
# ===============================
func _on_money_changed(t: int, amount: int) -> void:
	if t != team_id:
		return
	money_label.text = "Gold: %d" % amount

func _on_prep_time_updated(t: float) -> void:
	var total := int(t)
	prep_timer_label.text = "Prep: %02d:%02d" % [total / 60, total % 60]

# ===============================
# READY / MATCH
# ===============================
func _on_ready_updated(t: int, ready: bool) -> void:
	if t != team_id:
		return
	is_ready              = ready
	ready_button.text     = "READY ✓"
	ready_button.disabled = true

func _on_match_started() -> void:
	prep_active = false
	if is_instance_valid(ready_button):
		ready_button.hide()
		ready_button.queue_free()
	prep_timer_label.text = "⚔ FIGHT"

func _on_ready_pressed() -> void:
	if is_ready:
		return
	is_ready              = true
	ready_button.text     = "READY ✓"
	ready_button.disabled = true
	if is_instance_valid(game_manager):
		game_manager.set_team_ready(team_id, true)

# ===============================
# UPGRADE REFRESH
# ===============================
func refresh_after_upgrade() -> void:
	_last_hp          = -1.0
	_last_max_hp      = -1.0
	_last_base_hp     = -1.0
	_last_base_max_hp = -1.0
	_last_ammo        = -1
	_last_max_ammo    = -1

# ===============================
# STATUS FLASH
# ===============================
func show_status(text: String) -> void:
	if not is_instance_valid(gun_name_label):
		return
	var original := gun_name_label.text
	gun_name_label.text = text
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(gun_name_label):
		gun_name_label.text = original

# ===============================
# UTILS
# ===============================
func _get_float(node: Node, prop: String) -> float:
	if not is_instance_valid(node) or not (prop in node):
		return 0.0
	var val = node.get(prop)
	match typeof(val):
		TYPE_NIL:    return 0.0
		TYPE_INT:    return float(val)
		TYPE_FLOAT:  return val
		TYPE_STRING: return val.to_float()
		_:           return 0.0

func _get_int(node: Node, prop: String) -> int:
	if not is_instance_valid(node) or not (prop in node):
		return 0
	var val = node.get(prop)
	match typeof(val):
		TYPE_NIL:    return 0
		TYPE_INT:    return val
		TYPE_FLOAT:  return int(val)
		TYPE_STRING: return val.to_int()
		_:           return 0

func _count_enemies() -> int:
	var count := 0
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and u.get("team_id") != team_id:
			count += 1
	return count
