@tool
extends AcceptDialog
## Session Management Popup — 会话管理弹窗
##
## 列出所有会话，支持搜索、切换、新建和删除。
## 由 plugin 通过 refresh() 传入会话数据，通过信号通知外部操作。

# ============ 信号 ============

signal session_selected(session_id: String)
signal session_new()
signal session_deleted(session_id: String)

# ============ UI 组件 (@onready) ============

@onready var _main_vbox: VBoxContainer = $MainVBox
@onready var _new_btn: Button = $MainVBox/TopBar/NewBtn
@onready var _search_field: LineEdit = $MainVBox/TopBar/SearchField
@onready var _session_list: ItemList = $MainVBox/SessionList
@onready var _switch_btn: Button = $MainVBox/ActionBar/SwitchBtn
@onready var _delete_btn: Button = $MainVBox/ActionBar/DeleteBtn
@onready var _close_btn: Button = $MainVBox/ActionBar/CloseBtn

# ============ 状态 ============

var _current_id: String = ""


func _ready() -> void:
	# AcceptDialog 默认带 OK 按钮，隐藏它
	get_ok_button().hide()

	# 连接按钮信号
	_new_btn.pressed.connect(_on_new_pressed)
	_search_field.text_changed.connect(_on_search_changed)
	_session_list.item_activated.connect(_on_item_activated)
	_switch_btn.pressed.connect(_on_switch_pressed)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_close_btn.pressed.connect(_on_close_pressed)


# ============ 公共 API ============

## 刷新会话列表。sessions 为 Array[Dictionary]，每项须含 "id" 和可选 "messages"(int)。
## current_id 标记当前活跃会话。
func refresh(sessions: Array, current_id: String = "") -> void:
	_current_id = current_id
	_session_list.clear()

	for s in sessions:
		if not s is Dictionary:
			continue
		var sid: String = str(s.get("id", ""))
		if sid.is_empty():
			continue
		var msg_count: int = int(s.get("messages", 0))

		# 构造显示文本
		var prefix: String = "  "
		if sid == current_id:
			prefix = "● "
		var display: String = "%s%s  %d msgs" % [prefix, sid, msg_count]

		var idx: int = _session_list.add_item(display)
		_session_list.set_item_metadata(idx, sid)

		# 当前会话高亮选中
		if sid == current_id:
			_session_list.select(idx)


# ============ 内部方法 ============

## 根据搜索文本过滤列表项的显示/隐藏
func _filter(text: String) -> void:
	var query: String = text.strip_edges().to_lower()
	for i in range(_session_list.item_count):
		var item_text: String = _session_list.get_item_text(i).to_lower()
		if query.is_empty() or query in item_text:
			_session_list.set_item_disabled(i, false)
		else:
			_session_list.set_item_disabled(i, true)


## 返回当前选中项的 session_id，无选中返回空字符串
func _get_selected_id() -> String:
	var selected: Array = _session_list.get_selected_items()
	if selected.is_empty():
		return ""
	return str(_session_list.get_item_metadata(selected[0]))


# ============ 回调 ============

func _on_new_pressed() -> void:
	session_new.emit()
	# 外部应在处理 session_new 后调用 refresh() 更新列表


func _on_search_changed(text: String) -> void:
	_filter(text)


func _on_item_activated(index: int) -> void:
	var sid: String = str(_session_list.get_item_metadata(index))
	if not sid.is_empty():
		session_selected.emit(sid)


func _on_switch_pressed() -> void:
	var sid: String = _get_selected_id()
	if sid.is_empty():
		return
	session_selected.emit(sid)


func _on_delete_pressed() -> void:
	var sid: String = _get_selected_id()
	if sid.is_empty():
		return
	# 弹出确认对话框
	var confirm: ConfirmationDialog = ConfirmationDialog.new()
	confirm.title = "Delete Session"
	confirm.dialog_text = "Delete session '%s'? This cannot be undone." % sid
	add_child(confirm)
	confirm.popup_centered()
	confirm.confirmed.connect(func():
		session_deleted.emit(sid)
		confirm.queue_free()
	)
	confirm.canceled.connect(func():
		confirm.queue_free()
	)


func _on_close_pressed() -> void:
	hide()
