class_name CoreProgressStream
extends RefCounted

var pending := PackedByteArray()
var scan := 0
var content := ""
var reasoning := ""
var done := false
var finished := false
var error := ""
var processed := -1
var generated_bytes := 0
var received_bytes := 0
var byte_budget := 4194304
var started_ms := 0
var progress_ms := 0
var stall_ms := 90000
var total_ms := 0

func configure(now: int, stall_seconds: float, total_seconds: float, budget: int) -> void:
	started_ms = now
	progress_ms = now
	stall_ms = int(maxf(0.0, stall_seconds) * 1000.0)
	total_ms = int(maxf(0.0, total_seconds) * 1000.0)
	byte_budget = budget

func timeout_reason(now: int) -> String:
	if total_ms > 0 and now - started_ms >= total_ms: return "total_budget"
	if stall_ms > 0 and now - progress_ms >= stall_ms: return "no_progress"
	return ""

func feed(bytes: PackedByteArray, now: int) -> void:
	if done or not error.is_empty(): return
	received_bytes += bytes.size()
	if byte_budget > 0 and received_bytes > byte_budget:
		error = "Core response exceeds owner byte budget"
		return
	pending.append_array(bytes)
	# Decode only complete SSE frames: a UTF8 codepoint may cross TCP chunks.
	while scan < pending.size():
		var delimiter := 0
		if scan >= 1 and pending[scan - 1] == 10 and pending[scan] == 10: delimiter = 2
		elif scan >= 3 and pending[scan - 3] == 13 and pending[scan - 2] == 10 and pending[scan - 1] == 13 and pending[scan] == 10: delimiter = 4
		if delimiter > 0:
			var frame := pending.slice(0, scan + 1 - delimiter).get_string_from_utf8().replace("\r\n", "\n")
			pending = pending.slice(scan + 1)
			scan = 0
			_frame(frame, now)
			if done or not error.is_empty(): return
		else:
			scan += 1

func _frame(frame: String, now: int) -> void:
	var lines := PackedStringArray()
	for line in frame.split("\n"):
		if line.begins_with("data:"):
			var value := line.substr(5)
			if value.begins_with(" "): value = value.substr(1)
			lines.append(value)
	if lines.is_empty(): return # Comments/heartbeat/connection activity are not work.
	var data := "\n".join(lines)
	if data == "[DONE]":
		if not finished: error = "Core stream ended without a completion result"
		else: done = true
		return
	var parsed = JSON.parse_string(data)
	if not parsed is Dictionary:
		error = "Invalid Core streaming JSON"
		return
	if parsed.has("error"):
		error = "Core streaming backend error"
		return
	var progress = parsed.get("prompt_progress", {})
	if progress is Dictionary and progress.has("processed"):
		var value = progress.get("processed")
		if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0:
			var count := int(value)
			if count > processed:
				# An initial zero, clock/timing or total-only changes prove no work.
				if count > 0: progress_ms = now
				processed = count
	var choices = parsed.get("choices", [])
	if not choices is Array:
		error = "Invalid Core streaming choices"
		return
	for choice in choices:
		if not choice is Dictionary:
			error = "Invalid Core streaming choice"
			return
		if int(choice.get("index", 0)) != 0: continue
		var delta = choice.get("delta", {})
		if not delta is Dictionary:
			error = "Invalid Core streaming delta"
			return
		var text = delta.get("content", "")
		var thought = delta.get("reasoning_content", "")
		if (text != null and not text is String) or (thought != null and not thought is String):
			error = "Invalid Core streaming text"
			return
		var addition := (text as String) if text is String else ""
		var thinking := (thought as String) if thought is String else ""
		if not addition.is_empty() or not thinking.is_empty():
			content += addition
			reasoning += thinking
			generated_bytes += addition.to_utf8_buffer().size() + thinking.to_utf8_buffer().size()
			progress_ms = now
		if choice.get("finish_reason") != null: finished = true

func result() -> Dictionary:
	return {"choices": [{"index": 0, "message": {"role": "assistant", "content": content, "reasoning_content": reasoning}}]}
