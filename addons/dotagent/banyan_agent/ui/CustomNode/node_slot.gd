@tool
class_name NodeSlot
extends Panel
## 连接端口 — 在 GraphElement 的四边上绘制连接点。
##
## modulate 颜色语义：
##   gray    未连接/空闲
##   green   已连接且活跃
##   yellow  正在传输数据
##   red     错误
##   white   默认（被 stylebox 着色）

enum Direction { LEFT, RIGHT, TOP, BOTTOM }

var direction: Direction = Direction.LEFT

## 返回端口中心的全局坐标（用于连线计算）
func get_center() -> Vector2:
	return global_position + size * 0.5


## 设置 modulate 颜色（快捷方法）
func set_status(status: String) -> void:
	match status:
		"idle":
			modulate = Color(0.5, 0.5, 0.5, 1.0)
		"connected":
			modulate = Color(0.3, 0.9, 0.3, 1.0)
		"active":
			modulate = Color(1.0, 0.85, 0.2, 1.0)
		"error":
			modulate = Color(1.0, 0.3, 0.3, 1.0)
		_:
			modulate = Color.WHITE
