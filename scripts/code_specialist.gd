class_name CodeSpecialist
extends Node

var general_ai: AIClient
var registry := CodeLanguageRegistry.new()

func setup(ai_client: AIClient) -> void:
	general_ai = ai_client

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

func generate_code(task: String, files: Array = []) -> Dictionary:
	var prompt := """
You are AuroraFox Code Generator. Produce the smallest complete implementation that satisfies the task and fits the supplied project context.
Return strict JSON only:
{"files":[{"path":"relative/path.ext","language":"...","content":"complete file or patch-ready replacement"}],"explanation":"...","validation":["..."]}
Rules:
- preserve the project language/framework and public contracts unless the task explicitly changes them;
- never invent successful test/build results;
- no TODO/FIXME/placeholders;
- use only the files needed for the task.
Task: %s
Project context:
%s
""" % [task, _files_context(files)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.12)
	if not response.get("ok", false):
		return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Code Generator returned invalid JSON","raw":response.get("content", "")}
	var generated = parsed.get("files", [])
	if not generated is Array or generated.is_empty():
		return {"ok":false,"error":"Code Generator returned no files","raw":response.get("content", "")}
	parsed["ok"] = true
	return parsed

func debug_code(task: String, code_or_error: String, language: String = "unknown") -> Dictionary:
	var prompt := """
You are AuroraFox Debugger. Diagnose the concrete defect before proposing a fix.
Return strict JSON only:
{"root_cause":"...","evidence":["..."],"corrected_code":"...","tests":["..."],"residual_risks":["..."]}
Do not claim a test was executed. Preserve unrelated behavior and public APIs.
Language: %s
Task / observed failure: %s
Code, traceback, logs or diff:
%s
""" % [language, task, code_or_error.substr(0, 120000)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.05)
	if not response.get("ok", false):
		return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Debugger returned invalid JSON","raw":response.get("content", "")}
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

func refactor_code(task: String, code: String, language: String = "unknown") -> Dictionary:
	var prompt := """
You are AuroraFox Refactoring Specialist. Improve the code for the requested goal without changing required externally visible behavior.
Return strict JSON only:
{"refactored_code":"...","changes":["..."],"preserved_contracts":["..."],"tests":["..."],"risks":["..."]}
Do not claim tests were executed and do not introduce placeholders.
Language: %s
Refactoring goal: %s
Current code:
%s
""" % [language, task, code.substr(0, 120000)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.08)
	if not response.get("ok", false):
		return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Refactoring Specialist returned invalid JSON","raw":response.get("content", "")}
	parsed["ok"] = true
	return parsed

func generate_tests(task: String, code: String, language: String = "unknown") -> Dictionary:
	var prompt := """
You are AuroraFox Test Engineer. Design executable tests that validate the requested behavior, important edge cases and regressions in the supplied code.
Return strict JSON only:
{"framework":"...","test_code":"...","cases":[{"name":"...","purpose":"..."}],"coverage_notes":["..."]}
Do not claim tests were executed. Prefer the ecosystem's standard lightweight test style when no framework is supplied.
Language: %s
Testing goal: %s
Code under test:
%s
""" % [language, task, code.substr(0, 120000)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.08)
	if not response.get("ok", false):
		return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Test Engineer returned invalid JSON","raw":response.get("content", "")}
	var cases = parsed.get("cases", [])
	if not cases is Array or cases.is_empty():
		return {"ok":false,"error":"Test Engineer returned no test cases","raw":response.get("content", "")}
	parsed["ok"] = true
	return parsed

func reason_across_files(task: String, files: Array) -> Dictionary:
	if files.size() < 2:
		return {"ok":false,"error":"Multi-file reasoning requires at least two files"}
	var prompt := """
You are AuroraFox Multi-file Code Reasoner. Trace contracts and data flow across the supplied files before recommending changes.
Return strict JSON only:
{"summary":"...","dependencies":[{"from":"...","to":"...","contract":"..."}],"changes":[{"path":"...","reason":"..."}],"risks":["..."],"validation":["..."]}
Do not invent files outside the supplied context unless the task explicitly requires a new file. Do not claim tests were executed.
Task: %s
Files:
%s
""" % [task, _files_context(files, 120000)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.08)
	if not response.get("ok", false):
		return response
	var parsed := _parse_json(str(response.get("content", "")))
	if parsed.is_empty():
		return {"ok":false,"error":"Multi-file Code Reasoner returned invalid JSON","raw":response.get("content", "")}
	var dependencies = parsed.get("dependencies", [])
	var changes = parsed.get("changes", [])
	if not dependencies is Array or not changes is Array:
		return {"ok":false,"error":"Multi-file Code Reasoner returned invalid dependency/change structure"}
	parsed["ok"] = true
	return parsed

func _chat_code(messages: Array, temperature: float) -> Dictionary:
	if general_ai == null:
		return {"ok":false,"error":"AuroraFox Core client is not configured"}
	# Code reasoning is part of AuroraFox intelligence and must use the same
	# bundled-Core normal path as chat/planning. Provider-specific compatibility
	# is explicit elsewhere and must never precede this path.
	return await general_ai.chat(messages, temperature)

func _files_context(files: Array, max_chars: int = 90000) -> String:
	var rows: Array[String] = []
	var remaining := maxi(0, max_chars)
	for item in files:
		if remaining <= 0:
			break
		if not item is Dictionary:
			continue
		var path := str(item.get("path", item.get("name", "unknown"))).strip_edges()
		var content := str(item.get("content", ""))
		var language := str(item.get("language", registry.detect_from_path(path)))
		var header := "--- %s [%s] ---\n" % [path, language]
		var available := maxi(0, remaining - header.length())
		var clipped := content.substr(0, available)
		var row := header + clipped
		rows.append(row)
		remaining -= row.length()
	return "\n".join(rows)

func _parse_json(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("```"):
		cleaned = cleaned.replace("```json", "").replace("```", "").strip_edges()
	var parsed = JSON.parse_string(cleaned)
	return parsed if parsed is Dictionary else {}
