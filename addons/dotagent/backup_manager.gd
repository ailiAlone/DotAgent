@tool
class_name BackupManager
extends RefCounted
## 备份管理
##
## 写操作前自动备份原文件到 res://.dotagent_backups/<timestamp>/<rel_path>
## - 备份根目录:res://.dotagent_backups/
## - 最多保留 50 个时间戳目录(老的自动清理)
## - 备份不进 git(写到 .gitignore)

const BACKUP_ROOT := "res://.dotagent_backups"
const MAX_BACKUP_DIRS := 50


## 备份一个文件,返回备份后的路径(失败返回空字符串)
func backup(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var ts := Time.get_datetime_string_from_system(true).replace(":", "-").replace("T", "_")
	var backup_dir := BACKUP_ROOT.path_join(ts)
	var rel := file_path
	if rel.begins_with("res://"):
		rel = rel.substr(6)
	var dst := backup_dir.path_join(rel)
	_ensure_dir(dst)
	var src := FileAccess.open(file_path, FileAccess.READ)
	if src == null:
		return ""
	var content := src.get_as_text()
	src.close()
	var dst_f := FileAccess.open(dst, FileAccess.WRITE)
	if dst_f == null:
		return ""
	dst_f.store_string(content)
	dst_f.close()
	_cleanup_old()
	return dst


func list_backups() -> Array:
	var d := DirAccess.open(BACKUP_ROOT)
	if d == null:
		return []
	var dirs: Array = []
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			dirs.append(name)
		name = d.get_next()
	d.list_dir_end()
	dirs.sort()
	return dirs


func _ensure_dir(path: String) -> void:
	var last_slash := path.rfind("/")
	if last_slash <= 0:
		return
	var dir := path.substr(0, last_slash)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


func _cleanup_old() -> void:
	var d := DirAccess.open(BACKUP_ROOT)
	if d == null:
		return
	var dirs: Array = []
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			dirs.append(name)
		name = d.get_next()
	d.list_dir_end()
	if dirs.size() <= MAX_BACKUP_DIRS:
		return
	dirs.sort()
	var to_remove := dirs.slice(0, dirs.size() - MAX_BACKUP_DIRS)
	for old in to_remove:
		var full := BACKUP_ROOT.path_join(old)
		_rm_recursive(full)


func _rm_recursive(path: String) -> void:
	# 走 mavis-trash 更安全,但这里要能在没有 daemon 的情况下工作
	# 用 DirAccess 内置删除
	var d := DirAccess.open(path)
	if d == null:
		# 可能是文件,不是目录
		DirAccess.remove_absolute(path)
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path.path_join(name)
		if d.current_is_dir():
			_rm_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)
