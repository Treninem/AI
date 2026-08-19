class_name ChatStore
extends Node

const SAVE_PATH := "user://aurorafox_chats.json"

var chats: Array = []
var active_chat_id := ""

func _ready() -> void:
	load_all()
	if chats.is_empty():
		create_chat()

func create_chat(title: String = "Новый чат") -> String:
	var id := "%d_%d" % [Time.get_unix_time_from_system(), randi_range(1000, 9999)]
	chats.push_front({
		"id": id,
		"title": title,
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system(),
		"messages": [],
		"attachments": []
	})
	active_chat_id = id
	save_all()
	return id

func get_active_chat() -> Dictionary:
	return get_chat(active_chat_id)

func get_chat(id: String) -> Dictionary:
	for chat in chats:
		if str(chat.get("id", "")) == id:
			return chat
	return {}

func add_message(role: String, content: String, attachments: Array = []) -> void:
	var chat := get_active_chat()
	if chat.is_empty():
		create_chat()
		chat = get_active_chat()
	var messages: Array = chat.get("messages", [])
	messages.append({
		"role": role,
		"content": content,
		# Full extracted PDF/DOCX/XLSX/video text lives in File Intelligence cache and is used
		# for the current task. Chat history keeps only lightweight attachment metadata.
		"attachments": _compact_attachments(attachments),
		"time": Time.get_datetime_string_from_system()
	})
	chat["messages"] = messages
	chat["updated_at"] = Time.get_datetime_string_from_system()
	if role == "user" and messages.size() == 1:
		var clean := content.strip_edges().replace("\n", " ")
		chat["title"] = clean.substr(0, 38) if clean.length() > 0 else "Новый чат"
	save_all()

func _compact_attachments(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if not item is Dictionary: continue
		var compact := {
			"path": str(item.get("path", "")),
			"name": str(item.get("name", "file")),
			"extension": str(item.get("extension", "")),
			"kind": str(item.get("kind", "unknown")),
			"size": int(item.get("size", 0)),
			"metadata": item.get("metadata", {}),
			"warnings": item.get("warnings", []),
			"truncated": bool(item.get("truncated", false)),
			"cached": bool(item.get("cached", false)),
			"analyzed": bool(item.get("analyzed", false))
		}
		if item.has("private_copy"): compact["private_copy"] = str(item.get("private_copy", ""))
		out.append(compact)
	return out

func rename_chat(id: String, title: String) -> void:
	var chat := get_chat(id)
	if chat.is_empty(): return
	chat["title"] = title.strip_edges().substr(0, 60)
	save_all()

func delete_chat(id: String) -> void:
	for i in range(chats.size() - 1, -1, -1):
		if str(chats[i].get("id", "")) == id:
			chats.remove_at(i)
			break
	if chats.is_empty():
		create_chat()
	else:
		active_chat_id = str(chats[0].get("id", ""))
	save_all()

func search(query: String) -> Array:
	var q := query.to_lower().strip_edges()
	if q.is_empty(): return chats
	var result: Array = []
	for chat in chats:
		if str(chat.get("title", "")).to_lower().contains(q):
			result.append(chat)
			continue
		for message in chat.get("messages", []):
			if str(message.get("content", "")).to_lower().contains(q):
				result.append(chat)
				break
	return result

func save_all() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"active_chat_id": active_chat_id, "chats": chats}))
		file.close()

func load_all() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY: return
	chats = parsed.get("chats", [])
	active_chat_id = str(parsed.get("active_chat_id", ""))
	if active_chat_id.is_empty() and not chats.is_empty():
		active_chat_id = str(chats[0].get("id", ""))
