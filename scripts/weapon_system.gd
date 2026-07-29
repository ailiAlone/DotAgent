extends Node

## Autoload that manages the player's current weapon type and provides weapon data.

enum WeaponType { PISTOL, SPREAD, LASER }

const WEAPON_COUNT = 3

func _ready():
	pass

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

func get_weapon_data(type: int, level: int) -> Dictionary:
	level = clamp(level, 0, 3)
	match type:
		WeaponType.PISTOL:
			return {
				"damage": 1 + level,
				"fire_rate": 0.18 - level * 0.02,
				"bullet_count": 2 + level,
				"bullet_speed": 900.0 + level * 50.0,
				"spread": 0.12 - level * 0.02,
				"color": Color(1.0, 0.95, 0.4)
			}
		WeaponType.SPREAD:
			return {
				"damage": 1 + level / 2,
				"fire_rate": 0.28 - level * 0.03,
				"bullet_count": 5 + level * 2,
				"bullet_speed": 700.0 + level * 40.0,
				"spread": 0.22 + level * 0.04,
				"color": Color(1.0, 0.5, 0.3)
			}
		WeaponType.LASER:
			return {
				"damage": 2 + level * 2,
				"fire_rate": 0.45 - level * 0.05,
				"bullet_count": 1 + level,
				"bullet_speed": 1400.0,
				"spread": 0.0,
				"color": Color(0.4, 1.0, 0.6)
			}
		_:
			return {
				"damage": 1,
				"fire_rate": 0.18,
				"bullet_count": 2,
				"bullet_speed": 900.0,
				"spread": 0.12,
				"color": Color(1.0, 0.95, 0.4)
			}
