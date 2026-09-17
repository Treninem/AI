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
	var context_paths: Array[String] = []
	for item in files:
		if item is Dictionary:
			var candidate := str(item.get("path", item.get("name", ""))).strip_edges()
			if not candidate.is_empty():
				context_paths.append(candidate)
	var prompt := """
You are AuroraFox Code Generator. Produce the smallest complete implementation that satisfies the task and fits the supplied project context.
Return strict JSON only:
{"files":[{"path":"relative/path.ext","language":"...","content":"complete file or patch-ready replacement"}],"explanation":"...","validation":["..."]}
Rules:
- `files` is mandatory and MUST contain at least one entry whenever implementation is requested;
- when project context already provides a target file, use that exact relative path instead of inventing another one;
- every files entry must contain non-empty `path` and non-empty `content`;
- preserve the project language/framework and public contracts unless the task explicitly changes them;
- never invent successful test/build results;
- no TODO/FIXME/placeholders;
- use only the files needed for the task.
Expected context paths: %s
Task: %s
Project context:
%s
""" % [JSON.stringify(context_paths), task, _files_context(files)]
	var response := await _chat_code([{"role":"user","content":prompt}], 0.12)
	if not response.get("ok", false):
		return response
	var raw := str(response.get("content", ""))
	var parsed := _parse_json(raw)
	if parsed.is_empty():
		return {"ok":false,"error":"Code Generator returned invalid JSON","raw":raw}
	var generated := _valid_generated_files(parsed.get("files", []))
	if generated.is_empty():
		var repaired := await _repair_generated_code_response(task, files, raw, context_paths)
		if not repaired.get("ok", false):
			return repaired
		parsed = repaired
		generated = _valid_generated_files(parsed.get("files", []))
	if generated.is_empty():
		return {"ok":false,"error":"Code Generator returned no usable files after repair","raw":raw}
	parsed["files"] = generated
	parsed["ok"] = true
	return parsed

func _repair_generated_code_response(task: String, files: Array, raw: String, context_paths: Array[String]) -> Dictionary:
	var repair_prompt := """
You are repairing the STRUCTURE of a previous AuroraFox Code Generator answer. The implementation task still requires actual code.
Return one strict JSON object using exactly this top-level shape:
{"files":[{"path":"relative/path.ext","language":"...","content":"complete implementation"}],"explanation":"...","validation":["..."]}
Requirements:
- `files` must contain at least one usable file;
- prefer one of these existing context paths: %s;
- `path` and `content` must be non-empty;
- preserve any correct implementation content from the previous answer;
- if the previous answer omitted code, generate the smallest complete implementation now;
- never claim validation was executed.
Task: %s
Project context:
%s
Previous answer to repair:
%s
""" % [JSON.stringify(context_paths), task, _files_context(files, 50000), raw.substr(0, 30000)]
	var response := await _chat_code([{"role":"user","content":repair_prompt}], 0.02)
	if not response.get("ok", false):
		return {"ok":false,"error":"Code Generator repair request failed: %s" % str(response.get("error", "unknown")),"raw":raw}
	var repaired_raw := str(response.get("content", ""))
	var repaired := _parse_json(repaired_raw)
	if repaired.is_empty():
		return {"ok":false,"error":"Code Generator repair returned invalid JSON","raw":repaired_raw}
	var repaired_files := _valid_generated_files(repaired.get("files", []))
	if repaired_files.is_empty():
		return {"ok":false,"error":"Code Generator repair returned no usable files","raw":repaired_raw}
	repaired["files"] = repaired_files
	repaired["ok"] = true
	repaired["repaired_structure"] = true
	return repaired

func _valid_generated_files(value: Variant) -> Array:
	if not value is Array:
		return []
	var result: Array = []
	for item in value:
		if not item is Dictionary:
			continue
		var path := str(item.get("path", "")).strip_edges()
		var content := str(item.get("content", "")).strip_edges()
		if path.is_empty() or content.is_empty():
			continue
		result.append(item)
	return result

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
{"understands_code":true,"issues":[{"severity":"high|medium|low","problem":"...","fix":"..."}],"tests":["..."],"verdict":"...","confidence":0.0}
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
	parsed["ok"] = true
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
	var refactored_code := str(parsed.get("refactored_code", "")).strip_edges()
	if refactored_code.is_empty():
		return {"ok":false,"error":"Refactoring Specialist returned no refactored code","raw":response.get("content", "")}
	var changes = parsed.get("changes", [])
	if not changes is Array:
		return {"ok":false,"error":"Refactoring Specialist returned invalid changes structure","raw":response.get("content", "")}
	if changes.is_empty():
		if refactored_code == code.strip_edges():
			return {"ok":false,"error":"Refactoring Specialist returned a no-op refactor","raw":response.get("content", "")}
		parsed["changes"] = [_describe_code_delta(code, refactored_code)]
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
	var parsed = JSON.parse_string(cleaned)
	if parsed is Dictionary:
		return parsed

	# Local models sometimes wrap an otherwise valid JSON object in a Markdown
	# fence or add a short sentence before/after it. Recover only the first
	# syntactically valid object; never execute or reinterpret free-form text.
	if cleaned.begins_with("```"):
		var first_newline := cleaned.find("\n")
		var closing_fence := cleaned.rfind("```")
		if first_newline >= 0 and closing_fence > first_newline:
			var fenced := cleaned.substr(first_newline + 1, closing_fence - first_newline - 1).strip_edges()
			parsed = JSON.parse_string(fenced)
			if parsed is Dictionary:
				return parsed

	var extracted := _extract_first_json_object(cleaned)
	if extracted.is_empty():
		return {}
	parsed = JSON.parse_string(extracted)
	return parsed if parsed is Dictionary else {}

func _extract_first_json_object(text: String) -> String:
	var start := text.find("{")
	while start >= 0:
		var depth := 0
		var in_string := false
		var escaped := false
		for i in range(start, text.length()):
			var ch := text.substr(i, 1)
			if in_string:
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == "\"":
					in_string = false
				continue
			if ch == "\"":
				in_string = true
			elif ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
				if depth == 0:
					var candidate := text.substr(start, i - start + 1)
					if JSON.parse_string(candidate) is Dictionary:
						return candidate
					break
		start = text.find("{", start + 1)
	return ""

func _describe_code_delta(original: String, refactored: String) -> String:
	var before_lines := original.split("\n").size()
	var after_lines := refactored.split("\n").size()
	if after_lines < before_lines:
		return "Simplified implementation while preserving the requested contract (%d -> %d lines)." % [before_lines, after_lines]
	if after_lines > before_lines:
		return "Reworked implementation while preserving the requested contract (%d -> %d lines)." % [before_lines, after_lines]
	return "Changed implementation details while preserving the requested contract."
