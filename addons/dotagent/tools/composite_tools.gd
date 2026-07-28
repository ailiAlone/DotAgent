@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 复合工具模块 — 多步操作的原子封装
##
## 将多轮 LLM 调用压缩为单次调用。
## build_script: 结构化接口定义 → .gd 脚本骨架
## update_script: 更新脚本内容（桥接 Legacy script_tools）
##
## Tools:
## - build_script
## - update_script


func get_tool_definitions() -> Array:
	return [
		_td("build_script",
			"Generate a GDScript skeleton from structured interface definition. Creates file with class_name, extends, signals, exports, constants, enums, and method stubs. Syntax-validated before saving.",
			"_tool_build_script",
			{
				"path": {"type": "string", "description": "Script file path (.gd)"},
				"class_name": {"type": "string", "description": "Optional class_name declaration", "default": ""},
				"extends": {"type": "string", "description": "Base class (default 'Node')", "default": "Node"},
				"doc_comment": {"type": "string", "description": "Optional doc comment at top", "default": ""},
				"signals": {
					"type": "array",
					"description": "Signal declarations",
					"items": {
						"type": "object",
						"properties": {
							"name": {"type": "string"},
							"params": {"type": "array", "items": {"type": "string"}, "default": []}
						}
					},
					"default": []
				},
				"exports": {
					"type": "array",
					"description": "@export variable declarations",
					"items": {
						"type": "object",
						"properties": {
							"name": {"type": "string"},
							"type": {"type": "string", "description": "Variable type (int, float, String, etc.)"},
							"default": {"description": "Default value"},
							"hint": {"type": "string", "description": "Optional export hint"}
						}
					},
					"default": []
				},
				"constants": {
					"type": "array",
					"description": "Constant declarations",
					"items": {
						"type": "object",
						"properties": {
							"name": {"type": "string"},
							"value": {"description": "Constant value"}
						}
					},
					"default": []
				},
				"enums": {
					"type": "array",
					"description": "Enum declarations",
					"items": {
						"type": "object",
						"properties": {
							"name": {"type": "string"},
							"values": {"type": "array", "items": {"type": "string"}}
						}
					},
					"default": []
				},
				"onready_refs": {
					"type": "array",
					"description": "@onready var references",
					"items": {
						"type": "object",
						"properties": {
							"name": {"type": "string"},
							"type": {"type": "string"},
							"path": {"type": "string", "description": "Node path for $ reference"}
						}
					},
					"default": []
				},
				"methods": {
					"type": "array",
					"description": "Method definitions",
					"items": {
						"type": "object",
						"properties": {
							"name": {"type": "string"},
							"params": {"type": "array", "items": {"type": "string"}, "default": []},
							"returns": {"type": "string", "default": ""},
							"is_static": {"type": "boolean", "default": false},
							"body": {"type": "string", "description": "Method body (use 'pass # TODO' for stubs)", "default": "pass # TODO"}
						}
					},
					"default": []
				},
				"validate_syntax": {"type": "boolean", "description": "Validate GDScript syntax before saving", "default": true},
			},
			["path"]),
		_td("update_script",
			"Write or update a GDScript file with provided content. Validates syntax before saving. Creates backup of existing file.",
			"_tool_update_script",
			{
				"path": {"type": "string", "description": "Script file path (.gd)"},
				"content": {"type": "string", "description": "Complete script content to write"},
				"validate_syntax": {"type": "boolean", "description": "Validate GDScript syntax before saving", "default": true},
			},
			["path", "content"]),
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_build_script": return _tool_build_script(args)
		"_tool_update_script": return _tool_update_script(args)
	return _err("Unknown method: " + method_name)


# ============ Tool 1: build_script ============

func _tool_build_script(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".gd"):
		return _err("path must end with .gd")
	if FileAccess.file_exists(path):
		return _err("Script already exists: " + path + ". Use update_script to modify.")

	var class_name_val: String = args.get("class_name", "")
	var extends_val: String = args.get("extends", "Node")
	var doc_comment: String = args.get("doc_comment", "")
	var signals_defs: Array = args.get("signals", [])
	var exports_defs: Array = args.get("exports", [])
	var constants_defs: Array = args.get("constants", [])
	var enums_defs: Array = args.get("enums", [])
	var onready_defs: Array = args.get("onready_refs", [])
	var methods_defs: Array = args.get("methods", [])
	var validate: bool = args.get("validate_syntax", true)

	# Build script content line by line
	var lines: Array = []

	# Doc comment
	if not doc_comment.is_empty():
		lines.append("## " + doc_comment.replace("\n", "\n## "))
		lines.append("")

	# class_name
	if not class_name_val.is_empty():
		lines.append("class_name %s" % class_name_val)

	# extends
	lines.append("extends %s" % extends_val)
	lines.append("")

	# Signals
	if not signals_defs.is_empty():
		for sdef in signals_defs:
			var sname: String = str(sdef.get("name", ""))
			var sparams: Array = sdef.get("params", [])
			if sname.is_empty():
				continue
			if sparams.is_empty():
				lines.append("signal %s" % sname)
			else:
				lines.append("signal %s(%s)" % [sname, ", ".join(sparams)])
		lines.append("")

	# Enums
	if not enums_defs.is_empty():
		for edef in enums_defs:
			var ename: String = str(edef.get("name", ""))
			var evalues: Array = edef.get("values", [])
			if ename.is_empty():
				continue
			lines.append("enum %s { %s }" % [ename, ", ".join(evalues)])
		lines.append("")

	# Constants
	if not constants_defs.is_empty():
		for cdef in constants_defs:
			var cname: String = str(cdef.get("name", ""))
			var cval = cdef.get("value", "")
			if cname.is_empty():
				continue
			lines.append("const %s = %s" % [cname, str(cval)])
		lines.append("")

	# Exports
	if not exports_defs.is_empty():
		for xdef in exports_defs:
			var xname: String = str(xdef.get("name", ""))
			var xtype: String = str(xdef.get("type", ""))
			var xdefault = xdef.get("default", "")
			if xname.is_empty():
				continue
			var decl: String = "@export var %s" % xname
			if not xtype.is_empty():
				decl += ": %s" % xtype
			if str(xdefault) != "" and str(xdefault) != "null":
				decl += " = %s" % _format_value(xdefault)
			lines.append(decl)
		lines.append("")

	# Onready refs
	if not onready_defs.is_empty():
		for odef in onready_defs:
			var oname: String = str(odef.get("name", ""))
			var otype: String = str(odef.get("type", ""))
			var opath: String = str(odef.get("path", ""))
			if oname.is_empty():
				continue
			var decl: String = "@onready var %s" % oname
			if not otype.is_empty():
				decl += ": %s" % otype
			if not opath.is_empty():
				decl += " = $%s" % opath
			lines.append(decl)
		if not onready_defs.is_empty():
			lines.append("")

	# Methods
	for mdef in methods_defs:
		var mname: String = str(mdef.get("name", ""))
		var mparams: Array = mdef.get("params", [])
		var mreturns: String = str(mdef.get("returns", ""))
		var mis_static: bool = mdef.get("is_static", false)
		var mbody: String = str(mdef.get("body", "pass # TODO"))
		if mname.is_empty():
			continue

		var decl: String = ""
		if mis_static:
			decl = "static func %s" % mname
		else:
			decl = "func %s" % mname

		if mparams.is_empty():
			decl += "()"
		else:
			decl += "(%s)" % ", ".join(mparams)

		if not mreturns.is_empty():
			decl += " -> %s" % mreturns

		decl += ":"
		lines.append(decl)

		# Indent body
		for body_line in mbody.split("\n"):
			lines.append("\t" + body_line)
		lines.append("")

	# Join and add final newline
	var content: String = "\n".join(lines)
	if not content.ends_with("\n"):
		content += "\n"

	# Syntax validation
	if validate:
		var gs := GDScript.new()
		gs.source_code = content
		var err := gs.reload()
		if err != OK:
			return _err("Syntax validation failed:\n" + content.substr(0, 500))

	# Save
	_ensure_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err("Cannot write to: " + path)
	f.store_string(content)
	f.close()

	_refresh_filesystem()

	return _ok_json({
		"type": "build_script_result",
		"path": path,
		"class_name": class_name_val,
		"extends": extends_val,
		"signals_count": signals_defs.size(),
		"exports_count": exports_defs.size(),
		"methods_count": methods_defs.size(),
		"syntax_valid": true,
		"lines": content.split("\n").size(),
	})


# ============ Tool 2: update_script ============

func _tool_update_script(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var content: String = args.get("content", "")
	var validate: bool = args.get("validate_syntax", true)

	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".gd"):
		return _err("path must end with .gd")
	if content.is_empty():
		return _err("content is required")

	# Syntax validation
	if validate:
		var gs := GDScript.new()
		gs.source_code = content
		var err := gs.reload()
		if err != OK:
			return _err("Syntax validation failed — file not modified")

	# Backup existing file
	if FileAccess.file_exists(path):
		_get_backup().backup(path)

	# Write
	_ensure_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err("Cannot write to: " + path)
	f.store_string(content)
	f.close()

	_refresh_filesystem()

	return _ok_json({
		"type": "update_script_result",
		"path": path,
		"lines": content.split("\n").size(),
		"syntax_valid": true,
	})


# ============ Helpers ============

func _format_value(val: Variant) -> String:
	if val is String:
		var s: String = val
		# Check if it looks like a number or constant
		if s.is_valid_float() or s.is_valid_int() or s == "true" or s == "false" or s == "null":
			return s
		# Check if it's a Vector/Color literal
		if s.begins_with("Vector") or s.begins_with("Color") or s.begins_with("[") or s.begins_with("{"):
			return s
		# Otherwise quote it
		return '"%s"' % s
	if val is bool:
		return "true" if val else "false"
	if val is float or val is int:
		return str(val)
	return str(val)
