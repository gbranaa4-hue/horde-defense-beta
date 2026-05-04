# ─────────────────────────────────────────────────────────────
# PATCH 1 — player.gd
# In _input(), the existing guard already handles this:
#   if is_dead or ui_opened: return
# That means when the shop sets ui_opened = true, the player
# will NOT call _toggle_mouse() or do any mouse look.
# NO CHANGE NEEDED to player.gd — it already works correctly.
# ─────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────
# PATCH 2 — camera.gd  (the Node3D camera script)
# The camera's _unhandled_input runs even when the shop is open.
# Add a shop_open guard so it stops consuming mouse input.
# ─────────────────────────────────────────────────────────────

# REPLACE your entire camera.gd with this:

extends Node3D

@export var mouse_sensitivity := 0.3
@export var pitch_limit := 80.0
var pitch  := 0.0
var player: CharacterBody3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	player = get_tree().get_first_node_in_group("players")

func _unhandled_input(event):
	# ── GUARD: if the player has the shop open, do nothing ──────
	# shop_ui.gd sets player.ui_opened = true when open,
	# and releases the mouse to VISIBLE — both conditions block us.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if player and "ui_opened" in player and player.ui_opened:
		return
	# ────────────────────────────────────────────────────────────

	if event is InputEventMouseMotion:
		if player:
			player.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity, -pitch_limit, pitch_limit)
		rotation_degrees.x = pitch

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
