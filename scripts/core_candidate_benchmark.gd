class_name CoreCandidateBenchmark
extends RefCounted

const MAX_SOURCE_GROWTH_RATIO := 1.35
const RISKY_PRIMITIVES := [
	"OS.execute(",
	"OS.create_process(",
	"HTTPRequest.new(",
	"HTTPClient.new(",
	"TCPServer.new(",
	"StreamPeerTCP.new(",
	"PacketPeerUDP.new(",
	"WebSocketPeer.new(",
	"JavaScriptBridge",
	"Engine.get_singleton("
]

func source_contract(original: String, candidate: String, target: String) -> Dictionary:
	var baseline_public := _public_functions(original)
	var candidate_public := _public_functions(candidate)
	var missing_public: Array[String] = []
	for name in baseline_public:
		if name not in candidate_public:
			missing_public.append(name)

	var baseline_signals := _signals(original)
	var candidate_signals := _signals(candidate)
	var missing_signals: Array[String] = []
	for name in baseline_signals:
		if name not in candidate_signals:
			missing_signals.append(name)

	var risky_increases := {}
	for marker in RISKY_PRIMITIVES:
		var before := original.count(marker)
		var after := candidate.count(marker)
		if after > before:
			risky_increases[marker] = {"before": before, "after": after}

	var baseline_bytes := original.to_utf8_buffer().size()
	var candidate_bytes := candidate.to_utf8_buffer().size()
	var growth_ratio := float(candidate_bytes) / float(maxi(1, baseline_bytes))
	var growth_ok := growth_ratio <= MAX_SOURCE_GROWTH_RATIO
	var ok := missing_public.is_empty() and missing_signals.is_empty() and risky_increases.is_empty() and growth_ok
	return {
		"ok": ok,
		"target": target,
		"baseline_public_functions": baseline_public,
		"candidate_public_functions": candidate_public,
		"missing_public_functions": missing_public,
		"baseline_signals": baseline_signals,
		"candidate_signals": candidate_signals,
		"missing_signals": missing_signals,
		"risky_primitive_increases": risky_increases,
		"baseline_bytes": baseline_bytes,
		"candidate_bytes": candidate_bytes,
		"growth_ratio": growth_ratio,
		"max_growth_ratio": MAX_SOURCE_GROWTH_RATIO,
		"growth_ok": growth_ok
	}

func commands_for_target(target: String) -> Array:
	var scripts: Array[String] = []
	match target:
		"scripts/memory_store.gd":
			scripts = ["tests/local_semantic_memory_smoke.gd", "tests/semantic_memory_smoke.gd"]
		"scripts/agent_core.gd":
			scripts = ["tests/autonomous_coordinator_smoke.gd", "tests/chat_context_smoke.gd"]
		"scripts/cognition_layer.gd":
			scripts = ["tests/autonomous_coordinator_smoke.gd", "tests/self_improver_smoke.gd"]
		"agent/goals.gd":
			scripts = ["tests/autonomous_coordinator_smoke.gd"]
		_:
			return []
	var commands: Array = []
	for script in scripts:
		commands.append(["godot", "--headless", "--path", ".", "--script", script])
	return commands

func summarize_runs(results: Array) -> Dictionary:
	var passed := 0
	var failed := 0
	var evidence: Array = []
	for row in results:
		if not row is Dictionary:
			failed += 1
			continue
		var ok := bool(row.get("ok", false))
		if ok: passed += 1
		else: failed += 1
		evidence.append({
			"ok": ok,
			"command": row.get("command", []),
			"code": row.get("code", row.get("exit_code", -1)),
			"elapsed_ms": row.get("elapsed_ms", 0),
			"error": str(row.get("error", "")).substr(0, 800)
		})
	return {
		"ok": failed == 0 and passed > 0,
		"passed": passed,
		"failed": failed,
		"total": passed + failed,
		"evidence": evidence
	}

func compare_runtime(baseline: Dictionary, candidate: Dictionary) -> Dictionary:
	var baseline_ok := bool(baseline.get("ok", false))
	var candidate_ok := bool(candidate.get("ok", false))
	var baseline_passed := int(baseline.get("passed", 0))
	var candidate_passed := int(candidate.get("passed", 0))
	var no_regression := baseline_ok and candidate_ok and candidate_passed >= baseline_passed
	return {
		"ok": no_regression,
		"baseline_ok": baseline_ok,
		"candidate_ok": candidate_ok,
		"baseline_passed": baseline_passed,
		"candidate_passed": candidate_passed,
		"no_regression": no_regression,
		"baseline": baseline,
		"candidate": candidate
	}

func _public_functions(source: String) -> Array[String]:
	var out: Array[String] = []
	for raw in source.split("\n"):
		var line := str(raw).strip_edges()
		if not line.begins_with("func "):
			continue
		var tail := line.trim_prefix("func ")
		var name := tail.get_slice("(", 0).strip_edges()
		if name.is_empty() or name.begins_with("_"):
			continue
		if name not in out:
			out.append(name)
	out.sort()
	return out

func _signals(source: String) -> Array[String]:
	var out: Array[String] = []
	for raw in source.split("\n"):
		var line := str(raw).strip_edges()
		if not line.begins_with("signal "):
			continue
		var tail := line.trim_prefix("signal ")
		var name := tail.get_slice("(", 0).strip_edges()
		if name.is_empty():
			name = tail.get_slice(" ", 0).strip_edges()
		if not name.is_empty() and name not in out:
			out.append(name)
	out.sort()
	return out
