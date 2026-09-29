class_name AuroraUpdateManager
extends Node

signal update_check_started
signal update_available(info: Dictionary)
signal no_update(version: String)
signal download_started(info: Dictionary)
signal update_ready(info: Dictionary, package_path: String)
signal update_error(message: String)
signal update_attempt_failed(message: String, background: bool)
signal update_applying(info: Dictionary)
signal settings_changed(settings: Dictionary)

const SETTINGS_PATH := "user://aurora_update_settings.json"
const UPDATES_DIR := "user://updates"
const LOG_PATH := "user://logs/aurora_update.log"
const MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"
const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"
const RELEASE_API_URL := "https://api.github.com/repos/Treninem/AI/releases/latest"
const RELEASE_ASSET_API_PREFIX := "https://api.github.com/repos/Treninem/AI/releases/assets/"
const RELEASE_PAGE_URL := "https://github.com/Treninem/AI/releases/latest"
const PUBLIC_KEY_PATH := "res://update/release_public.pub"
const PART_RETRY_MIN_SECONDS := 2.0
const PART_RETRY_MAX_SECONDS := 60.0
const PART_TIMEOUT_MIN_SECONDS := 120.0
const PART_TIMEOUT_MAX_SECONDS := 900.0
const PART_MAX_BYTES := 512 * 1024 * 1024

