extends RefCounted

# Benchmark fixtures contain synthetic prompts. Deliberately exclude raw model
# replies, prompts, paths and arbitrary dictionaries from failure diagnostics.
static func describe(result: Dictionary) -> Dictionary:
	var diagnostic := _fields(result)
	diagnostic["ok"] = bool(result.get("ok", false))
	var attempts: Array = []
	var source = result.get("attempted_models", [])
	if source is Array:
		for value in source:
			if value is Dictionary:
				attempts.append(_fields(value))
			if attempts.size() >= 3:
				break
	diagnostic["attempts"] = attempts
	return diagnostic

static func _fields(value: Dictionary) -> Dictionary:
	var result := {}
	for key in ["error", "failure_scope", "runtime"]:
		if value.has(key):
			result[key] = str(value[key]).substr(0, 600)
	for key in ["model_failure", "retryable", "background_warmup_continues"]:
		if value.has(key):
			result[key] = bool(value[key])
	for key in ["http", "transport_result"]:
		if value.has(key):
			result[key] = int(value[key])
	return result
