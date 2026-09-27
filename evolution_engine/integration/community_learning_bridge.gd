class_name AuroraCommunityLearningBridge
extends Node

signal sync_completed(status: Dictionary)

const DEFAULT_INTERVAL_SECONDS := 60.0
const DEFAULT_BATCH_SIZE := 100
const MAX_BATCH_SIZE := 200
const CONTRACT := "aurorafox.impuls.community.v1"

var curator := AuroraCommunityLanguageCurator.new()
var _timer := Timer.new()
var _running := false
var _enabled := false
var _bound := false
var _api_url := ""
var _api_key := ""
var _last_status: Dictionary = {
	"ok": true,
	"enabled": false,
	"online": false,
	"last_pull_count": 0,
	"last_accepted": 0,
	"last_rejected": 0,
	"last_quarantined": 0,
	"last_error": "",
	"contract": CONTRACT
}

func _ready() -> void:
	_timer.one_shot = false
	_timer.wait_time = DEFAULT_INTERVAL_SECONDS
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_load_environment_config()

func bind(memory_value) -> void:
	curator.bind(memory_value)
	_bound = memory_value != null and memory_value.has_method("remember")
	if _enabled and _bound:
		_timer.start()
		call_deferred("sync_now")
	else:
		_timer.stop()

func configure(api_url: String, api_key: String, enabled := true, interval_seconds := DEFAULT_INTERVAL_SECONDS) -> Dictionary:
	_api_url = _normalize_base_url(api_url)
	_api_key = api_key.strip_edges()
	_enabled = enabled and not _api_url.is_empty() and not _api_key.is_empty()
	_timer.wait_time = clampf(interval_seconds, 30.0, 3600.0)
	if _enabled and _bound:
		_timer.start()
	else:
		_timer.stop()
	_last_status["enabled"] = _enabled
	return status()

func status() -> Dictionary:
	var out := _last_status.duplicate(true)
	out["enabled"] = _enabled
	out["bound"] = _bound
	out["configured"] = not _api_url.is_empty() and not _api_key.is_empty()
	out["api_host"] = _safe_host(_api_url)
	out["api_key_present"] = not _api_key.is_empty()
	out["running"] = _running
	out["retains_raw_chat"] = false
	out["stable_core_promotion"] = false
	out["weight_training"] = false
	return out

func sync_now() -> Dictionary:
	if not _enabled:
		return status()
	if not _bound:
		var unbound := status()
		unbound["ok"] = false
		unbound["stage"] = "foundation"
		unbound["error"] = "Local Memory is not bound; community events were not pulled"
		return unbound
	if _running:
		return {"ok": false, "stage": "busy", "error": "Community learning sync is already running"}
	_running = true
	var final_status := await _sync_once()
	_running = false
	_last_status = final_status.duplicate(true)
	sync_completed.emit(status())
	return status()

func _sync_once() -> Dictionary:
	var pulled := await _request_json(
		HTTPClient.METHOD_GET,
		"/v1/evolution/community/events/pull?limit=%d&lease_seconds=300" % DEFAULT_BATCH_SIZE
	)
	if not bool(pulled.get("ok", false)):
		return _failure(str(pulled.get("error", "Community pull failed")))

	var response = pulled.get("json", {})
	if not response is Dictionary or str(response.get("contract", "")) != CONTRACT:
		return _failure("Community pull contract mismatch")
	var events = response.get("events", [])
	if not events is Array:
		return _failure("Community pull returned invalid events")

	var ack_groups: Dictionary = {}
	var accepted := 0
	var rejected := 0
	var quarantined := 0
	for raw in events.slice(0, mini(events.size(), MAX_BATCH_SIZE)):
		if not raw is Dictionary:
			continue
		var decision := curator.curate(raw)
		var disposition := str(decision.get("disposition", "quarantined"))
		var reason := str(decision.get("reason", "invalid_schema"))
		var event_id := str(decision.get("event_id", ""))
		if event_id.is_empty():
			continue
		var group_key := disposition + ":" + reason
		if not ack_groups.has(group_key):
			ack_groups[group_key] = {
				"disposition": disposition,
				"reason": reason,
				"event_ids": []
			}
		ack_groups[group_key]["event_ids"].append(event_id)
		if disposition == "accepted":
			accepted += 1
		elif disposition == "rejected":
			rejected += 1
		else:
			quarantined += 1

	for key in ack_groups.keys():
		var group: Dictionary = ack_groups[key]
		var acked := await _request_json(HTTPClient.METHOD_POST, "/v1/evolution/community/events/ack", group)
		if not bool(acked.get("ok", false)):
			# Leave leases unacknowledged so the server can redeliver after timeout.
			return _failure("Community ACK failed; leased events will be retried")

	return {
		"ok": true,
		"enabled": true,
		"online": true,
		"last_pull_count": events.size(),
		"last_accepted": accepted,
		"last_rejected": rejected,
		"last_quarantined": quarantined,
		"last_error": "",
		"last_sync_at": Time.get_datetime_string_from_system(true),
		"contract": CONTRACT
	}

func _request_json(method: int, path: String, payload: Dictionary = {}) -> Dictionary:
	if _api_url.is_empty() or _api_key.is_empty():
		return {"ok": false, "error": "Community API is not configured"}
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	var headers := PackedStringArray([
		"Accept: application/json",
		"Authorization: Bearer " + _api_key,
		"X-AuroraFox-Contract: " + CONTRACT
	])
	var body := ""
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json; charset=utf-8")
		body = JSON.stringify(payload)
	var err := request.request(_api_url + path, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "HTTPRequest start failed: %s" % err}
	var completed: Array = await request.request_completed
	request.queue_free()
	if completed.size() < 4:
		return {"ok": false, "error": "HTTPRequest returned incomplete result"}
	var result_code := int(completed[0])
	var response_code := int(completed[1])
	var raw_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Community API transport failed: %s" % result_code}
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": "Community API HTTP %s" % response_code}
	var parsed = JSON.parse_string(raw_body.get_string_from_utf8())
	if not parsed is Dictionary:
		return {"ok": false, "error": "Community API returned invalid JSON"}
	return {"ok": true, "json": parsed}

func _load_environment_config() -> void:
	var url := OS.get_environment("AURORAFOX_COMMUNITY_API_URL")
	if url.is_empty():
		url = OS.get_environment("AURORAFOX_API_URL")
	var key := OS.get_environment("AURORAFOX_COMMUNITY_API_KEY")
	if key.is_empty():
		key = OS.get_environment("AURORAFOX_API_KEY")
	configure(url, key, not url.is_empty() and not key.is_empty(), DEFAULT_INTERVAL_SECONDS)

func _normalize_base_url(value: String) -> String:
	var clean := value.strip_edges().trim_suffix("/")
	if clean.is_empty():
		return ""
	# Remote community learning is never allowed over plaintext HTTP. Localhost
	# development may opt in explicitly through a loopback URL only.
	if clean.begins_with("https://"):
		return clean
	if clean.begins_with("http://127.0.0.1") or clean.begins_with("http://localhost"):
		return clean
	return ""

func _safe_host(value: String) -> String:
	var clean := value.replace("https://", "").replace("http://", "")
	return clean.split("/", false)[0] if not clean.is_empty() else ""

func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"enabled": _enabled,
		"online": false,
		"last_pull_count": 0,
		"last_accepted": 0,
		"last_rejected": 0,
		"last_quarantined": 0,
		"last_error": message.substr(0, 300),
		"last_sync_at": Time.get_datetime_string_from_system(true),
		"contract": CONTRACT
	}

func _on_timer() -> void:
	if _enabled and _bound and not _running:
		sync_now()
