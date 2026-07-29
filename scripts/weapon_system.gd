extends Node

## Autoload that manages player weapon data for three weapon types with levels 0-3.

enum WeaponType { PISTOL, SPREAD, LASER }

const WEAPON_COUNT = 3
const MAX_LEVEL = 3


func _ready() -> void:
	pass


## Returns the human-readable name for a weapon type.
func weapon_type_name(type: int) -> String:
	match type:
		WeaponType.PISTOL:
			return "PISTOL"
		WeaponType.SPREAD:
			return "SPREAD"
		WeaponType.LASER:
			return "LASER"
		_:
			return "PISTOL"


## Returns weapon stats for the given type and level.
## Dictionary keys: damage (int), fire_rate (float), bullet_count (int),
## bullet_speed (float), spread (float), color (Color).
func get_weapon_data(type: int, level: int) -> Dictionary:
	level = clampi(level, 0, MAX_LEVEL)

	match type:
		WeaponType.PISTOL:
			# Focused, high per-bullet damage, fast fire, accurate.
			return {
				"damage": 2 + level,
				"fire_rate": 0.14 - level * 0.02,
				"bullet_count": 1,
				"bullet_speed": 1000.0 + level * 60.0,
				"spread": maxf(0.0, 0.04 - level * 0.01),
				"color": Color(1.0, 0.95, 0.4)
			}

		WeaponType.SPREAD:
			# Multi-bullet wide fan, lower per-bullet damage, slower fire.
			return {
				"damage": 1 + level / 2,
				"fire_rate": 0.30 - level * 0.025,
				"bullet_count": 3 + level * 2,
				"bullet_speed": 700.0 + level * 40.0,
				"spread": 0.18 + level * 0.04,
				"color": Color(1.0, 0.5, 0.3)
			}

		WeaponType.LASER:
			# Single powerful shot, very high bullet speed, slowest fire, bright magenta-cyan.
			var t: float = level / float(MAX_LEVEL)
			return {
				"damage": 3 + level * 3,
				"fire_rate": 0.50 - level * 0.04,
				"bullet_count": 1,
				"bullet_speed": 1600.0 + level * 200.0,
				"spread": 0.0,
				"color": Color(1.0, 0.0, 1.0).lerp(Color(0.0, 1.0, 1.0), t)
			}

		_:
			return {
				"damage": 2,
				"fire_rate": 0.14,
				"bullet_count": 1,
				"bullet_speed": 1000.0,
				"spread": 0.04,
				"color": Color(1.0, 0.95, 0.4)
			}