const DEFAULT_SETTINGS := {
	"auto_check": true,
	"auto_download": true,
	"auto_apply": true,
	"channel": "stable",
	"check_interval_hours": 1,
	"last_check_unix": 0.0
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var current_version := "0.0.0"
var latest_info: Dictionary = {}
var downloaded_path := ""
var checking := false
var downloading := false
var _timer := 0.0
var _next_retry_unix := 0.0

func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_load_settings()
	_ensure_dirs()
	_confirm_windows_update_health()
	set_process(true)
	call_deferred("_initial_check")

func _process(delta: float) -> void:
	if not bool(settings.get("auto_check", true)): return
	_timer += delta
	if _timer < 60.0: return
	_timer = 0.0
	var last := float(settings.get("last_check_unix", 0.0))
	var hours := maxf(1.0, float(settings.get("check_interval_hours", 1)))
	if Time.get_unix_time_from_system() >= _next_retry_unix and Time.get_unix_time_from_system() - last >= hours * 3600.0:
		check_for_updates(false)

func _initial_check() -> void:
	await get_tree().create_timer(2.0).timeout
	if bool(settings.get("auto_check", true)):
		await check_for_updates(false)

func check_for_updates(manual := true) -> Dictionary:
	if checking:
		return {"ok": false, "error": "update check already running"}
	checking = true
	if manual:
		update_check_started.emit()
	_log("update check started version=%s manual=%s" % [current_version, manual])
	var manifest_response := await _fetch_release_asset("update.json", MANIFEST_URL)
	var code := int(manifest_response.get("code", 0))
	if code == 404:
		checking = false
		settings["last_check_unix"] = Time.get_unix_time_from_system()
		_save_settings()
		_log("no published update manifest yet")
		if manual: no_update.emit(current_version)
		return {"ok": true, "available": false, "version": current_version}
	if not bool(manifest_response.get("ok", false)):
		checking = false
		_next_retry_unix = Time.get_unix_time_from_system() + 300.0
		return _fail("Не удалось проверить stable-обновление: %s" % str(manifest_response.get("error", "нет ответа")), manual)

	var manifest_bytes: PackedByteArray = manifest_response.get("body", PackedByteArray())
	var raw := manifest_bytes.get_string_from_utf8()
	var untrusted_parsed = JSON.parse_string(raw)
	if not FileAccess.file_exists(PUBLIC_KEY_PATH):
		checking = false
		var untrusted_remote := "0.0.0"
		if untrusted_parsed is Dictionary:
			untrusted_remote = str(untrusted_parsed.get("version", "0.0.0"))
		if _compare_versions(untrusted_remote, current_version) > 0:
			var repair_message := "Обнаружена более новая версия AuroraFox %s, но эта установка не содержит доверенный ключ обновлений. Автоматическая установка заблокирована безопасностью. Выполните одноразовый Repair/Bridge переход и затем обновления будут работать штатно." % untrusted_remote
			_log("repair required current=%s remote=%s release=%s" % [current_version, untrusted_remote, RELEASE_PAGE_URL])
			update_attempt_failed.emit(repair_message, not manual)
			if manual: update_error.emit(repair_message)
			return {
				"ok": false,
				"available": true,
				"repair_required": true,
				"version": untrusted_remote,
				"release_page": RELEASE_PAGE_URL,
				"error": repair_message,
				"background": not manual
			}
		return _fail("В этой сборке отсутствует публичный ключ обновлений AuroraFox", manual)

	var signature_result := await _fetch_manifest_signature()
	if not signature_result.get("ok", false):
		checking = false
		_next_retry_unix = Time.get_unix_time_from_system() + 300.0
		return _fail(str(signature_result.get("error", "Подпись update.json недоступна")), manual)
	if not _verify_manifest_signature(manifest_bytes, signature_result.get("signature", PackedByteArray())):
		checking = false
		return _fail("Криптографическая подпись update.json недействительна. Обновление отклонено.", manual)
	_log("update manifest RSA-SHA256 signature verified")
	settings["last_check_unix"] = Time.get_unix_time_from_system()
	_next_retry_unix = 0.0
	_save_settings()

	var parsed = untrusted_parsed
	checking = false
	if not parsed is Dictionary:
		return _fail("Некорректный update.json", manual)
	var info: Dictionary = parsed
	if str(info.get("channel", "stable")) != str(settings.get("channel", "stable")):
		if manual: no_update.emit(current_version)
		return {"ok": true, "available": false, "reason": "different_channel"}
	var remote := str(info.get("version", "0.0.0"))
	if _compare_versions(remote, current_version) <= 0:
		latest_info = info
		_log("no update current=%s remote=%s" % [current_version, remote])
		if manual: no_update.emit(current_version)
		return {"ok": true, "available": false, "version": remote}
	var asset := _platform_asset(info)
	if asset.is_empty():
		return _fail("Для этой платформы в релизе нет пакета обновления", manual)
	if str(asset.get("url", "")).is_empty() or str(asset.get("sha256", "")).length() != 64:
		return _fail("Релиз опубликован без корректного URL или SHA-256", manual)
	latest_info = info
	latest_info["selected_asset"] = asset
	_log("update available %s -> %s" % [current_version, remote])
	update_available.emit(latest_info)
	var response := {"ok": true, "available": true, "info": latest_info}
	if bool(settings.get("auto_download", true)):
		response["download"] = await download_update(manual)
	return response

func download_update(manual := true) -> Dictionary:
	if downloading:
		return {"ok": false, "error": "download already running"}
	if latest_info.is_empty():
		return {"ok": false, "error": "no update selected"}
	var asset: Dictionary = latest_info.get("selected_asset", _platform_asset(latest_info))
	if asset.is_empty(): return {"ok": false, "error": "no platform asset"}
	var url := str(asset.get("url", ""))
	var expected := str(asset.get("sha256", "")).to_lower()
	var ext := "apk" if OS.get_name() == "Android" else "zip"
	var version := str(latest_info.get("version", "update"))
	var relative := "%s/AuroraFox-%s.%s" % [UPDATES_DIR, version, ext]
	var absolute := ProjectSettings.globalize_path(relative)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	downloading = true
	if manual:
		download_started.emit(latest_info)
	_log("download started url=%s manual=%s size=%d" % [url, manual, int(asset.get("size", 0))])
	var parts = asset.get("parts", [])
	var transfer: Dictionary
	if parts is Array and not parts.is_empty():
		transfer = await _download_chunked_asset(asset, version, absolute)
	else:
		transfer = await _download_legacy_asset(url, int(asset.get("size", 0)), absolute)
	downloading = false
	if not bool(transfer.get("ok", false)):
		return _fail(str(transfer.get("error", "Не удалось загрузить обновление")), manual)
	var actual := _sha256_file(absolute)
	if actual.is_empty() or actual != expected:
		DirAccess.remove_absolute(absolute)
		return _fail("SHA-256 обновления не совпал. Собранный пакет удалён; проверенные части сохранены для повторной сборки.", manual)
	downloaded_path = absolute
	_log("download verified version=%s sha256=%s resumed_parts=%d" % [version, actual, int(transfer.get("resumed_parts", 0))])
	update_ready.emit(latest_info, downloaded_path)
	var response := {"ok": true, "path": downloaded_path, "sha256": actual, "verified": true, "resumed_parts": int(transfer.get("resumed_parts", 0))}
	if bool(settings.get("auto_apply", true)) and not OS.has_feature("editor"):
		_log("verified update is configured for automatic apply")
		response["apply"] = apply_downloaded_update(manual)
	return response

func _download_legacy_asset(url: String, size_bytes: int, absolute: String) -> Dictionary:
	# Compatibility path for already published signed manifests. V1.5+ releases
	# publish verified parts and use _download_chunked_asset instead.
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var req := HTTPRequest.new()
	# Large signed release packages can take longer than 30 minutes on slow links.
	# The signed manifest size sets a bounded transfer window; integrity is
	# still checked against the signed SHA-256 before the package is applied.
	var timeout_seconds := _package_timeout_seconds(size_bytes)
	req.timeout = timeout_seconds
	req.download_file = absolute
	add_child(req)
	var headers := PackedStringArray(["User-Agent: AuroraFox-Updater/%s" % current_version])
	_log("download transfer timeout_seconds=%.0f" % timeout_seconds)
	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "Не удалось начать загрузку обновления: %s" % error_string(err)}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	var transport := int(result[0])
	if transport != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		DirAccess.remove_absolute(absolute)
		return {"ok": false, "error": "Ошибка загрузки обновления: %s" % _request_failure(transport, code)}
	return {"ok": true, "resumed_parts": 0}

