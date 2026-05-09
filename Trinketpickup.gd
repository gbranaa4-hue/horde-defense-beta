# ============================================================
# TrinketPickup.gd
# ============================================================
extends Area3D

@export var ability_data : Dictionary = {}
@export var team_id      : int        = 0   # 0 = any team

var _picked : bool  = false
var _bob_t  : float = 0.0
var _mesh   : MeshInstance3D = null
var _label  : Label3D        = null


func _ready() -> void:
	collision_layer = 0
	collision_mask  = 1
	body_entered.connect(_on_body_entered)
	add_to_group("trinkets")
	_build_visual()
	if not ability_data.is_empty():
		_apply_ability_data()


func setup(data: Dictionary, tid: int = 0) -> void:
	ability_data = data
	team_id      = tid
	if is_inside_tree():
		_apply_ability_data()


func _build_visual() -> void:
	_mesh       = MeshInstance3D.new()
	var box     := BoxMesh.new()
	box.size    = Vector3(0.45, 0.45, 0.45)
	_mesh.mesh  = box
	add_child(_mesh)

	var col        := CollisionShape3D.new()
	var sphere     := SphereShape3D.new()
	sphere.radius  = 1.0
	col.shape      = sphere
	add_child(col)

	_label                      = Label3D.new()
	_label.position             = Vector3(0.0, 1.2, 0.0)
	_label.pixel_size           = 0.007
	_label.billboard            = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test        = true
	_label.outline_size         = 5
	_label.outline_modulate     = Color(0.0, 0.0, 0.0, 0.85)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)

	_set_color(Color(0.8, 0.8, 0.8))
	_label.text = "Trinket"


func _apply_ability_data() -> void:
	if ability_data.is_empty(): return
	var slot     : int    = int(ability_data.get("slot", 0))
	var tier     : int    = int(ability_data.get("tier", 0))
	var name_str : String = ability_data.get("name", "Trinket")
	var desc_str : String = ability_data.get("desc", "")

	var slot_colors : Array = [Color(1.0,0.28,0.08), Color(0.18,0.48,1.00), Color(0.12,0.92,0.42)]
	_set_color(slot_colors[clampi(slot, 0, 2)])

	var stars : String = ["★","★★","★★★","★★★★"][clampi(tier, 0, 3)]
	var text  : String = name_str + "\n" + stars
	if desc_str.length() > 0:
		text += "\n" + (desc_str if desc_str.length() <= 42 else desc_str.left(40) + "…")
	_label.text     = text
	_label.modulate = Color.WHITE


func _set_color(c: Color) -> void:
	if not is_instance_valid(_mesh): return
	var mat                  := StandardMaterial3D.new()
	mat.albedo_color          = c
	mat.emission_enabled      = true
	mat.emission              = c * 0.55
	_mesh.material_override   = mat


func _process(delta: float) -> void:
	if _picked: return
	_bob_t += delta * 1.6
	if is_instance_valid(_mesh):
		_mesh.position.y = sin(_bob_t) * 0.12
		_mesh.rotate_y(delta * 1.4)


func _on_body_entered(body: Node) -> void:
	if _picked: return
	if not body.is_in_group("player"): return
	# team_id == 0 → any team can pick up
	if team_id != 0:
		var bt : int = int(body.get("team_id") if "team_id" in body else -1)
		if bt != team_id: return

	_picked = true

	var slot : int = int(ability_data.get("slot", 0))
	var pid  : int = int(body.get("player_id") if "player_id" in body else 0)

	# Get TalentTree autoload
	var tt : Node = get_node_or_null("/root/TalentTree")
	if not is_instance_valid(tt):
		tt = get_tree().get_first_node_in_group("talent_tree")

	# ── FIX: Unlock tier FIRST, THEN equip ───────────────────
	# This ensures HUD refresh sees the correct new tier.
	if is_instance_valid(tt) and tt.has_method("on_trinket_collected"):
		tt.on_trinket_collected(body, ability_data)

	# Check if player queued a specific ability for this slot
	var equip_data : Dictionary = ability_data.duplicate()
	if is_instance_valid(tt) and tt.has_method("get_queued"):
		var q : Dictionary = tt.get_queued(pid)
		if not q.is_empty() and int(q.get("slot", -1)) == slot:
			equip_data = q
			tt.clear_queued(pid)

	# Equip on player
	if body.has_method("equip_ability"):
		body.equip_ability(slot, equip_data)
	elif body.has_method("on_trinket_pickup"):
		body.on_trinket_pickup(equip_data, slot)

	_pickup_effect()
	await get_tree().create_timer(0.12).timeout
	queue_free()


func _pickup_effect() -> void:
	if is_instance_valid(_mesh):  _mesh.visible  = false
	if is_instance_valid(_label): _label.visible = false
	var snd := get_node_or_null("PickupSound") as AudioStreamPlayer3D
	if is_instance_valid(snd): snd.play()

	var slot  : int   = int(ability_data.get("slot", 0))
	var slot_colors : Array = [Color(1.0,0.28,0.08), Color(0.18,0.48,1.0), Color(0.12,0.92,0.42)]
	var color : Color = slot_colors[clampi(slot, 0, 2)]

	var p  := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction              = Vector3(0,1,0)
	pm.spread                 = 55.0
	pm.initial_velocity_min   = 2.0
	pm.initial_velocity_max   = 5.0
	pm.gravity                = Vector3(0,-5,0)
	pm.color                  = color
	p.process_material        = pm
	p.amount                  = 18
	p.one_shot                = true
	p.lifetime                = 0.7
	p.emitting                = true
	p.global_position         = global_position
	get_parent().add_child(p)
	get_tree().create_timer(1.2).timeout.connect(
		func(): if is_instance_valid(p): p.queue_free())
