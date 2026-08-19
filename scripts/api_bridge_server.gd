class_name AuroraApiBridgeServer
extends Node

const DEFAULT_PORT := 8770
const MAX_REQUEST_BYTES := 8 * 1024 * 1024

@export var enabled := true
@export_range(1024, 65535, 1) var port := DEFAULT_PORT

var server := TCPServer.new()
var clients: Array = []
var main: Node
var agent: AgentCore
var memory: MemoryStore
var tools: ToolRegistry
var ai: AIClient

func _ready() -> void:
	if not enabled or OS.get_name() == "Android":
		return
	main = get_parent()
	_bind_core()
	var error := server.listen(port, "127.0.0.1")
	if error != OK:
		push_warning("AuroraFox API bridge failed to listen on 127.0.0.1:%d: %s" % [port, error_string(error)])
		return
	set_process(true)

func _exit_tree() -> void:
	if server.is_listening():
		server.stop()
	clients.clear()

func _bind_core() -> void:
	if main == null:
		return
	var value = main.get("agent")
	if value is AgentCore:
		agent = value
	value = main.get("memory")
	if value is MemoryStore:
		memory = value
	value = main.get("tools")
	if value is ToolRegistry:
		tools = value
	value = main.get("ai")
	if value is AIClient:
		ai = value

func _process(_delta: float) -> void:
	if not server.is_listening():
		return
	while server.is_connection_available():
		var peer := server.take_connection()
		if peer != null:
			clients.append({"peer": peer, "buffer": "", "busy": false})

	for index in range(clients.size() - 1, -1, -1):
		var client: Dictionary = clients[index]
		var peer = client.get("peer")
		if not peer is StreamPeerTCP or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.remove_at(index)
			continue
		if bool(client.get("busy", false)):
			continue
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var chunk := peer.get_utf8_string(available)
		var buffer := str(client.get("buffer", "")) + chunk
		if buffer.to_utf8_buffer().size() > MAX_REQUEST_BYTES:
			_send(peer, {"ok": false, "error": "API bridge request is too large"})
			peer.disconnect_from_host()
			clients.remove_at(index)
			continue
		var newline := buffer.find("\n")
		if newline < 0:
			client["buffer"] = buffer
			continue
		var line := buffer.substr(0, newline).strip_edges()
		client["buffer"] = buffer.substr(newline + 1)
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not parsed is Dictionary:
			_send(peer, {"ok": false, "error": "Invalid JSON request"})
			continue
		client["busy"] = true
		call_deferred("_dispatch_request", peer, parsed, client)

func _dispatch_request(peer: StreamPeerTCP, request: Dictionary, client: Dictionary) -> void:
	_bind_core()
	var request_id := str(request.get("request_id", ""))
	var op := str(request.get("op", ""))
	var payload: Dictionary = request.get("payload", {}) if request.get("payload", {}) is Dictionary else {}
	var result: Dictionary

	match op:
		"status":
			result = _status()
		"chat":
			result = await _chat(payload)
		"tools":
			result = _tools()
		"tool":
			result = await _tool(payload)
		"learn":
			result = _learn(payload)
		"feedback":
			result = _feedback(payload)
		_:
			result = {"ok": false, "error": "Unknown API bridge operation: " + op}

	result["request_id"] = request_id
	_send(peer, result)
	client["busy"] = false

func _status() -> Dictionary:
	return {
		"ok": agent != null and memory != null and tools != null and ai != null,
		"service": "AuroraFox AgentCore bridge",
		"version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"model": ai.model if ai != null else "",
		"tools": tools.tools.size() if tools != null else 0,
		"memory": memory.semantic_status() if memory != null else {},
	}

func _chat(payload: Dictionary) -> Dictionary:
	if agent == null or memory == null:
		return {"ok": false, "error": "AgentCore is not ready"}
	var message := str(payload.get("message", "")).strip_edges()
	if message.is_empty():
		return {"ok": false, "error": "Empty chat message"}
	var context: Array = payload.get("context", []) if payload.get("context", []) is Array else []
	var metadata: Dictionary = payload.get("metadata", {}) if payload.get("metadata", {}) is Dictionary else {}
	var conversation_id := str(payload.get("conversation_id", ""))
	var source := str(metadata.get("source", "api")).strip_edges()
	if source.is_empty():
		source = "api"
	memory.remember(
		"api_request_context",
		JSON.stringify({"conversation_id": conversation_id, "source": source, "metadata": _compact(metadata)}),
		"api:" + source,
		0.42,
		0.92
	)
	var answer := await agent.run_task(message, context)
	return {
		"ok": true,
		"content": answer,
		"model": ai.model if ai != null else "agent",
		"details": {"conversation_id": conversation_id, "source": source},
	}

