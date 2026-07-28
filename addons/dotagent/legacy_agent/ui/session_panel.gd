@tool
class_name SessionPanel
extends PopupPanel
## 会话列表面板（拆自 dock.gd）
##
## UI 节点（详见 dock.tscn 中的 SessionPopup）:
##   SessionVBox/TopBar:       NewButton + SearchField
##   SessionVBox/SessionList:  会话列表（ItemList）
##   SessionVBox/ActionBar:    SwitchButton + RenameButton + ForkButton + DeleteButton + CloseButton
##
## 职责:
##   - 列出/搜索/新建/切换/重命名/fork/删除 会话
##   - 与 DockController 交互（业务逻辑）
##   - 应用本地化文案

@onready var session_list: ItemList = %SessionList
@onready var new_button: Button = %NewButton
@onready var switch_button: Button = %SwitchButton
@onready var rename_button: Button = %RenameButton
@onready var fork_button: Button = %ForkButton
@onready var delete_button: Button = %DeleteButton
@onready var close_button: Button = %CloseButton
@onready var search_field: LineEdit = %SearchField

var _controller: DockController = null
var _session_store: SessionStore = null


func _ready() -> void:
	# 1. 业务后端（单例,避免重复扫描 sessions 目录）
	_session_store = SessionStore.instance()
	# 2. 按钮绑定
	new_button.pressed.connect(_on_new_session_pressed)
	switch_button.pressed.connect(_on_switch_session_pressed)
	rename_button.pressed.connect(_on_rename_session_pressed)
	fork_button.pressed.connect(_on_fork_session_pressed)
	delete_button.pressed.connect(_on_delete_session_pressed)
	close_button.pressed.connect(hide)
	session_list.item_activated.connect(_on_session_item_activated)
	search_field.text_changed.connect(_on_session_search_changed)
	# 3. 文案
	_apply_locale()


## 由 dock 注入 controller（若需要）
func set_controller(controller: DockController) -> void:
	_controller = controller


## 由 dock 调用 — 打开弹窗
func open() -> void:
	_populate_session_list("")
	popup_centered()


## 由 dock 调用 — 当会话切换时刷新列表
func refresh() -> void:
	if visible:
		_populate_session_list(search_field.text)


func _on_session_search_changed(text: String) -> void:
	_populate_session_list(text)


func _populate_session_list(filter: String) -> void:
	session_list.clear()
	var sessions: Array
	if filter.strip_edges() == "":
		sessions = _session_store.list_sessions(50)
	else:
		sessions = _session_store.search_sessions(filter, 50)
	if sessions.is_empty():
		session_list.add_item("(no sessions yet — click New)")
		session_list.set_item_disabled(0, true)
		return
	for s in sessions:
		var id: String = s.get("id", "?")
		var name: String = s.get("name", "")
		var msgs: int = int(s.get("message_count", 0))
		var updated: String = s.get("updated_at", "")
		var short_time := updated
		if updated.length() >= 16:
			short_time = updated.substr(5, 11).replace("T", " ")
		var marker := " ● " if id == _controller.get_current_session_id() else ""
		session_list.add_item("[b]%s[/b]  %d msgs  %s%s" % [name, msgs, short_time, marker])
		var idx := session_list.item_count - 1
		session_list.set_item_metadata(idx, id)


func _on_session_item_activated(idx: int) -> void:
	var session_id: String = session_list.get_item_metadata(idx)
	if session_id.is_empty() or session_id == _controller.get_current_session_id():
		return
	_controller.switch_session(session_id)
	_populate_session_list(search_field.text)


func _on_new_session_pressed() -> void:
	_controller.new_session()
	_populate_session_list(search_field.text)


func _on_switch_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty() or session_id == _controller.get_current_session_id():
		return
	_controller.switch_session(session_id)
	_populate_session_list(search_field.text)


func _on_rename_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var info := _session_store.get_session(session_id)
	var current_name: String = info.get("name", session_id)
	_show_rename_dialog(session_id, current_name)


func _show_rename_dialog(session_id: String, current_name: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Rename session"
	dlg.dialog_text = "New name:"
	var edit := LineEdit.new()
	edit.text = current_name
	edit.custom_minimum_size = Vector2(300, 0)
	dlg.add_child(edit)
	dlg.confirmed.connect(func():
		var new_name := edit.text.strip_edges()
		if new_name != "" and new_name != current_name:
			_controller.rename_session(session_id, new_name)
			_populate_session_list(search_field.text)
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered()


func _on_fork_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var new_id: String = _controller.fork_session(session_id)
	if new_id != "":
		_populate_session_list(search_field.text)


func _on_delete_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete session?"
	dlg.dialog_text = "Delete session %s?\nThis cannot be undone." % session_id
	dlg.confirmed.connect(func():
		_controller.delete_session(session_id)
		_populate_session_list(search_field.text)
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered()


func _apply_locale() -> void:
	title = Locale.t("Sessions")
	if new_button: new_button.text = Locale.t("New")
	if switch_button: switch_button.text = Locale.t("Switch")
	if rename_button: rename_button.text = Locale.t("Rename")
	if fork_button: fork_button.text = Locale.t("Fork")
	if delete_button: delete_button.text = Locale.t("Delete")
	if close_button: close_button.text = Locale.t("Close")
	if search_field: search_field.placeholder_text = Locale.t("search…")


## 外部调用以响应语言切换
func on_locale_changed() -> void:
	_apply_locale()
