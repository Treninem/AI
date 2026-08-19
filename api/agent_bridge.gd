class_name AuroraApiAgentBridge
extends Node

signal bridge_started(port: int)
signal bridge_stopped
signal bridge_error(message: String)

@export var enabled := true
@export_range(1024, 65535, 1) var port := 8770
@export_range(1, 128, 1) var max_clients := 32

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _started := false

func _ready() -> void:
	if OS.get_name() == "Android":
		return
	if enabled:
		_start()

func _exit_tree() -> void:
	_stop()

func _process(_delta: float) -> void:
	if not _started:
		return
	while _server.is_connection_available() and _clients.size() < max_clients:
		var peer := _server.take_connection()
		if peer != null:
			_clients.append({"peer": peer, "buffer": PackedByteArray()})

	var finished: Array[int] = []
	for i in range(_clients.size()):
		var item: Dictionary = _clients[i]
		var peer: StreamPeerTCP = item.get("peer")
		if peer == null:
			finished.append(i)
			continue
		peer.poll()
		var status := peer.get_status()
		if status in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
			finished.append(i)
			continue
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var read := peer.get_data(available)
		if int(read[0]) != OK:
			finished.append(i)
			continue
		var buffer: PackedByteArray = item.get("buffer", PackedByteArray())
		buffer.append_array(read[1])
		item["buffer"] = buffer
		_clients[i] = item
		if buffer.size() > 8 * 1024 * 1024:
			_send_error(peer, "request too large", "")
			finished.append(i)
			continue
		var newline := buffer.find(10)
		if newline >= 0:
			var line := buffer.slice(0, newline).get_string_from_utf8()
			finished.append(i)
			_handle_peer_request(peer, line)

	finished.sort()
	finished.reverse()
	for index in finished:
		if index >= 0 and index < _clients.size():
			_clients.remove_at(index)

func _start() -> void:
	if _started:
		return
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		bridge_error.emit("API bridge listen failed on 127.0.0.1:%d: %s" % [port, error_string(err)])
		return
	_started = true
	set_process(true)
	bridge_started.emit(port)

func _stop() -> void:
	if not _started:
		return
	for item in _clients:
		var peer: StreamPeerTCP = item.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()
	_server.stop()
	_started = false
	bridge_stopped.emit()

func _handle_peer_request(peer: StreamPeerTCP, line: String) -> void:
	var parsed = JSON.parse_string(line)
	if not parsed is Dictionary:
		_send_error(peer, "invalid JSON request", "")
		return
	var request: Dictionary = parsed
	var request_id := str(request.get("request_id", ""))
	var op := str(request.get("op", ""))
	var payload: Dictionary = request.get("payload", {})
	var result: Dictionary = await _dispatch(op, payload)
	result["request_id"] = request_id
	_send(peer, result)

func _dispatch(op: String, payload: Dictionary) -> Dictionary:
	var main := get_parent()
	if main == null:
		return {"ok": false, "error": "Main node unavailable"}
	var agent = main.get("agent")
	var memory = main.get("memory")
	var tools = main.get("tools")
	if not agent is AgentCore or not memory is MemoryStore or not tools is ToolRegistry:
		return {"ok": false, "error": "AuroraFox core is not initialized"}

	match op:
		"status":
			return {
				"ok": true,
				"runtime": "godot-agent-core",
				"version": str(ProjectSettings.get_setting("application/config/version", "1.0.0.0")),
				"tools": tools.tools.size(),
				"semantic_memory": memory.semantic_status(),
				"bridge_port": port
			}
		"tools":
			return {"ok": true, "tools": tools.describe_tools()}
		"tool":
			var name := str(payload.get("name", ""))
			var args: Dictionary = payload.get("args", {})
			var tool_result = await tools.call_tool(name, args)
			return {"ok": not (tool_result is Dictionary and not bool(tool_result.get("ok", true))), "result": tool_result}
		"chat":
			var message := str(payload.get("message", "")).strip_edges()
			if message.is_empty():
				return {"ok": false, "error": "empty message"}
			var context: Array = payload.get("context", [])
			var metadata: Dictionary = payload.get("metadata", {})
			var conversation_id := str(payload.get("conversation_id", ""))
			var source := str(metadata.get("source", "api"))
			memory.remember(
				"api_request",
				JSON.stringify({"conversation_id": conversation_id, "message": message, "metadata": metadata}),
				"api:" + source,
				0.64,
				0.92
			)
			var answer: String = await agent.run_task(message, context)
			memory.remember(
				"api_response",
				JSON.stringify({"conversation_id": conversation_id, "answer": answer}),
				"api:" + source,
				0.54,
				0.82
			)
			return {"ok": true, "content": answer, "model": "aurorafox-agent", "runtime": "godot-agent-core"}
		"learn":
			return _learn_from_api(memory, payload)
		"feedback":
			return _feedback_from_api(agent, memory, payload)
		_:
			return {"ok": false, "error": "unknown bridge operation: " + op}

func _learn_from_api(memory: MemoryStore, payload: Dictionary) -> Dictionary:
	var content := str(payload.get("content", "")).strip_edges()
	if content.is_empty():
		return {"ok": false, "error": "empty learning content"}
	var source := "api:" + str(payload.get("source", "external"))
	memory.learn(
		content,
		source,
		clampf(float(payload.get("importance", 0.65)), 0.0, 1.0),
		clampf(float(payload.get("confidence", 0.80)), 0.0, 1.0),
		str(payload.get("kind", "external_knowledge"))
	)
	return {"ok": true, "learned": true, "source": source}

func _feedback_from_api(agent: AgentCore, memory: MemoryStore, payload: Dictionary) -> Dictionary:
	var source := "api:" + str(payload.get("source", "external"))
	var score := clampf(float(payload.get("score", 0.0)), -1.0, 1.0)
	var message := str(payload.get("message", ""))
	var answer := str(payload.get("answer", ""))
	var corrected := str(payload.get("corrected_answer", "")).strip_edges()
	var note := str(payload.get("note", ""))
	var conversation_id := str(payload.get("conversation_id", ""))
	var snapshot := {
		"conversation_id": conversation_id,
		"message": message,
		"answer": answer,
		"score": score,
		"note": note,
		"metadata": payload.get("metadata", {})
	}
	memory.remember("api_feedback", JSON.stringify(snapshot), source, 0.82, 0.92)
	if score < -0.15:
		agent.experience.record_failure(
		message if not message.is_empty() else "API conversation " + conversation_id,
		"External API feedback %.2f: %s" % [score, note if not note.is_empty() else answer.substr(0, 1000)]
		)
	if score > 0.20:
		memory.learn(
			JSON.stringify({"request": message, "successful_answer": answer, "feedback": note}),
			source,
			0.78,
			minf(0.98, 0.72 + score * 0.24),
			"successful_api_interaction"
		)
	if not corrected.is_empty():
		memory.learn(
			JSON.stringify({"request": message, "corrected_answer": corrected, "feedback": note}),
			source,
			0.94,
			0.96,
			"corrected_api_answer"
		)
	return {"ok": true, "feedback_recorded": true, "score": score, "corrected": not corrected.is_empty()}

func _send(peer: StreamPeerTCP, payload: Dictionary) -> void:
	var raw := (JSON.stringify(payload) + "\n").to_utf8_buffer()
	peer.put_data(raw)
	peer.disconnect_from_host()

func _send_error(peer: StreamPeerTCP, message: String, request_id: String) -> void:
	_send(peer, {"ok": false, "error": message, "request_id": request_id})
