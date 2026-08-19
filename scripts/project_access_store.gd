class_name ProjectAccessStore
extends Node

const PATH := "user://trusted_projects.json"

var roots: Array[String] = []

func _ready() -> void:
	_load()

func add_root(path: String) -> bool:
	var normalized := normalize(path)
	if normalized.is_empty(): return false
	if not DirAccess.dir_exists_absolute(normalized): return false
	for root in roots:
		if _key(root) == _key(normalized): return true
	roots.append(normalized)
	_save()
	return true

func remove_root(path: String) -> void:
	var key := _key(path)
	for i in range(roots.size() - 1, -1, -1):
		if _key(roots[i]) == key: roots.remove_at(i)
	_save()

func is_trusted_root(path: String) -> bool:
	var key := _key(normalize(path))
	if key.is_empty(): return false
	for root in roots:
		if _key(root) == key: return true
	return false

func all_roots() -> Array[String]:
	return roots.duplicate()

func normalize(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.begins_with("res://") or p.begins_with("user://"):
		p = ProjectSettings.globalize_path(p).replace("\\", "/")
	while p.ends_with("/") and p.length() > 3: p = p.trim_suffix("/")
	return p

func _key(path: String) -> String:
	var value := normalize(path)
	return value.to_lower() if OS.get_name() == "Windows" else value

func _load() -> void:
	roots.clear()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		for item in parsed:
			var normalized := normalize(str(item))
			if not normalized.is_empty() and DirAccess.dir_exists_absolute(normalized): roots.append(normalized)

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(roots, "  "))
	f.close()
