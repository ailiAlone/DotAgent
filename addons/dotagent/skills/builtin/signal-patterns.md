# triggers: signal, connect, disconnect, pressed, timeout, body_entered, area_entered, button, callback, event, _on_, bind, emit

# Signal Patterns — Connect, Disconnect, and Emit

## Core Rule
**All signal connections are code-based.** Use `replace_in_file` to add `.connect()` / `.disconnect()` lines in scripts. There is no tool for signal wiring.

## Static Connections (_ready)
Most common pattern — wire up UI and gameplay signals once at startup:
```gdscript
func _ready():
    %StartButton.pressed.connect(_on_start_pressed)
    $Timer.timeout.connect(_on_timeout)
    $Area2D.body_entered.connect(_on_body_entered)
```

## Dynamic Connections (runtime-created nodes)
When creating nodes at runtime, connect immediately after creating:
```gdscript
var btn := Button.new()
btn.pressed.connect(_on_dynamic_click)
add_child(btn)
```

## Temporary Bindings (connect then disconnect)
For one-shot or conditional signal handling:
```gdscript
func _on_area_entered(body):
    body.damaged.connect(_on_enemy_hit)   # bind temporarily

func _on_enemy_hit(amount):
    # ... handle damage ...
    # Disconnect to prevent duplicate triggers
    if sender is Node and sender.damaged.is_connected(_on_enemy_hit):
        sender.damaged.disconnect(_on_enemy_hit)
```

## Bind Extra Data
Pass additional arguments to the callback:
```gdscript
for star in stars:
    star.body_entered.connect(_on_star_collected.bind(star))
    star.body_entered.connect(_on_star_collected.bind(star, "extra_info"))
```

## Emitting Custom Signals
Define in script, emit from anywhere:
```gdscript
signal health_changed(new_health: int)

func take_damage(amount: int):
    health -= amount
    health_changed.emit(health)
```

## Workflow Checklist
1. `read_script` — find where to insert (usually `_ready()` or event callback)
2. `replace_in_file` — insert the `.connect()` / `.disconnect()` line
3. `check_script_syntax` — verify it compiles
4. `run_scene_capture` — test the connection works

## Common Mistakes
- ❌ Forgetting to create the callback method first → `check_script_syntax` catches this
- ❌ Connecting inside `_process()` → creates duplicate connections every frame
- ❌ Not disconnecting temporary bindings → callback fires multiple times
- ❌ Using `connect_signal` tool — it was removed, always use code
- ❌ `node.signal_name.connect` on a signal that doesn't exist → check with `get_node_type_info` first