func _download_chunked_asset(asset: Dictionary, version: String, absolute: String) -> Dictionary:
	var validation := _validate_part_plan(asset)
	if not bool(validation.get("ok", false)):
		return validation
	var parts: Array = asset.get("parts", [])
	var part_dir := ProjectSettings.globalize_path("%s/%s.parts" % [UPDATES_DIR, _safe_component(version)])
	DirAccess.make_dir_recursive_absolute(part_dir)
	var resumed := 0
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var name := str(part.get("name", ""))
		var final_path := part_dir.path_join(name)
		var partial_path := final_path + ".partial"
		var expected_size := int(part.get("size", 0))
		var expected_sha := str(part.get("sha256", "")).to_lower()
		if _verified_file(final_path, expected_size, expected_sha):
			resumed += 1
			_log("update part resumed index=%d/%d name=%s" % [index + 1, parts.size(), name])
			continue
		if FileAccess.file_exists(final_path):
			DirAccess.remove_absolute(final_path)
		var retry_delay := PART_RETRY_MIN_SECONDS
		while true:
			_log("update part transfer index=%d/%d name=%s bytes=%d" % [index + 1, parts.size(), name, expected_size])
			var result := await _download_part_once(str(part.get("url", "")), expected_size, partial_path)
			if bool(result.get("ok", false)) and _verified_file(partial_path, expected_size, expected_sha):
				if FileAccess.file_exists(final_path):
					DirAccess.remove_absolute(final_path)
				var rename_error := DirAccess.rename_absolute(partial_path, final_path)
				if rename_error == OK:
					_log("update part verified index=%d/%d name=%s sha256=%s" % [index + 1, parts.size(), name, expected_sha])
					break
				result = {"ok": false, "error": "не удалось зафиксировать проверенную часть: %s" % error_string(rename_error)}
			# Keep a short partial file for the next HTTP Range request. A complete
			# but hash-invalid part cannot be trusted and is restarted from zero.
			if FileAccess.file_exists(partial_path):
				var partial := FileAccess.open(partial_path, FileAccess.READ)
				var partial_size := int(partial.get_length()) if partial != null else -1
				if partial != null:
					partial.close()
				if partial_size < 0 or partial_size >= expected_size:
					DirAccess.remove_absolute(partial_path)
			_log("update part retry index=%d/%d delay=%.0f error=%s" % [index + 1, parts.size(), retry_delay, str(result.get("error", "ошибка проверки"))])
			await get_tree().create_timer(retry_delay).timeout
			retry_delay = minf(PART_RETRY_MAX_SECONDS, retry_delay * 2.0)
	var assembled := _assemble_verified_parts(parts, part_dir, absolute)
	if not bool(assembled.get("ok", false)):
		return assembled
	return {"ok": true, "resumed_parts": resumed, "parts": parts.size()}