func _tools() -> Dictionary:
	if tools == null:
		return {"ok": false, "error": "ToolRegistry is not ready"}
	return {"ok": true, "tools": tools.describe_tools()}

func _tool(payload: Dictionary) -> Dictionary:
	if tools == null:
		return {"ok": false, "error": "ToolRegistry is not ready"}
	var name := str(payload.get("name", ""))
	var args: Dictionary = payload.get("args", {}) if payload.get("args", {}) is Dictionary else {}
	if name.is_empty():
		return {"ok": false, "error": "Tool name is required"}
	var result = await tools.call_tool(name, args)
	return {"ok": true, "name": name, "result": _compact(result)}

func _learn(event: Dictionary) -> Dictionary:
	if memory == null or agent == null:
		return {"ok": false, "error": "Learning subsystem is not ready"}
	var kind := str(event.get("kind", "api_event"))
	var payload: Dictionary = event.get("payload", {}) if event.get("payload", {}) is Dictionary else {}
	var source := str(payload.get("source", "external_api"))
	match kind:
		"interaction":
			var user_text := str(payload.get("user", "")).strip_edges()
			var assistant_text := str(payload.get("assistant", "")).strip_edges()
			var content := JSON.stringify({
				"source": source,
				"conversation_id": payload.get("conversation_id", ""),
				"user": user_text.substr(0, 16000),
				"assistant": assistant_text.substr(0, 20000),
				"runtime": payload.get("runtime", ""),
				"model": payload.get("model", ""),
			})
			memory.remember("api_interaction", content, "api:" + source, 0.58, 0.84)
		"file_analysis":
			memory.learn(
				str(payload.get("content", "")).substr(0, 30000),
				"api-file:" + source,
				0.68,
				0.78,
				"api_file_knowledge"
			)
		"error":
			var task := str(payload.get("task", "API request"))
			var error_text := str(payload.get("error", "unknown API error"))
			agent.experience.record_failure(task, "API/%s: %s" % [source, error_text])
			memory.remember("api_error", JSON.stringify(_compact(payload)), "api:" + source, 0.72, 0.95)
		"feedback":
			return _feedback(payload)
		_:
			memory.remember("api_event", JSON.stringify(_compact(payload)), "api:" + source, 0.44, 0.76)
	return {"ok": true, "learned": true, "kind": kind}

func _feedback(payload: Dictionary) -> Dictionary:
	if memory == null or agent == null:
		return {"ok": false, "error": "Learning subsystem is not ready"}
	var score := clampf(float(payload.get("score", 0.0)), -1.0, 1.0)
	var source := str(payload.get("source", "external_api"))
	var prompt := str(payload.get("prompt", "")).strip_edges()
	var answer := str(payload.get("answer", "")).strip_edges()
	var comment := str(payload.get("comment", "")).strip_edges()
	var corrected := str(payload.get("corrected_answer", "")).strip_edges()
	var feedback := {
		"score": score,
		"source": source,
		"conversation_id": payload.get("conversation_id", ""),
		"prompt": prompt.substr(0, 16000),
		"answer": answer.substr(0, 20000),
		"comment": comment.substr(0, 8000),
		"corrected_answer": corrected.substr(0, 20000),
	}
	memory.remember(
		"api_feedback_positive" if score > 0.0 else "api_feedback_negative" if score < 0.0 else "api_feedback_neutral",
		JSON.stringify(feedback),
		"api-feedback:" + source,
		0.88 if absf(score) >= 0.8 else 0.72,
		0.96
	)
	if score < 0.0:
		agent.experience.record_failure(prompt if not prompt.is_empty() else "API response", comment if not comment.is_empty() else "External API negative feedback")
	if not corrected.is_empty():
		memory.learn(
			JSON.stringify({"prompt": prompt, "preferred_answer": corrected, "source": source}),
			"api-correction:" + source,
			0.96,
			0.98,
			"corrected_response"
		)
	return {"ok": true, "learned": true, "score": score, "correction_saved": not corrected.is_empty()}

func _compact(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = value.duplicate(true)
		for key in out.keys():
			var text := str(out[key])
			if text.length() > 30000:
				out[key] = text.substr(0, 30000) + "…"
		return out
	if value is Array:
		var arr: Array = value
		return arr.slice(0, mini(arr.size(), 100))
	return str(value).substr(0, 30000)

func _send(peer: StreamPeerTCP, payload: Dictionary) -> void:
	if peer == null or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	peer.put_data((JSON.stringify(payload) + "\n").to_utf8_buffer())
