class_name AuroraUpdateManager
extends Node

signal update_check_started
signal update_available(info: Dictionary)
signal no_update(version: String)
signal download_started(info: Dictionary)
signal update_ready(info: Dictionary, package_path: String)
signal update_error(message: String)
signal update_applying(info: Dictionary)
signal settings_changed(settings: Dictionary)

const SETTINGS_PATH := "user://aurora_update_settings.json"
const UPDATES_DIR := "user://updates"
const LOG_PATH := "user://logs/aurora_update.log"
const MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"
const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"
const PUBLIC_KEY_PATH := "res://update/release_public.pub"

const DEFAULT_SETTINGS := {
	"auto_check": true,
	"auto_download": true,
	"channel": "stable",
	"check_interval_hours": 6,
	"last_check_unix": 0.0
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var current_version := "0.0.0"
var latest_info: Dictionary = {}
var downloaded_path := ""
var checking := false
var downloading := false
var _timer := 0.0

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
	var hours := maxf(1.0, float(settings.get("check_interval_hours", 6)))
	if Time.get_unix_time_from_system() - last >= hours * 3600.0:
		check_for_updates(false)

func _initial_check() -> void:
	await get_tree().create_timer(2.0).timeout
	if bool(settings.get("auto_check", true)):
		check_for_updates(false)

func check_for_updates(manual := true) -> Dictionary:
	if checking:
		return {"ok": false, "error": "update check already running"}
	checking = true
	update_check_started.emit()
	_log("update check started version=%s manual=%s" % [current_version, manual])
	var req := HTTPRequest.new()
	req.timeout = 25.0
	add_child(req)
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: AuroraFox-Updater/%s" % current_version])
	var err := req.request(MANIFEST_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		checking = false
		req.queue_free()
		return _fail("Не удалось запустить проверку обновлений: %s" % error_string(err), manual)
	var result: Array = await req.request_completed
	req.queue_free()
	settings["last_check_unix"] = Time.get_unix_time_from_system()
	_save_settings()
	var code := int(result[1])
	if code == 404:
		checking = false
		_log("no published update manifest yet")
		if manual: no_update.emit(current_version)
		return {"ok": true, "available": false, "version": current_version}
	if code < 200 or code >= 300:
		checking = false
		return _fail("Сервер обновлений ответил кодом %d" % code, manual)

	var manifest_bytes: PackedByteArray = result[3]
	var signature_result := await _fetch_manifest_signature()
	if not signature_result.get("ok", false):
		checking = false
		return _fail(str(signature_result.get("error", "Подпись update.json недоступна")), manual)
	if not _verify_manifest_signature(manifest_bytes, signature_result.get("signature", PackedByteArray())):
		checking = false
		return _fail("Криптографическая подпись update.json недействительна. Обновление отклонено.", manual)
	_log("update manifest RSA-SHA256 signature verified")

	var raw := manifest_bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(raw)
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
		no_update.emit(current_version)
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
	if bool(settings.get("auto_download", true)):
		download_update()
	return {"ok": true, "available": true, "info": latest_info}

func download_update() -> Dictionary:
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
	if FileAccess.file_exists(relative): DirAccess.remove_absolute(absolute)
	downloading = true
	download_started.emit(latest_info)
	_log("download started url=%s" % url)
	var req := HTTPRequest.new()
	req.timeout = 1800.0
	req.download_file = absolute
	add_child(req)
	var headers := PackedStringArray(["User-Agent: AuroraFox-Updater/%s" % current_version])
	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		downloading = false
		req.queue_free()
		return _fail("Не удалось начать загрузку обновления: %s" % error_string(err), true)
	var result: Array = await req.request_completed
	req.queue_free()
	downloading = false
	var code := int(result[1])
	if code < 200 or code >= 300:
		DirAccess.remove_absolute(absolute)
		return _fail("Ошибка загрузки обновления: HTTP %d" % code, true)
	var actual := _sha256_file(absolute)
	if actual.is_empty() or actual != expected:
		DirAccess.remove_absolute(absolute)
		return _fail("SHA-256 обновления не совпал. Пакет удалён.", true)
	downloaded_path = absolute
	_log("download verified version=%s sha256=%s" % [version, actual])
	update_ready.emit(latest_info, downloaded_path)
	return {"ok": true, "path": downloaded_path, "sha256": actual}

func apply_downloaded_update() -> Dictionary:
	if latest_info.is_empty() or downloaded_path.is_empty() or not FileAccess.file_exists(downloaded_path):
		return {"ok": false, "error": "verified update package is missing"}
	update_applying.emit(latest_info)
	if OS.get_name() == "Windows":
		return _apply_windows_update()
	if OS.get_name() == "Android":
		return _apply_android_update()
	return _fail("Автообновление пока поддерживает Windows и Android", true)

func set_auto_check(value: bool) -> void:
	settings["auto_check"] = value
	_save_settings()

func set_auto_download(value: bool) -> void:
	settings["auto_download"] = value
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

func _fetch_manifest_signature() -> Dictionary:
	if not FileAccess.file_exists(PUBLIC_KEY_PATH):
		return {"ok": false, "error": "В этой сборке отсутствует публичный ключ обновлений AuroraFox"}
	var req := HTTPRequest.new()
	req.timeout = 25.0
	add_child(req)
	var headers := PackedStringArray(["Accept: application/octet-stream", "User-Agent: AuroraFox-Updater/%s" % current_version])
	var err := req.request(MANIFEST_SIG_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "Не удалось запросить подпись update.sig: %s" % error_string(err)}
	var result: Array = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	if code < 200 or code >= 300:
		return {"ok": false, "error": "Подпись update.sig недоступна: HTTP %d" % code}
	var signature: PackedByteArray = result[3]
	if signature.size() < 128:
		return {"ok": false, "error": "Файл update.sig слишком короткий"}
	return {"ok": true, "signature": signature}

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

func _apply_windows_update() -> Dictionary:
	if OS.has_feature("editor"):
		return _fail("Установка обновления отключена при запуске из редактора Godot", true)
	var helper_res := "res://update/windows_updater.ps1"
	var helper_user := UPDATES_DIR + "/windows_updater.ps1"
	if not _copy_text_resource(helper_res, helper_user):
		return _fail("Не удалось подготовить Windows updater", true)
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
	if pid <= 0: return _fail("Не удалось запустить updater helper", true)
	_log("windows updater launched pid=%d" % pid)
	get_tree().quit()
	return {"ok": true, "applying": true}

func _apply_android_update() -> Dictionary:
	if not Engine.has_singleton("AuroraFoxRuntime"):
		return _fail("Android updater plugin отсутствует в этой сборке", true)
	var plugin := Engine.get_singleton("AuroraFoxRuntime")
	if not plugin.has_method("installUpdateApk"):
		return _fail("Android runtime не поддерживает установку обновления", true)
	var raw = plugin.call("installUpdateApk", downloaded_path)
	var parsed = JSON.parse_string(str(raw))
	if parsed is Dictionary:
		if bool(parsed.get("ok", false)):
			_log("android package installer opened")
			return parsed
		if bool(parsed.get("requires_permission", false)):
			_log("android unknown-app-source permission requested")
			return parsed
		return _fail(str(parsed.get("error", "Не удалось открыть установщик Android")), true)
	return _fail("Некорректный ответ Android updater", true)

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
	if visible: update_error.emit(message)
	return {"ok": false, "error": message}

func _log(message: String) -> void:
	_ensure_dirs()
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null: return
	f.seek_end()
	f.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), message])
	f.close()
