@tool
extends SceneTree
## 验证 replace_in_file 的模糊匹配自愈（缩进容错 + 相似区域回读）
## 运行: godot --headless --path <project> --script res://tests/_test_fuzzy_replace.gd

const ScriptTools = preload("res://addons/dotagent/tools/script_tools.gd")

var _pass: int = 0
var _fail: int = 0
var _tools = null
# 用 .txt 跳过 GDScript 语法校验链路（校验链在真实运行中已覆盖；
# 本测试只验证模糊匹配逻辑，避免无头嵌套子进程在 Windows 上管道死锁）
var _tmp := "res://tests/_fuzzy_tmp.txt"


func _init() -> void:
	_tools = ScriptTools.new()
	_tools.set_editor_context(null, null)

	# 用例 1：文件用 tab 缩进，模型用 4 空格缩进 → 应模糊命中并自动修正
	_write("extends Node\n\nfunc foo() -> void:\n\tvar x: int = 1\n\tprint(x)\n")
	var r1: Dictionary = await _tools.call("_tool_replace_in_file", {
		"path": _tmp,
		"old_text": "func foo() -> void:\n    var x: int = 1\n    print(x)",
		"new_text": "func foo() -> void:\n    var x: int = 2\n    print(x)",
	})
	_t("fuzzy match applies with indent fix", r1.get("ok", false) == true)
	_t("file content has tab-indented x=2", _read().contains("\tvar x: int = 2"))
	_t("no space-indent pollution", not _read().contains("    var x"))

	# 用例 2：嵌套层级保留（new_text 的相对缩进不变）
	_write("extends Node\n\nfunc bar() -> void:\n\tif true:\n\t\tprint(1)\n")
	var r2: Dictionary = await _tools.call("_tool_replace_in_file", {
		"path": _tmp,
		"old_text": "func bar() -> void:\n  if true:\n    print(1)",
		"new_text": "func bar() -> void:\n  if true:\n    if false:\n      print(2)",
	})
	_t("nested fuzzy applies", r2.get("ok", false) == true)
	_t("nested indent preserved", _read().contains("\tif true:\n\t\tif false:\n\t\t\tprint(2)"))

	# 用例 3：完全不沾边 → 报错并回读最相似区域
	_write("extends Node\n\nfunc baz() -> void:\n\tpass\n")
	var r3: Dictionary = await _tools.call("_tool_replace_in_file", {
		"path": _tmp,
		"old_text": "func nonexistent() -> void:\n\tvar q: int = 9",
		"new_text": "whatever",
	})
	_t("no match returns error", r3.get("ok", true) == false)
	_t("error includes actual file content", str(r3.get("content", "")).contains("ACTUAL FILE CONTENT"))
	_t("file untouched", _read().contains("func baz"))

	DirAccess.remove_absolute(_tmp)
	print("=== Results: %d/%d passed ===" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)


func _t(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s" % name)


func _write(text: String) -> void:
	var f := FileAccess.open(_tmp, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read() -> String:
	return FileAccess.get_file_as_string(_tmp)