func _validate_part_plan(asset: Dictionary) -> Dictionary:
	var parts = asset.get("parts", [])
	if not parts is Array or parts.is_empty():
		return {"ok": false, "error": "Подписанный manifest не содержит частей обновления"}
	var total := 0
	var names := {}
	for raw in parts:
		if not raw is Dictionary:
			return {"ok": false, "error": "Некорректное описание части обновления"}
		var part: Dictionary = raw
		var name := str(part.get("name", ""))
		var url := str(part.get("url", ""))
		var sha := str(part.get("sha256", "")).to_lower()
		var size := int(part.get("size", 0))
		if name.is_empty() or name != name.get_file() or name.contains("..") or names.has(name):
			return {"ok": false, "error": "Небезопасное или повторяющееся имя части обновления"}
		if not url.begins_with("https://") or sha.length() != 64 or not sha.is_valid_hex_number() or size <= 0 or size > PART_MAX_BYTES:
			return {"ok": false, "error": "Некорректный URL, размер или SHA-256 части обновления"}
		names[name] = true
		total += size
	if total != int(asset.get("size", 0)):
		return {"ok": false, "error": "Суммарный размер частей не совпадает с подписанным размером пакета"}
	return {"ok": true, "parts": parts.size(), "size": total}

func _download_part_once(url: String, size_bytes: int, target: String) -> Dictionary:
	var offset := 0
	if FileAccess.file_exists(target):
		var existing := FileAccess.open(target, FileAccess.READ)
		if existing != null:
			offset = int(existing.get_length())
			existing.close()
	if offset < 0 or offset >= size_bytes:
		DirAccess.remove_absolute(target)
		offset = 0
	var req := HTTPRequest.new()
	req.timeout = _part_timeout_seconds(size_bytes)
	add_child(req)
	var headers := PackedStringArray(["User-Agent: AuroraFox-Updater/%s" % current_version])
	if offset > 0:
		headers.append("Range: bytes=%d-" % offset)
	var start_error := req.request(url, headers, HTTPClient.METHOD_GET)
	if start_error != OK:
		req.queue_free()
		return {"ok": false, "error": "запрос части не запущен: %s" % error_string(start_error)}
	var result: Array = await req.request_completed
	req.queue_free()
	var transport := int(result[0])
	var code := int(result[1])
	var response_headers: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]
	if code not in [200, 206]:
		return {"ok": false, "error": _request_failure(transport, code)}
	var append := offset > 0 and code == 206
	if append:
		var content_range := _header_value(response_headers, "content-range")
		if not content_range.to_lower().begins_with("bytes %d-" % offset):
			return {"ok": false, "error": "сервер вернул неверный Content-Range для продолжения части"}
	var mode := FileAccess.READ_WRITE if append else FileAccess.WRITE
	var file := FileAccess.open(target, mode)
	if file == null:
		return {"ok": false, "error": "не удалось сохранить байты части обновления"}
	if append:
		file.seek_end()
	file.store_buffer(body)
	file.close()
	if transport != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "%s; полученные байты сохранены для Range-продолжения" % _request_failure(transport, code)}
	return {"ok": true, "resumed_from": offset if append else 0, "bytes": body.size()}

func _header_value(headers: PackedStringArray, wanted: String) -> String:
	var prefix := wanted.to_lower() + ":"
	for raw in headers:
		var line := str(raw)
		if line.to_lower().begins_with(prefix):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""

func _part_timeout_seconds(size_bytes: int) -> float:
	# Timeout is per small part and detects lack of progress. There is no total
	# update deadline: failed parts retry after reconnection and verified parts stay.
	return clampf(float(maxi(0, size_bytes)) / 131072.0, PART_TIMEOUT_MIN_SECONDS, PART_TIMEOUT_MAX_SECONDS)

