# ============================================================
# patrol_editor.gd
# Attach as a child of your ShopUI / Control node.
# Draws waypoint dots + lines on a CanvasLayer overlay.
# Supports click-to-place waypoints and click-drag rectangles.
# ============================================================
extends Node
class_name PatrolEditor

# ===============================
# SIGNALS
# ===============================
signal patrol_path_set(points: Array)   # emitted when player clicks "Send Patrol"
signal editor_closed

# ===============================
# STATE
# ===============================
var _active         : bool             = false
var _waypoints      : Array[Vector3]   = []   # 3D world points
var _screen_points  : Array[Vector2]   = []   # matching 2D screen positions for drawing

var _drag_start_screen : Vector2 = Vector2.ZERO
var _drag_start_world  : Vector3 = Vector3.ZERO
var _is_dragging       : bool    = false
var _drag_threshold    : float   = 12.0   # pixels before drag is detected

var _camera  : Camera3D = null
var _overlay : Control  = null   # transparent Control for drawing + input

# Buttons owned by this editor (added to shop UI externally)
var btn_set_patrol  : Button = null
var btn_send_patrol : Button = null
var btn_clear       : Button = null
var btn_close       : Button = null
var _status_label   : Label  = null

# ===============================
# INIT — call from shop after _build_shop_ui
# ===============================
func init(camera: Camera3D, status_lbl: Label) -> void:
	_camera       = camera
	_status_label = status_lbl
	_build_overlay()

func _build_overlay() -> void:
	# Full-screen transparent Control that sits on top
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible      = false
	_overlay.z_index      = 200
	# Connect drawing and input
	_overlay.draw.connect(_on_overlay_draw)
	_overlay.gui_input.connect(_on_overlay_input)
	# Add to scene root so it covers everything
	Engine.get_main_loop().current_scene.add_child(_overlay)

# ===============================
# OPEN / CLOSE
# ===============================
func open() -> void:
	_active          = true
	_overlay.visible = true
	_overlay.queue_redraw()
	_update_status("Click: add waypoint   |   Click+drag: draw rectangle   |   Right-click: remove last   |   Esc: close")
	if btn_send_patrol:
		btn_send_patrol.disabled = _waypoints.is_empty()

func close() -> void:
	_active          = false
	_overlay.visible = false
	editor_closed.emit()

func clear_waypoints() -> void:
	_waypoints.clear()
	_screen_points.clear()
	_overlay.queue_redraw()
	if btn_send_patrol: btn_send_patrol.disabled = true
	_update_status("Waypoints cleared.")

# ===============================
# INPUT
# ===============================
func _on_overlay_input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
			return
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_remove_last_waypoint()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_remove_last_waypoint()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_start_screen = event.position
				_drag_start_world  = _screen_to_world(event.position)
				_is_dragging       = false
			else:
				# Released
				if _is_dragging:
					_finish_rect_drag(event.position)
				else:
					_add_waypoint_at_screen(event.position)
				_is_dragging = false
				_overlay.queue_redraw()

	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var dist : float = event.position.distance_to(_drag_start_screen)
			if dist > _drag_threshold:
				_is_dragging = true
				_overlay.queue_redraw()

# ===============================
# WAYPOINT MANAGEMENT
# ===============================
func _add_waypoint_at_screen(screen_pos: Vector2) -> void:
	var world := _screen_to_world(screen_pos)
	if world == Vector3.ZERO:
		return
	_waypoints.append(world)
	_screen_points.append(screen_pos)
	_overlay.queue_redraw()
	if btn_send_patrol: btn_send_patrol.disabled = false
	_update_status("Waypoint %d added. Click 'Send Patrol' to apply." % _waypoints.size())

func _remove_last_waypoint() -> void:
	if _waypoints.is_empty():
		return
	_waypoints.pop_back()
	_screen_points.pop_back()
	_overlay.queue_redraw()
	if btn_send_patrol: btn_send_patrol.disabled = _waypoints.is_empty()
	_update_status("Removed last waypoint. %d remaining." % _waypoints.size())

func _finish_rect_drag(end_screen: Vector2) -> void:
	# Generate 4 corners of the rectangle in world space
	var corners_screen : Array[Vector2] = [
		_drag_start_screen,
		Vector2(end_screen.x, _drag_start_screen.y),
		end_screen,
		Vector2(_drag_start_screen.x, end_screen.y),
	]
	var added := 0
	for sc in corners_screen:
		var w := _screen_to_world(sc)
		if w != Vector3.ZERO:
			_waypoints.append(w)
			_screen_points.append(sc)
			added += 1
	if added > 0:
		_overlay.queue_redraw()
		if btn_send_patrol: btn_send_patrol.disabled = false
		_update_status("Rectangle added (%d corners). Click 'Send Patrol' to apply." % added)

# ===============================
# SEND TO CREEPS
# ===============================
func send_patrol() -> void:
	if _waypoints.is_empty():
		_update_status("No waypoints set!")
		return
	patrol_path_set.emit(_waypoints.duplicate())
	_update_status("✓ Patrol path sent to %d waypoints." % _waypoints.size())

# ===============================
# DRAW OVERLAY
# ===============================
func _on_overlay_draw() -> void:
	if not _active:
		return

	var dot_color  := Color(0.2, 0.8, 1.0, 0.95)
	var line_color := Color(0.2, 0.8, 1.0, 0.55)
	var rect_color := Color(1.0, 0.85, 0.2, 0.35)
	var dot_radius := 8.0

	# Draw connecting lines
	for i in range(1, _screen_points.size()):
		_overlay.draw_line(_screen_points[i - 1], _screen_points[i], line_color, 2.0)

	# Close the loop if 3+ points
	if _screen_points.size() >= 3:
		_overlay.draw_line(_screen_points[-1], _screen_points[0], Color(line_color, 0.3), 1.5)

	# Draw waypoint dots
	for i in _screen_points.size():
		var sp := _screen_points[i]
		_overlay.draw_circle(sp, dot_radius, dot_color)
		_overlay.draw_circle(sp, dot_radius + 2.0, Color(dot_color, 0.3))
		# Index label
		_overlay.draw_string(
			ThemeDB.fallback_font,
			sp + Vector2(-4, 5),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, 13,
			Color.BLACK
		)

	# Draw drag rectangle preview
	if _is_dragging:
		var mouse_pos := _overlay.get_local_mouse_position()
		var rect      := Rect2(_drag_start_screen, mouse_pos - _drag_start_screen).abs()
		_overlay.draw_rect(rect, rect_color)
		_overlay.draw_rect(rect, Color(1.0, 0.85, 0.2, 0.8), false, 2.0)

# ===============================
# UTIL
# ===============================
func _screen_to_world(screen_pos: Vector2) -> Vector3:
	if not is_instance_valid(_camera):
		return Vector3.ZERO
	var from   := _camera.project_ray_origin(screen_pos)
	var to     := from + _camera.project_ray_normal(screen_pos) * 300.0
	var space  := _camera.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	var result := space.intersect_ray(params)
	return result.get("position", Vector3.ZERO)

func _update_status(text: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = text
