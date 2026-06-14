@tool
class_name SessionManager
extends RefCounted
## Session 生命周期管理
##
## 负责: 创建/切换/重命名/删除/fork session, 消息持久化, 消息压缩, 脏数据清理。
## 不持有 messages — 通过参数接收/返回,由 DockController 持有唯一引用。

signal session_changed(session_id: String, messages: Array)
signal config_changed()

var current_session_id: String = ""

var _session_store: SessionStore
var _logger: SessionLog


func setup(logger: SessionLog) -> void:
	_session_store = SessionStore.instance()
	_logger = logger


# ============ Public API ============

## 启动/恢复 session
## 找最近 updated 的 session;没有就建一个新的
func bootstrap(system_prompt: String) -> Array[Dictionary]:
	var sessions := _session_store.list_sessions(1)
	if sessions.is_empty():
		var info := _session_store.create_session("")
		current_session_id = info["id"]
		var messages: Array[Dictionary] = [{"role": "system", "content": system_prompt}]
		session_changed.emit(current_session_id, messages.duplicate(true))
		return messages
	else:
		return switch(sessions[0]["id"], system_prompt, [], true)


## 新建 session
func create_new(system_prompt: String) -> Array[Dictionary]:
	var info := _session_store.create_session("")
	current_session_id = info["id"]
	var messages: Array[Dictionary] = [{"role": "system", "content": system_prompt}]
	_save(current_session_id, messages)
	session_changed.emit(current_session_id, messages.duplicate(true))
	return messages


## 强制全新 session(测试用,绕开历史脏数据)
func create_clean(system_prompt: String) -> Array[Dictionary]:
	var info := _session_store.create_session("")
	current_session_id = info["id"]
	var messages: Array[Dictionary] = [{"role": "system", "content": system_prompt}]
	_save(current_session_id, messages)
	session_changed.emit(current_session_id, messages.duplicate(true))
	return messages


## 切换 session
## **脏数据防护**:逐段检查 assistant{tool_calls}+后续 tool 消息是否配对。
func switch(session_id: String, system_prompt: String, current_messages: Array[Dictionary], suppress_save: bool = false) -> Array[Dictionary]:
	if not suppress_save:
		save(current_session_id, current_messages)

	var raw_msgs := _session_store.read_messages(session_id)
	var messages := _clean_messages(raw_msgs, system_prompt)

	current_session_id = session_id

	if messages.size() > 50:
		var before := messages.size()
		compact(messages, 3)
		_logger.warn("Auto-compacted on session load: %d → %d msgs" % [before, messages.size()])

	session_changed.emit(session_id, messages.duplicate(true))
	return messages


## 重命名 session
func rename(session_id: String, new_name: String) -> bool:
	var ok := _session_store.rename_session(session_id, new_name)
	if ok:
		config_changed.emit()
	return ok


## Fork session
func fork(source_id: String) -> String:
	var info := _session_store.fork_session(source_id, "Fork of " + source_id)
	return info.get("id", "")


## 删除 session。返回是否成功。
## 如果删的是当前 session,自动创建新 session。
func delete(session_id: String) -> bool:
	var was_current := session_id == current_session_id
	var ok := _session_store.delete_session(session_id)
	if not ok:
		return false
	if was_current:
		var info := _session_store.create_session("")
		current_session_id = info["id"]
	return true


## 保存 messages + 更新 model 元数据
func save_with_model(session_id: String, messages: Array[Dictionary], model: String) -> void:
	if session_id.is_empty():
		return
	_session_store.write_messages(session_id, messages)
	if model.is_empty():
		return
	var info := _session_store.get_session(session_id)
	if info and info.get("model", "") != model:
		info["model"] = model
		_session_store._write_session_meta(session_id, info)


## 仅保存 messages(不更新 model)
func save(session_id: String, messages: Array[Dictionary]) -> void:
	if session_id.is_empty():
		return
	_session_store.write_messages(session_id, messages)


## 压缩 messages(保留 system + 最后 N 轮用户问答)
## 直接修改传入的 messages 数组(引用)
func compact(messages: Array[Dictionary], keep_exchanges: int = 5) -> Dictionary:
	var kept: Array[Dictionary] = []
	for msg in messages:
		if msg.get("role") == "system":
			kept.append(msg)
			break
	var user_indices := []
	for idx in range(messages.size() - 1, -1, -1):
		if messages[idx].get("role") == "user":
			user_indices.append(idx)
			if user_indices.size() >= keep_exchanges:
				break
	if user_indices.is_empty():
		return {"before": messages.size(), "after": messages.size()}
	var start: int = user_indices[user_indices.size() - 1]
	for idx in range(start, messages.size()):
		if messages[idx].get("role") != "system":
			kept.append(messages[idx])
	var before := messages.size()
	messages.clear()
	for m in kept:
		messages.append(m)
	return {"before": before, "after": kept.size()}


# ============ Internal ============

## 脏数据清理:逐段检查 assistant→tool 配对
func _clean_messages(raw_messages: Array, system_prompt: String) -> Array[Dictionary]:
	var cleaned: Array[Dictionary] = []
	cleaned.append({"role": "system", "content": system_prompt})

	var i := 0
	while i < raw_messages.size():
		var msg: Dictionary = raw_messages[i]
		var role: String = msg.get("role", "")
		if role == "system":
			i += 1
			continue

		if role == "assistant" and msg.has("tool_calls"):
			var declared_ids := {}
			for tc in msg.get("tool_calls", []):
				var tid: String = tc.get("id", "")
				if not tid.is_empty():
					declared_ids[tid] = true

			var j := i + 1
			var found_ids := {}
			while j < raw_messages.size() and raw_messages[j].get("role", "") == "tool":
				var tid: String = raw_messages[j].get("tool_call_id", "")
				if not tid.is_empty():
					found_ids[tid] = true
				j += 1

			var all_ok := true
			for tid in declared_ids.keys():
				if not found_ids.has(tid):
					all_ok = false
					break

			if not all_ok:
				_logger.warn("switch_session: dropping orphan assistant segment (missing tool results)")
				i = j
				continue

			cleaned.append(msg)
			i += 1
			while i < j:
				cleaned.append(raw_messages[i])
				i += 1
		elif role == "tool":
			_logger.warn("switch_session: skipping orphan tool message (tool_call_id=%s)" % msg.get("tool_call_id", "?"))
			i += 1
		else:
			cleaned.append(msg)
			i += 1

	return cleaned


func _save(session_id: String, messages: Array[Dictionary]) -> void:
	_session_store.write_messages(session_id, messages)