func _verified_file(path: String, expected_size: int, expected_sha: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var actual_size := file.get_length()
	file.close()
	return actual_size == expected_size and _sha256_file(path) == expected_sha

func _assemble_verified_parts(parts: Array, part_dir: String, absolute: String) -> Dictionary:
	var temporary := absolute + ".assembling"
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null:
		return {"ok": false, "error": "Не удалось создать собираемый пакет обновления"}
	for raw in parts:
		var part: Dictionary = raw
		var input := FileAccess.open(part_dir.path_join(str(part.get("name", ""))), FileAccess.READ)
		if input == null:
			output.close()
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "error": "Проверенная часть обновления исчезла перед сборкой"}
		while input.get_position() < input.get_length():
			output.store_buffer(input.get_buffer(mini(4 * 1024 * 1024, input.get_length() - input.get_position())))
		input.close()
	output.close()
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var rename_error := DirAccess.rename_absolute(temporary, absolute)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "Не удалось зафиксировать собранный пакет: %s" % error_string(rename_error)}
	return {"ok": true}

func _safe_component(value: String) -> String:
	var out := ""
	for character in value:
		var c := str(character)
		if c.is_valid_int() or c in [".", "-", "_"]:
			out += c
	return out if not out.is_empty() else "update"

func apply_downloaded_update(manual := true) -> Dictionary:
	if latest_info.is_empty() or downloaded_path.is_empty() or not FileAccess.file_exists(downloaded_path):
		return {"ok": false, "error": "verified update package is missing"}
	update_applying.emit(latest_info)
	if OS.get_name() == "Windows":
		return _apply_windows_update(manual)
	if OS.get_name() == "Android":
		return _apply_android_update(manual)
	return _fail("Автообновление пока поддерживает Windows и Android", manual)

func set_auto_check(value: bool) -> void:
	settings["auto_check"] = value
	_save_settings()

func set_auto_download(value: bool) -> void:
	settings["auto_download"] = value
	_save_settings()

func set_auto_apply(value: bool) -> void:
	settings["auto_apply"] = value
	_save_settings()

func set_check_interval_hours(value: int) -> void:
	settings["check_interval_hours"] = clampi(value, 1, 168)
	_save_settings()

func get_settings() -> Dictionary:
	return settings.duplicate(true)

func _platform_asset(info: Dictionary) -> Dictionary:
	var assets = info.get("assets", {})
	if not assets is Dictionary: return {}
	if OS.get_name() == "Windows": return assets.get("windows", {})
	if OS.get_name() == "Android": return assets.get("android", {})
	return {}

func _package_timeout_seconds(size_bytes: int) -> float:
	# The previous fixed 1800-second timeout cut off the 1.99 GB Windows ZIP
	# on the owner PC twice, exactly at 30 minutes. Allow at least an hour and
	# budget down to 256 KiB/s, capped at three hours for a stalled transfer.
	return clampf(float(maxi(0, size_bytes)) / 262144.0, 3600.0, 10800.0)

func _fetch_manifest_signature() -> Dictionary:
	if not FileAccess.file_exists(PUBLIC_KEY_PATH):
		return {"ok": false, "error": "В этой сборке отсутствует публичный ключ обновлений AuroraFox"}
	var response := await _fetch_release_asset("update.sig", MANIFEST_SIG_URL)
	if not bool(response.get("ok", false)):
		return {"ok": false, "error": "Подпись update.sig недоступна: %s" % str(response.get("error", "нет ответа"))}
	var signature: PackedByteArray = response.get("body", PackedByteArray())
	if signature.size() < 128:
		return {"ok": false, "error": "Файл update.sig слишком короткий"}
	return {"ok": true, "signature": signature}

