@tool
class_name SkillManager
extends RefCounted
## Skill Manager — loads, matches, and injects scene-type domain knowledge.
##
## Skill files live in res://addons/dotagent/skills/*.md
## Format:
##   # triggers: keyword1, keyword2, ...
##   (blank line)
##   ... markdown content ...

var _skills: Array[Dictionary] = []


func _init() -> void:
	_reload()


## Reload all skills from disk (scans builtin/ and custom/).
func _reload() -> void:
	_skills.clear()
	_scan_dir("res://addons/dotagent/skills/builtin/")
	_scan_dir("res://addons/dotagent/skills/custom/")


func _scan_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".md") and not dir.current_is_dir():
			_load_skill(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()


## Parse a single skill file.
func _load_skill(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	var lines := text.split("\n")
	if lines.is_empty():
		return

	# First line: # triggers: kw1, kw2, kw3
	var header := lines[0].strip_edges()
	var triggers: Array[String] = []
	if header.begins_with("# triggers:"):
		var raw := header.trim_prefix("# triggers:").strip_edges()
		for kw in raw.split(",", false):
			var t := kw.strip_edges().to_lower()
			if not t.is_empty():
				triggers.append(t)

	# Content starts after first blank line
	var content_start := 1
	while content_start < lines.size() and not lines[content_start].strip_edges().is_empty():
		content_start += 1
	var content: String = ""
	if content_start < lines.size():
		content = "\n".join(lines.slice(content_start)).strip_edges()

	if content.is_empty():
		return

	var skill_name := path.get_file().trim_suffix(".md")
	_skills.append({
		"name": skill_name,
		"path": path,
		"triggers": triggers,
		"content": content,
	})


## Match user message text against skill triggers.
## Returns concatenated content of all matching skills.
func match(text: String) -> String:
	var lower := text.to_lower()
	var parts: Array[String] = []
	for skill in _skills:
		for trigger in skill.get("triggers", []):
			if trigger in lower:
				parts.append(skill.get("content", ""))
				break
	if parts.is_empty():
		return ""
	return "\n\n---\n\n".join(parts)


## List all loaded skills with their triggers (for the list_skills tool).
func list_skills() -> Array:
	var out: Array = []
	for skill in _skills:
		out.append({
			"name": skill.get("name"),
			"triggers": skill.get("triggers"),
		})
	return out


## Get a specific skill by name.
func get_skill(name: String) -> Dictionary:
	for skill in _skills:
		if skill.get("name") == name:
			return skill
	return {}
