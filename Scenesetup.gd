# ============================================================
# SceneSetup.gd — AUTOLOAD
# ============================================================
extends Node


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_bases()
	_setup_players()
	print("[SceneSetup] Done.")


# ── Bases ─────────────────────────────────────────────────────
func _setup_bases() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene): return

	for pair in [["Base", 1], ["Base2", 2], ["base", 1], ["base2", 2],
				 ["base1", 1], ["Base1", 1]]:
		var node := scene.find_child(pair[0], true, false) as Node
		if not is_instance_valid(node): continue
		if not node.is_in_group("bases"): node.add_to_group("bases")
		var tid : int = pair[1]
		if "team_id" in node: node.set("team_id", tid)
		node.set_meta("team_id", tid)
		print("[SceneSetup] Base '%s' → team_id=%d" % [node.name, tid])

	# Any node already in "base" group
	for node in get_tree().get_nodes_in_group("base"):
		if not node.is_in_group("bases"): node.add_to_group("bases")


# ── Players ───────────────────────────────────────────────────
func _setup_players() -> void:
	var players_node := get_tree().current_scene.find_child("Players", true, false)
	if is_instance_valid(players_node):
		for p in players_node.get_children():
			if not is_instance_valid(p): continue
			if not p.is_in_group("player"): p.add_to_group("player")
			if not p.is_in_group("units"):  p.add_to_group("units")
			if "team_id" in p and int(p.get("team_id")) == 0:
				p.set("team_id", 1)

	var shop := get_tree().get_first_node_in_group("shop")
	if is_instance_valid(shop):
		for p in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(p) and shop.has_method("bind_player"):
				if not is_instance_valid(shop.get("player")):
					shop.bind_player(p)
				break
