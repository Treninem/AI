class_name ChatStore
extends Node

const SAVE_PATH := "user://aurorafox_chats.json"

var chats: Array = []
var active_chat_id := ""
var _save_queued := false
var _save_in_progress := false

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
	queue_save()
	return id

func get_active_chat() -> Dictionary:
	return get_chat(active_chat_id)

func get_chat(id: String) -> Dictionary:
	for chat in chats:
		if str(chat.get("id", "")) == id:
			return chat
	return {}

func add_message(role: String, content: String, attachments: Array = [], metadata: Dictionary = {}) -> String:
	var chat := get_active_chat()
	if chat.is_empty():
		create_chat()
		chat = get_active_chat()
	var messages: Array = chat.get("messages", [])
	var message_id := _new_message_id()
	messages.append({
		"id": message_id,
		"role": role,
		"content": content,
		# Full extraction stays in File Intelligence cache. History keeps a short excerpt so
		# follow-up questions such as “а что во второй части файла?” retain useful context.
		"attachments": _compact_attachments(attachments),
		"time": Time.get_datetime_string_from_system(),
		"metadata": metadata.duplicate(true),
		"feedback": {}
	})
	chat["messages"] = messages
	chat["updated_at"] = Time.get_datetime_string_from_system()
	if role == "user" and messages.size() == 1:
		var clean := content.strip_edges().replace("\n", " ")
		chat["title"] = OwnerResourcePolicy.clip(clean, "chat_auto_title_chars") if clean.length() > 0 else "Новый чат"
	# Paint the newly appended message in the same frame. Persist on the next
	# idle turn so long Android histories cannot block live presentation.
	queue_save()
	return message_id

func set_message_feedback(message_id: String, score: int, analysis: Dictionary = {}, state := "recorded") -> bool:
	if message_id.is_empty() or score < -1 or score > 1:
		return false
	for chat in chats:
		if not chat is Dictionary:
			continue
		var messages: Array = chat.get("messages", [])
		for i in range(messages.size()):
			var message = messages[i]
			if not message is Dictionary or str(message.get("id", "")) != message_id:
				continue
			message["feedback"] = {} if score == 0 else {
				"score": score,
				"state": state,
				"analysis": analysis.duplicate(true),
				"updated_at": Time.get_datetime_string_from_system(true)
			}
			messages[i] = message
			chat["messages"] = messages
			chat["updated_at"] = Time.get_datetime_string_from_system()
			queue_save()
			return true
	return false

func feedback_context(message_id: String) -> Dictionary:
	for chat in chats:
		if not chat is Dictionary:
			continue
		var messages: Array = chat.get("messages", [])
		for i in range(messages.size()):
			var message = messages[i]
			if not message is Dictionary or str(message.get("id", "")) != message_id:
				continue
			var prompt := ""
			for previous in range(i - 1, -1, -1):
				var candidate = messages[previous]
				if candidate is Dictionary and str(candidate.get("role", "")) == "user":
					prompt = str(candidate.get("content", ""))
					break
			return {
				"conversation_id": str(chat.get("id", "")),
				"message_id": message_id,
				"prompt": prompt,
				"answer": str(message.get("content", "")),
				"metadata": message.get("metadata", {}),
				"feedback": message.get("feedback", {})
			}
	return {}

func _new_message_id() -> String:
	return "msg_%d_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi_range(1000, 9999)]

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
			"analyzed": bool(item.get("analyzed", false)),
			"excerpt": OwnerResourcePolicy.clip(str(item.get("content", "")), "chat_attachment_chars")
		}
		if item.has("private_copy"): compact["private_copy"] = str(item.get("private_copy", ""))
		out.append(compact)
	return out

func rename_chat(id: String, title: String) -> void:
	var chat := get_chat(id)
	if chat.is_empty(): return
	chat["title"] = OwnerResourcePolicy.clip(title.strip_edges(), "chat_title_chars")
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
			for attachment in message.get("attachments", []):
				if str(attachment.get("name", "")).to_lower().contains(q) or str(attachment.get("excerpt", "")).to_lower().contains(q):
					result.append(chat)
					break
	return result

func save_all() -> void:
	_save_queued = false
	_save_in_progress = true
	var temporary := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"active_chat_id": active_chat_id, "chats": chats}))
		file.close()
		var target := ProjectSettings.globalize_path(SAVE_PATH)
		var source := ProjectSettings.globalize_path(temporary)
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(target)
		DirAccess.rename_absolute(source, target)
	_save_in_progress = false

func queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	call_deferred("_flush_queued_save")

func _flush_queued_save() -> void:
	if not _save_queued or _save_in_progress:
		return
	save_all()

func _exit_tree() -> void:
	if _save_queued and not _save_in_progress:
		save_all()

func load_all() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY: return
	chats = parsed.get("chats", [])
	_migrate_message_identity()
	active_chat_id = str(parsed.get("active_chat_id", ""))
	if active_chat_id.is_empty() and not chats.is_empty():
		active_chat_id = str(chats[0].get("id", ""))

func _migrate_message_identity() -> void:
	var changed := false
	for chat in chats:
		if not chat is Dictionary:
			continue
		var messages: Array = chat.get("messages", [])
		for i in range(messages.size()):
			var message = messages[i]
			if not message is Dictionary:
				continue
			if str(message.get("id", "")).is_empty():
				message["id"] = _new_message_id()
				changed = true
			if not message.has("metadata"):
				message["metadata"] = {}
				changed = true
			if not message.has("feedback"):
				message["feedback"] = {}
				changed = true
			messages[i] = message
		chat["messages"] = messages
	if changed:
		queue_save()