func _fetch_release_asset(filename: String, direct_url: String) -> Dictionary:
	var direct := await _request_bytes(direct_url, "application/octet-stream")
	if bool(direct.get("ok", false)) or int(direct.get("code", 0)) == 404:
		return direct
	# A failed redirect/TLS/DNS request to github.com can still leave the
	# official GitHub API reachable. Asset bytes remain untrusted until RSA
	# signature verification (and the package SHA-256 gate).
	var release := await _request_bytes(RELEASE_API_URL, "application/vnd.github+json")
	if not bool(release.get("ok", false)):
		return {"ok": false, "error": "%s; GitHub API: %s" % [str(direct.get("error", "нет ответа")), str(release.get("error", "нет ответа"))]}
	var release_bytes: PackedByteArray = release.get("body", PackedByteArray())
	var metadata = JSON.parse_string(release_bytes.get_string_from_utf8())
	if not metadata is Dictionary or bool(metadata.get("draft", true)) or bool(metadata.get("prerelease", true)):
		return {"ok": false, "error": "GitHub API не вернул опубликованный stable-релиз"}
	var assets = metadata.get("assets", [])
	if not assets is Array:
		return {"ok": false, "error": "GitHub API не вернул список файлов релиза"}
	for asset in assets:
		if asset is Dictionary and str(asset.get("name", "")) == filename:
			var api_url := str(asset.get("url", ""))
			if not api_url.begins_with(RELEASE_ASSET_API_PREFIX):
				return {"ok": false, "error": "GitHub API вернул неожиданный адрес файла"}
			_log("stable asset fallback via GitHub API name=%s tag=%s" % [filename, str(metadata.get("tag_name", ""))])
			var fallback := await _request_bytes(api_url, "application/octet-stream")
			if bool(fallback.get("ok", false)):
				return fallback
			return {"ok": false, "error": "%s; GitHub API asset: %s" % [str(direct.get("error", "нет ответа")), str(fallback.get("error", "нет ответа"))]}
	return {"ok": false, "error": "В stable-релизе отсутствует %s" % filename}

func _request_bytes(url: String, accept: String) -> Dictionary:
	for attempt in range(2):
		var req := HTTPRequest.new()
		req.timeout = 25.0
		add_child(req)
		var headers := PackedStringArray(["Accept: " + accept, "User-Agent: AuroraFox-Updater/%s" % current_version])
		var start_error := req.request(url, headers, HTTPClient.METHOD_GET)
		if start_error != OK:
			req.queue_free()
			return {"ok": false, "error": "запрос не запущен: %s" % error_string(start_error), "code": 0}
		var result: Array = await req.request_completed
		req.queue_free()
		var transport := int(result[0])
		var code := int(result[1])
		_log("update HTTP url=%s result=%d status=%d attempt=%d" % [url, transport, code, attempt + 1])
		if transport == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
			return {"ok": true, "body": result[3], "code": code}
		var detail := _request_failure(transport, code)
		if attempt == 0 and (transport != HTTPRequest.RESULT_SUCCESS or code >= 500):
			await get_tree().create_timer(1.0).timeout
			continue
		return {"ok": false, "error": detail, "code": code, "result": transport}
	return {"ok": false, "error": "повторный запрос не завершился", "code": 0}

func _request_failure(result: int, code: int) -> String:
	if result == HTTPRequest.RESULT_SUCCESS:
		if code == 0: return "сервер не прислал HTTP-ответ"
		return "HTTP %d" % code
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE: return "не удалось определить адрес сервера (DNS), код Godot %d" % result
		HTTPRequest.RESULT_CANT_CONNECT: return "нет соединения с сервером, код Godot %d" % result
		HTTPRequest.RESULT_CONNECTION_ERROR: return "соединение прервано, код Godot %d" % result
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "ошибка защищённого соединения TLS, код Godot %d" % result
		HTTPRequest.RESULT_TIMEOUT: return "истекло время ожидания сети, код Godot %d" % result
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "слишком много перенаправлений, код Godot %d" % result
		_: return "сетевая ошибка Godot %d, HTTP %d" % [result, code]

func _verify_manifest_signature(payload: PackedByteArray, signature: PackedByteArray) -> bool:
	var key := CryptoKey.new()
	var key_error := key.load(PUBLIC_KEY_PATH, true)
	if key_error != OK or not key.is_public_only():
		_log("update public key failed to load: %s" % error_string(key_error))
		return false
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return false
	if ctx.update(payload) != OK: return false
	var digest := ctx.finish()
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest, signature, key)

