extends SceneTree

func _fail(message: String, code: int) -> void:
	push_error(message)
	quit(code)

func _body(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var client := ComputerClient.new()
	root.add_child(client)

	var transport := client._decode_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	if str(transport.get("error", "")) != "transport_failure" or not bool(transport.get("retryable", false)):
		_fail("Transport failure contract regressed", 2)
		return

	var plain_404 := client._decode_response(HTTPRequest.RESULT_SUCCESS, 404, _body("<html>missing</html>"))
	if str(plain_404.get("error", "")) != "http_error" or int(plain_404.get("http", 0)) != 404 or bool(plain_404.get("retryable", true)):
		_fail("Plain-text 404 was not classified before JSON parsing", 3)
		return
	if "missing" not in str(plain_404.get("message", "")):
		_fail("Plain-text HTTP error detail was discarded", 4)
		return

	var plain_503 := client._decode_response(HTTPRequest.RESULT_SUCCESS, 503, _body("temporarily unavailable"))
	if str(plain_503.get("error", "")) != "http_error" or not bool(plain_503.get("retryable", false)):
		_fail("Retryable plain-text 503 contract regressed", 5)
		return

	var json_429_body := JSON.stringify({"error": "rate_limited", "detail": "slow down"})
	var json_429 := client._decode_response(HTTPRequest.RESULT_SUCCESS, 429, _body(json_429_body))
	if str(json_429.get("error", "")) != "rate_limited" or str(json_429.get("message", "")) != "slow down" or not bool(json_429.get("retryable", false)):
		_fail("Structured HTTP error detail contract regressed", 6)
		return

	var empty_204 := client._decode_response(HTTPRequest.RESULT_SUCCESS, 204, PackedByteArray())
	if str(empty_204.get("error", "")) != "empty_response" or int(empty_204.get("http", 0)) != 204 or bool(empty_204.get("retryable", true)):
		_fail("Empty success-body handling regressed", 7)
		return

	var empty_503 := client._decode_response(HTTPRequest.RESULT_SUCCESS, 503, PackedByteArray())
	if str(empty_503.get("error", "")) != "http_error" or int(empty_503.get("http", 0)) != 503 or not bool(empty_503.get("retryable", false)):
		_fail("Empty HTTP error body was misclassified", 8)
		return

	var malformed_200 := client._decode_response(HTTPRequest.RESULT_SUCCESS, 200, _body("not-json"))
	if str(malformed_200.get("error", "")) != "malformed_response" or bool(malformed_200.get("retryable", true)):
		_fail("Malformed 2xx JSON contract regressed", 9)
		return

	var ok_body := JSON.stringify({"ok": true, "marker": "decoded"})
	var ok_response := client._decode_response(HTTPRequest.RESULT_SUCCESS, 200, _body(ok_body))
	if not bool(ok_response.get("ok", false)) or str(ok_response.get("marker", "")) != "decoded":
		_fail("Valid JSON response no longer passes through", 10)
		return

	client.queue_free()
	print("AURORA_COMPUTER_RESPONSE_SMOKE_OK transport=closed http_non_json=classified http_json=classified empty=bounded malformed_2xx=closed")
	quit(0)
