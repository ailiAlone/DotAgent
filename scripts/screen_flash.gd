extends CanvasLayer

# 屏幕红闪 — 玩家受击时调用
# 始终盖在最上层，无视游戏暂停

var flash_rect: ColorRect
var tween: Tween

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100  # 确保最上层
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1.0, 0.1, 0.1, 0.0)
	flash_rect.anchor_right = 1.0
	flash_rect.anchor_bottom = 1.0
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)

func flash(intensity: float = 0.5):
	if tween and tween.is_valid():
		tween.kill()
	flash_rect.color.a = clamp(intensity, 0.0, 1.0)
	tween = create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD)
