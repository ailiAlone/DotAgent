## ParticleManager - Unified particle effect spawning utility.
## Provides static helpers for explosion, smoke, and future effect types.

class_name ParticleManager
extends Node2D

static func _find_effects_root():
	var root = Engine.get_main_loop().root
	if root != null:
		for child in root.get_children():
			if child is Node2D and child.name == "Effects":
				return child
	return null

static func spawn_explosion(parent: Node, world_position: Vector2, size: float = 1.0, color: Color = Color(1.0, 0.6, 0.2)):
	var scene = load("res://scenes/explosion.tscn")
	if scene == null:
		return null
	var fx = scene.instantiate()
	if fx == null:
		return null
	fx.position = world_position
	fx.set("size", size)
	fx.set("color", color)
	var container = _find_effects_root()
	if container == null and parent is Node2D:
		container = parent
	if container != null:
		container.add_child(fx)
	elif parent != null:
		parent.add_child(fx)
	else:
		Engine.get_main_loop().root.add_child(fx)
	return fx

static func spawn_smoke(parent: Node, world_position: Vector2, size: float = 1.0, color: Color = Color(0.5, 0.5, 0.5)):
	# Smoke is not yet implemented as a separate scene; reuse explosion with a softer look.
	return spawn_explosion(parent, world_position, size * 0.6, color)
