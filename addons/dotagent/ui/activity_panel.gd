@tool
extends VBoxContainer
## 活动日志面板 - 显示 AI 的工具调用过程
## 同时写入 SessionLog，确保 Activity 输出也进入 editor_output.txt

@onready var log_list: VBoxContainer = %LogList
@onready var scroll: ScrollContainer = %Scroll
@onready var clear_button: Button = %ClearButton

var _logger: SessionLog = null


func _ready() -> void:
	_logger = SessionLog.instance()
	clear_button.pressed.connect(_on_clear)
	clear_button.text = Locale.t("Clear")


func log_tool_call(tool_name: String, args: Dictionary, status: String) -> void:
	var line := "%s  🔧 %s(%s)" % [_timestamp(), tool_name, _summarize_args(args)]
	if status != "":
		line += "  [%s]" % status
	_append_line(line, _color("running"))
	_logger.append("ACTIVITY", line)


func log_tool_result(tool_name: String, result: Dictionary) -> void:
	var ok: bool = result.get("ok", true)
	var content: String = str(result.get("content", ""))
	var preview := content.replace("\n", " ")
	if preview.length() > 200:
		preview = preview.substr(0, 200) + "..."
	var mark := "✅" if ok else "❌"
	var line := "%s  %s %s → %s" % [_timestamp(), mark, tool_name, preview]
	_append_line(line, _color("ok" if ok else "err"))
	_logger.append("ACTIVITY", line)


func log_info(text: String) -> void:
	var line := "%s  ℹ️ %s" % [_timestamp(), text]
	_append_line(line, _color("info"))
	_logger.append("ACTIVITY", line)


func log_warning(text: String) -> void:
	var line := "%s  ⚠️ %s" % [_timestamp(), text]
	_append_line(line, _color("warn"))
	_logger.append("ACTIVITY", line)


func log_error(text: String) -> void:
	var line := "%s  ❌ %s" % [_timestamp(), text]
	_append_line(line, _color("err"))
	_logger.append("ACTIVITY", line)


func _append_line(text: String, color: Color) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.selection_enabled = true
	label.custom_minimum_size = Vector2(0, 16)
	log_list.add_child(label)
	label.append_text("[color=#%s]%s[/color]" % [color.to_html(false), text])
	_scroll_to_bottom()


func _summarize_args(args: Dictionary) -> String:
	if args.is_empty():
		return ""
	var parts: Array = []
	for k in args.keys():
		var v := str(args[k]).replace("\n", " ")
		if v.length() > 60:
			v = v.substr(0, 60) + "..."
		parts.append("%s=%s" % [k, v])
	return ", ".join(parts)


func _timestamp() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]


func _color(kind: String) -> Color:
	match kind:
		"running": return Color(0.95, 0.78, 0.35)  # 琥珀色
		"ok": return Color(0.55, 0.85, 0.55)        # 绿色
		"err": return Color(0.95, 0.45, 0.45)       # 红色
		"info": return Color(0.6, 0.8, 1.0)         # 蓝色
		"warn": return Color(0.95, 0.65, 0.20)      # 橙色
		_: return Color(0.85, 0.85, 0.85)


func _on_clear() -> void:
	for child in log_list.get_children():
		child.queue_free()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
