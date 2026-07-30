extends Node

## Weather system managing weather states and their effects on gameplay.
## Weather types: CLEAR, RAIN, SNOW, FOG
## Effects: RAIN reduces visibility, SNOW reduces player speed, FOG increases enemy spawn rate

enum WeatherType {
	CLEAR = 0,
	RAIN = 1,
	SNOW = 2,
	FOG = 3
}

signal weather_changed(weather_type: int)

## Weather effect parameters
const RAIN_VISIBILITY_MULT: float = 0.6       # Rain reduces visibility to 60%
const SNOW_SPEED_MULT: float = 0.7            # Snow reduces player speed to 70%
const FOG_SPAWN_RATE_MULT: float = 1.5         # Fog increases enemy spawn rate by 50%

const CLEAR_NAME: String = "Clear"
const RAIN_NAME: String = "Rain"
const SNOW_NAME: String = "Snow"
const FOG_NAME: String = "Fog"

var _current_weather: WeatherType = WeatherType.CLEAR
var _weather_particles: Node2D = null


func _ready() -> void:
	# Start with clear weather
	set_weather(WeatherType.CLEAR)


## Get the current weather type
func get_current_weather() -> WeatherType:
	return _current_weather


## Set the weather to a specific type
## Emits weather_changed signal when weather changes
func set_weather(weather_type: WeatherType) -> void:
	if _current_weather == weather_type:
		return
	
	_current_weather = weather_type
	
	# Update weather particles if scene is loaded
	_update_weather_particles()
	
	# Emit weather changed signal
	weather_changed.emit(_current_weather)
	
	_print_weather_change()


## Set weather by integer value (useful for signals from other nodes)
func set_weather_by_int(value: int) -> void:
	var weather_type: WeatherType = clampi(value, 0, WeatherType.size() - 1) as WeatherType
	set_weather(weather_type)


## Randomly switch to a new weather (excluding current)
func randomize_weather() -> void:
	var new_weather: WeatherType
	var attempts: int = 0
	const MAX_ATTEMPTS: int = 10
	
	# Try to get a different weather type
	while attempts < MAX_ATTEMPTS:
		new_weather = randi() % WeatherType.size() as WeatherType
		if new_weather != _current_weather:
			break
		attempts += 1
	
	set_weather(new_weather)


## Get weather effects as a dictionary
## Returns multipliers for visibility, speed, and spawn rate
func get_weather_effects() -> Dictionary:
	match _current_weather:
		WeatherType.RAIN:
			return {
				"visibility_mult": RAIN_VISIBILITY_MULT,
				"speed_mult": 1.0,
				"spawn_rate_mult": 1.0,
				"name": RAIN_NAME,
				"type": WeatherType.RAIN
			}
		WeatherType.SNOW:
			return {
				"visibility_mult": 1.0,
				"speed_mult": SNOW_SPEED_MULT,
				"spawn_rate_mult": 1.0,
				"name": SNOW_NAME,
				"type": WeatherType.SNOW
			}
		WeatherType.FOG:
			return {
				"visibility_mult": 0.7,
				"speed_mult": 1.0,
				"spawn_rate_mult": FOG_SPAWN_RATE_MULT,
				"name": FOG_NAME,
				"type": WeatherType.FOG
			}
		_:
			return {
				"visibility_mult": 1.0,
				"speed_mult": 1.0,
				"spawn_rate_mult": 1.0,
				"name": CLEAR_NAME,
				"type": WeatherType.CLEAR
			}


## Get the spawn rate multiplier for enemy spawning
## Respects weather effects (FOG increases spawn rate)
func get_spawn_rate_multiplier() -> float:
	var effects: Dictionary = get_weather_effects()
	return effects.get("spawn_rate_mult", 1.0) as float


## Get the player speed multiplier
## Respects weather effects (SNOW reduces player speed)
func get_player_speed_multiplier() -> float:
	var effects: Dictionary = get_weather_effects()
	return effects.get("speed_mult", 1.0) as float


## Get the visibility multiplier
## Respects weather effects (RAIN reduces visibility)
func get_visibility_multiplier() -> float:
	var effects: Dictionary = get_weather_effects()
	return effects.get("visibility_mult", 1.0) as float


## Check if current weather is CLEAR
func is_clear() -> bool:
	return _current_weather == WeatherType.CLEAR


## Check if current weather is RAIN
func is_rain() -> bool:
	return _current_weather == WeatherType.RAIN


## Check if current weather is SNOW
func is_snow() -> bool:
	return _current_weather == WeatherType.SNOW


## Check if current weather is FOG
func is_fog() -> bool:
	return _current_weather == WeatherType.FOG


## Update weather particles based on current weather
func _update_weather_particles() -> void:
	if not has_node("WeatherParticles") and _weather_particles == null:
		return
	
	var particles: Node2D = get_node_or_null("WeatherParticles") as Node2D
	if particles == null:
		return
	
	# Hide all particle systems first
	for child: Node in particles.get_children():
		if child is CPUParticles2D or child is GPUParticles2D:
			var ps: Node = child as Node
			ps.visible = false
	
	# Show appropriate particle system based on weather
	match _current_weather:
		WeatherType.RAIN:
			if particles.has_node("Rain"):
				var rain: Node = particles.get_node("Rain") as Node
				rain.visible = true
		WeatherType.SNOW:
			if particles.has_node("Snow"):
				var snow: Node = particles.get_node("Snow") as Node
				snow.visible = true
		WeatherType.FOG:
			if particles.has_node("Fog"):
				var fog: Node = particles.get_node("Fog") as Node
				fog.visible = true


## Print weather change for debugging
func _print_weather_change() -> void:
	var effects: Dictionary = get_weather_effects()
	var name: String = effects.get("name", "Unknown") as String
	print("Weather changed to: ", name)
	print("  - Visibility: ", effects.get("visibility_mult", 1.0))
	print("  - Player Speed: ", effects.get("speed_mult", 1.0))
	print("  - Enemy Spawn Rate: ", effects.get("spawn_rate_mult", 1.0))
