@tool
extends RefCounted
## Session 管理工具(给 AI 调用)
##
## Session 是一等公民,跟 log 完全不同:
## - 有 id / name / 时间 / model / parent_id(支持 fork)
## - 可 list / create / rename / delete / fork / switch
## - 每个 session 单独存 res://ai_sessions/<id>/{session.json, messages.json}
##
## AI 用这些工具:
## - 找过去的对话引用 → list_sessions + load_session
## - 用户说"另起一个话题"→ create_session
## - 用户说"从那个 session 继续" → load_session 把消息塞 _messages(不直接切换,只读)

var editor_plugin: EditorPlugin = null
var activity_panel: Control = null
var _store: SessionStore = SessionStore.new()


func set_editor_context(plugin: EditorPlugin, activity: Control) -> void:
	editor_plugin = plugin
	activity_panel = activity


func get_tool_definitions() -> Array:
	return [
		{
			"name": "list_sessions",
			"description": "List all past AI panel sessions (newest first). Each entry has id, name, created_at, updated_at, message_count, model, parent_id. Use this to find a previous session before calling load_session.",
			"parameters": {
				"type": "object",
				"properties": {
					"limit": {"type": "integer", "description": "Max entries to return (default 20)", "default": 20},
					"search": {"type": "string", "description": "Optional filter — match name or id (case-insensitive substring)"},
				},
			},
			"method_name": "_tool_list_sessions",
			"dangerous": false,
		},
		{
			"name": "load_session",
			"description": "Read a past session's messages. Returns the raw _messages array (list of {role, content, tool_calls}). Use to inspect/reference a previous conversation. Does NOT auto-replace the current conversation.",
			"parameters": {
				"type": "object",
				"properties": {
					"session_id": {"type": "string", "description": "Session id, e.g. '2026-06-07_14-30-25'"},
				},
				"required": ["session_id"],
			},
			"method_name": "_tool_load_session",
			"dangerous": false,
		},
		{
			"name": "create_session",
			"description": "Create a new empty session. The user can later rename / delete / fork it. Returns {id, name, created_at}. Does NOT auto-switch the user into it — that happens in the UI when the user clicks 'New'.",
			"parameters": {
				"type": "object",
				"properties": {
					"name": {"type": "string", "description": "Optional name (defaults to 'Session @ MM-DD HH:MM')"},
					"parent_id": {"type": "string", "description": "Optional parent session id (for fork tracking only)"},
				},
			},
			"method_name": "_tool_create_session",
			"dangerous": false,
		},
		{
			"name": "rename_session",
			"description": "Rename an existing session. Use after the user gives a name for an auto-generated session.",
			"parameters": {
				"type": "object",
				"properties": {
					"session_id": {"type": "string", "description": "Session id"},
					"new_name": {"type": "string", "description": "New name (1-80 chars)"},
				},
				"required": ["session_id", "new_name"],
			},
			"method_name": "_tool_rename_session",
			"dangerous": false,
		},
		{
			"name": "fork_session",
			"description": "Create a new session by copying all messages from an existing one. The new session is a sibling with parent_id pointing back. Use when the user wants to try a different approach from a past point.",
			"parameters": {
				"type": "object",
				"properties": {
					"session_id": {"type": "string", "description": "Source session id to fork from"},
					"new_name": {"type": "string", "description": "Optional name for the new session (default: 'Fork of <source_id>')"},
				},
				"required": ["session_id"],
			},
			"method_name": "_tool_fork_session",
			"dangerous": false,
		},
		{
			"name": "delete_session",
			"description": "Permanently delete a session and its files. Cannot be undone. Use only when the user explicitly confirms.",
			"parameters": {
				"type": "object",
				"properties": {
					"session_id": {"type": "string", "description": "Session id to delete"},
				},
				"required": ["session_id"],
			},
			"method_name": "_tool_delete_session",
			"dangerous": true,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_list_sessions": return _tool_list_sessions(args)
		"_tool_load_session": return _tool_load_session(args)
		"_tool_create_session": return _tool_create_session(args)
		"_tool_rename_session": return _tool_rename_session(args)
		"_tool_fork_session": return _tool_fork_session(args)
		"_tool_delete_session": return _tool_delete_session(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_list_sessions(args: Dictionary) -> Dictionary:
	var limit: int = int(args.get("limit", 20))
	var search: String = args.get("search", "")
	var sessions: Array
	if search.strip_edges() == "":
		sessions = _store.list_sessions(limit)
	else:
		sessions = _store.search_sessions(search, limit)
	if sessions.is_empty():
		return _ok("No sessions found" + (" matching '" + search + "'" if search != "" else "") + ".")
	return _ok(JSON.stringify(sessions, "  "))


func _tool_load_session(args: Dictionary) -> Dictionary:
	var session_id: String = args.get("session_id", "")
	if session_id.is_empty():
		return _err("session_id is required")
	var msgs := _store.read_messages(session_id)
	if msgs.is_empty():
		return _err("Session not found or has no messages: " + session_id)
	return _ok(JSON.stringify(msgs, "  "))


func _tool_create_session(args: Dictionary) -> Dictionary:
	var name: String = args.get("name", "")
	var parent_id: String = args.get("parent_id", "")
	var info := _store.create_session(name, parent_id)
	return _ok(JSON.stringify(info, "  "))


func _tool_rename_session(args: Dictionary) -> Dictionary:
	var session_id: String = args.get("session_id", "")
	var new_name: String = args.get("new_name", "")
	if session_id.is_empty() or new_name.is_empty():
		return _err("session_id and new_name are required")
	if not _store.rename_session(session_id, new_name):
		return _err("Session not found: " + session_id)
	return _ok("Renamed %s to '%s'" % [session_id, new_name])


func _tool_fork_session(args: Dictionary) -> Dictionary:
	var session_id: String = args.get("session_id", "")
	if session_id.is_empty():
		return _err("session_id is required")
	var new_name: String = args.get("new_name", "")
	var info := _store.fork_session(session_id, new_name)
	return _ok(JSON.stringify(info, "  "))


func _tool_delete_session(args: Dictionary) -> Dictionary:
	var session_id: String = args.get("session_id", "")
	if session_id.is_empty():
		return _err("session_id is required")
	if not _store.delete_session(session_id):
		return _err("Failed to delete (not found?): " + session_id)
	return _ok("Deleted session: " + session_id)


func _ok(content: String) -> Dictionary:
	return {"ok": true, "content": content}


func _err(content: String) -> Dictionary:
	return {"ok": false, "content": "❌ " + content}
