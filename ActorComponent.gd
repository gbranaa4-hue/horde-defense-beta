# ============================================================
# ActorComponent.gd — Base class for all player/actor components
# ============================================================
# Usage:
#   extends ActorComponent
#   func _ready(): initialize(get_parent())
# ============================================================
extends Node
class_name ActorComponent

var actor : CharacterBody3D = null

func initialize(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor
