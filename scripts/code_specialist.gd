class_name CodeSpecialist
extends Node

var general_ai: AIClient
var registry := CodeLanguageRegistry.new()
var ollama_url := "http://127.0.0.1:11434"
var code_model := "qwen3-coder:30b"

func setup(ai_client: AIClient) -> void:
	general_ai = ai_client
	ollama_url = ai_client.base_url

func analyze_request(task: String, files: Array = []) -> Dictionary:
	var hints: Array = []
	for item in files:
		if item is Dictionary:
			var path := str(item.get("path", item.get("name", "")))
			var lang := registry.detect_from_path(path)
			if lang != "unknown" and lang not in hints:
				hints.append(lang)
	var prompt := """
You are AuroraFox Code Architect. Understand the programming task before writing code.
Return strict JSON only with:
{
  "summary":"what the user actually needs",
  "languages":["..."],
  "project_type":"...",
  "files_to_inspect":["..."],
  "implementation_plan":["..."],
  "validation_plan":["..."],
  "risks":["..."],
  "assumptions":["..."]
}
Prefer the language/framework already used by the project unless the user explicitly requests another.
Do not claim a compiler, runtime, package or test passed unless it was actually run.
Known language hints: %s
Task: %s
""" % [JSON.stringify(hints), task]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.1)
	if not response.get("ok", false):
		return {"ok":false,"error":response.get("error", "code model unavailable")}
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Code Architect returned invalid JSON","raw":response.get("content", "")}
	parsed["ok"] = true
	return parsed

func review_code(task: String, code_or_diff: String, language: String = "unknown") -> Dictionary:
	var lang_info := registry.describe(language)
	var prompt := """
You are the AuroraFox senior code reviewer. Review the code/diff for correctness, security, edge cases,
resource leaks, concurrency issues, API misuse, maintainability and whether it actually satisfies the task.
Return strict JSON only:
{"ok":true,"understands_code":true,"issues":[{"severity":"high|medium|low","problem":"...","fix":"..."}],"tests":["..."],"verdict":"...","confidence":0.0}
Language metadata: %s
Task: %s
Code or diff:
%s
""" % [JSON.stringify(lang_info), task, code_or_diff.substr(0, 120000)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.05)
	if not response.get("ok", false):
		return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Reviewer returned invalid JSON","raw":response.get("content", "")}
	return parsed

func explain_code(code: String, language: String = "unknown") -> Dictionary:
	var prompt := """
You are AuroraFox Code Comprehension. Explain what this code actually does, not just line-by-line syntax.
Identify inputs, outputs, state, data flow, side effects, invariants, failure modes, external dependencies and algorithmic complexity.
Return strict JSON only:
{"purpose":"...","data_flow":["..."],"side_effects":["..."],"dependencies":["..."],"failure_modes":["..."],"complexity":"...","uncertainties":["..."]}
Language: %s
Code:
%s
""" % [language, code.substr(0, 120000)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.1)
	if not response.get("ok", false): return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty(): return {"ok":false,"error":"Invalid comprehension JSON"}
	parsed["ok"] = true
	return parsed

func _chat_code(messages: Array, temperature: float) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 300.0
	add_child(request)
	var payload := {"model":code_model,"messages":messages,"stream":false,"options":{"temperature":temperature}}
	var err := request.request(ollama_url + "/api/chat", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request.queue_free()
		return await general_ai.chat(messages, temperature)
	var result: Array = await request.request_completed
	request.queue_free()
	var code := int(result[1])
	if code < 200 or code >= 300:
		return await general_ai.chat(messages, temperature)
	var data = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if data is Dictionary:
		return {"ok":true,"content":str(data.get("message", {}).get("content", "")),"model":code_model}
	return await general_ai.chat(messages, temperature)

func _parse_json(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Dictionary else {}