func _apply_windows_update(visible_errors := true) -> Dictionary:
	if OS.has_feature("editor"):
		return _fail("Установка обновления отключена при запуске из редактора Godot", visible_errors)
	var helper_res := "res://update/windows_updater.ps1"
	var helper_user := UPDATES_DIR + "/windows_updater.ps1"
	if not _copy_text_resource(helper_res, helper_user):
		return _fail("Не удалось подготовить Windows updater", visible_errors)
	var install_dir := OS.get_executable_path().get_base_dir()
	var exe_name := OS.get_executable_path().get_file()
	var health := ProjectSettings.globalize_path(UPDATES_DIR + "/health-%s.ok" % str(latest_info.get("version", "next")))
	if FileAccess.file_exists(health): DirAccess.remove_absolute(health)
	var expected := str(latest_info.get("selected_asset", {}).get("sha256", ""))
	var args := PackedStringArray([
		"-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", ProjectSettings.globalize_path(helper_user),
		"-Package", downloaded_path,
		"-InstallDir", install_dir,
		"-ParentPid", str(OS.get_process_id()),
		"-ExeName", exe_name,
		"-ExpectedSha256", expected,
		"-HealthFile", health
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0: return _fail("Не удалось запустить updater helper", visible_errors)
	_log("windows updater launched pid=%d" % pid)
	get_tree().quit()
	return {"ok": true, "applying": true, "automatic": not visible_errors}

func _apply_android_update(visible_errors := true) -> Dictionary:
	if not Engine.has_singleton("AuroraFoxRuntime"):
		return _fail("Android updater plugin отсутствует в этой сборке", visible_errors)
	var plugin := Engine.get_singleton("AuroraFoxRuntime")
	if not plugin.has_method("installUpdateApk"):
		return _fail("Android runtime не поддерживает установку обновления", visible_errors)
	var raw = plugin.call("installUpdateApk", downloaded_path)
	var parsed = JSON.parse_string(str(raw))
	if parsed is Dictionary:
		parsed["automatic"] = not visible_errors
		if bool(parsed.get("ok", false)):
			_log("android package installer opened")
			return parsed
		if bool(parsed.get("requires_permission", false)):
			_log("android unknown-app-source permission requested")
			return parsed
		return _fail(str(parsed.get("error", "Не удалось открыть установщик Android")), visible_errors)
	return _fail("Некорректный ответ Android updater", visible_errors)

func _compare_versions(a: String, b: String) -> int:
	var aa := _version_parts(a)
	var bb := _version_parts(b)
	var count := maxi(aa.size(), bb.size())
	for i in range(count):
		var av := int(aa[i]) if i < aa.size() else 0
		var bv := int(bb[i]) if i < bb.size() else 0
		if av > bv: return 1
		if av < bv: return -1
	return 0

func _version_parts(value: String) -> Array:
	var clean := value.strip_edges().trim_prefix("v")
	clean = clean.split("-", false)[0]
	var out: Array = []
	for part in clean.split(".", false):
		var digits := ""
		for c in part:
			if str(c).is_valid_int(): digits += str(c)
			else: break
		out.append(int(digits) if not digits.is_empty() else 0)
	return out

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	while file.get_position() < file.get_length():
		ctx.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
	file.close()
	return ctx.finish().hex_encode().to_lower()

func _copy_text_resource(source: String, target: String) -> bool:
	var src := FileAccess.open(source, FileAccess.READ)
	if src == null: return false
	var text := src.get_as_text()
	src.close()
	var target_abs := ProjectSettings.globalize_path(target)
	DirAccess.make_dir_recursive_absolute(target_abs.get_base_dir())
	var dst := FileAccess.open(target, FileAccess.WRITE)
	if dst == null: return false
	dst.store_string(text)
	dst.close()
	return true

func _confirm_windows_update_health() -> void:
	if OS.get_name() != "Windows": return
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--aurora-update-health":
			var health := str(args[i + 1])
			var f := FileAccess.open(health, FileAccess.WRITE)
			if f != null:
				f.store_string("ok %s %s" % [current_version, Time.get_datetime_string_from_system()])
				f.close()
				_log("post-update health marker written")
			return

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATES_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))

func _load_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for key in DEFAULT_SETTINGS.keys():
			if parsed.has(key): settings[key] = parsed[key]

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings, "  "))
		f.close()
	settings_changed.emit(settings.duplicate(true))

func _fail(message: String, visible: bool) -> Dictionary:
	_log("ERROR " + message)
	update_attempt_failed.emit(message, not visible)
	if visible: update_error.emit(message)
	return {"ok": false, "error": message, "background": not visible}

func _log(message: String) -> void:
	_ensure_dirs()
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null: return
	f.seek_end()
	f.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), message])
	f.close()
