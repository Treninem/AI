class_name AuroraApiSettingsOverlay
extends Node

signal personal_session_changed(state: Dictionary)
signal personal_memory_changed(items: Array)
signal personal_request_failed(message: String)

const PERSONAL_SESSION_PATH := "user://personal_session.json"
const DEFAULT_PUBLIC_API_URL := "https://api.aurorafox.ru"
const PERSONAL_REQUEST_TIMEOUT := 12.0

var manager: AuroraApiGatewayManager
var popup: PopupPanel
var status_label: Label
var url_label: Label
var enabled_toggle: CheckButton
var port_box: SpinBox
var key_name: LineEdit
var token_output: LineEdit
var keys_box: VBoxContainer

var _personal_session: Dictionary = {}
var _personal_memory_cache: Array = []
var _personal_busy := false
var _last_personal_error := ""

const BG := Color(0.025, 0.03, 0.05, 0.995)
const SURFACE := Color(0.055, 0.065, 0.10, 0.98)
const BORDER := Color(0.34, 0.39, 0.55, 0.55)
const ACCENT := Color("a98aff")
const GREEN := Color("64ff9d")
const WHITE := Color("f3f6ff")
const MUTED := Color("8d98ad")

func _ready() -> void:
	_load_personal_session()
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	await get_tree().process_frame
	manager = get_parent().get_node_or_null("ApiGatewayManager") as AuroraApiGatewayManager
	if OS.get_name() != "Android" and manager != null:
		_build_popup()
		_inject_settings_button()
		manager.status_changed.connect(_on_status_changed)
		manager.key_created.connect(_on_key_created)
		_refresh()
	personal_session_changed.emit(personal_state())
	if str(_personal_session.get("kind", "")) == "account" and _access_needs_refresh():
		call_deferred("_refresh_personal_session_background")

func _refresh_personal_session_background() -> void:
	await refresh_personal_session()

func personal_base_url() -> String:
	var configured := OS.get_environment("AURORAFOX_PUBLIC_URL").strip_edges()
	if configured.is_empty():
		configured = str(ProjectSettings.get_setting("aurorafox/api/public_url", DEFAULT_PUBLIC_API_URL)).strip_edges()
	if configured.is_empty():
		configured = DEFAULT_PUBLIC_API_URL
	while configured.ends_with("/"):
		configured = configured.left(configured.length() - 1)
	return configured

func personal_busy() -> bool:
	return _personal_busy

func personal_state() -> Dictionary:
	var kind := str(_personal_session.get("kind", ""))
	var account: Dictionary = {}
	var raw_account = _personal_session.get("account", {})
	if raw_account is Dictionary:
		account = raw_account.duplicate(true)
	return {
		"kind": kind,
		"signed_in": kind in ["account", "guest"],
		"account": account,
		"guest_id": str(_personal_session.get("guest_id", "")),
		"device_id": str(_personal_session.get("device_id", "")),
		"access_expires_at": int(_personal_session.get("access_expires_at", 0)),
		"refresh_expires_at": int(_personal_session.get("refresh_expires_at", 0)),
		"pending_guest_migration": not str(_personal_session.get("pending_guest_token", "")).is_empty(),
		"last_error": _last_personal_error,
		"memory_items": _personal_memory_cache.size(),
		"service": personal_base_url()
	}

func personal_memory_cache() -> Array:
	return _personal_memory_cache.duplicate(true)

func login_personal(email: String, password: String) -> Dictionary:
	if _personal_busy:
		return {"ok": false, "error": "Операция аккаунта уже выполняется"}
	var clean_email := email.strip_edges()
	if clean_email.is_empty() or password.is_empty():
		return {"ok": false, "error": "Укажи e-mail и пароль"}
	_personal_busy = true
	var previous_guest := ""
	if str(_personal_session.get("kind", "")) == "guest":
		previous_guest = str(_personal_session.get("guest_token", ""))
	elif not str(_personal_session.get("pending_guest_token", "")).is_empty():
		previous_guest = str(_personal_session.get("pending_guest_token", ""))
	var response := await _request_json(
		"/v1/auth/login",
		HTTPClient.METHOD_POST,
		{
			"email": clean_email,
			"password": password,
			"device_name": _device_name(),
			"platform": _platform_name()
		}
	)
	if not bool(response.get("ok", false)):
		_personal_busy = false
		return _personal_failure(response)
	var data: Dictionary = response.get("data", {})
	_personal_session = {
		"kind": "account",
		"account": data.get("account", {}),
		"access_token": str(data.get("access_token", "")),
		"access_expires_at": int(data.get("access_expires_at", 0)),
		"refresh_token": str(data.get("refresh_token", "")),
		"refresh_expires_at": int(data.get("refresh_expires_at", 0)),
		"session_id": str(data.get("session_id", "")),
		"device_id": str(data.get("device_id", ""))
	}
	if not previous_guest.is_empty():
		var migration := await _request_json(
			"/v1/account/migrate-guest",
			HTTPClient.METHOD_POST,
			{"guest_token": previous_guest},
			str(_personal_session.get("access_token", ""))
		)
		if not bool(migration.get("ok", false)):
			_personal_session["pending_guest_token"] = previous_guest
	_save_personal_session()
	_last_personal_error = ""
	_personal_busy = false
	personal_session_changed.emit(personal_state())
	return {"ok": true, "state": personal_state()}

func enter_guest() -> Dictionary:
	if _personal_busy:
		return {"ok": false, "error": "Операция аккаунта уже выполняется"}
	if str(_personal_session.get("kind", "")) == "account":
		return {"ok": false, "error": "Сначала выйди из аккаунта на этом устройстве"}
	if str(_personal_session.get("kind", "")) == "guest" and not str(_personal_session.get("guest_token", "")).is_empty():
		return {"ok": true, "state": personal_state()}
	_personal_busy = true
	var response := await _request_json(
		"/v1/auth/guest",
		HTTPClient.METHOD_POST,
		{"device_name": _device_name(), "platform": _platform_name()}
	)
	if not bool(response.get("ok", false)):
		_personal_busy = false
		return _personal_failure(response)
	var data: Dictionary = response.get("data", {})
	_personal_session = {
		"kind": "guest",
		"guest_token": str(data.get("guest_token", "")),
		"guest_id": str(data.get("guest_id", "")),
		"device_id": str(data.get("device_id", "")),
		"created_at": int(data.get("created_at", 0))
	}
	_save_personal_session()
	_last_personal_error = ""
	_personal_busy = false
	personal_session_changed.emit(personal_state())
	return {"ok": true, "state": personal_state()}

func refresh_personal_session() -> Dictionary:
	if str(_personal_session.get("kind", "")) != "account":
		return {"ok": false, "error": "Аккаунт не активен"}
	var refresh_token := str(_personal_session.get("refresh_token", ""))
	if refresh_token.is_empty():
		return {"ok": false, "error": "Сессия требует повторного входа"}
	var response := await _request_json(
		"/v1/auth/refresh",
		HTTPClient.METHOD_POST,
		{"refresh_token": refresh_token}
	)
	if not bool(response.get("ok", false)):
		if int(response.get("status", 0)) == 401:
			_clear_personal_session()
			personal_session_changed.emit(personal_state())
		return _personal_failure(response)
	var data: Dictionary = response.get("data", {})
	for key in ["access_token", "access_expires_at", "refresh_token", "refresh_expires_at", "session_id", "device_id"]:
		if data.has(key):
			_personal_session[key] = data[key]
	_save_personal_session()
	_last_personal_error = ""
	personal_session_changed.emit(personal_state())
	return {"ok": true, "state": personal_state()}

func retry_guest_migration() -> Dictionary:
	if str(_personal_session.get("kind", "")) != "account":
		return {"ok": false, "error": "Для переноса гостевых данных нужен вход в аккаунт"}
	var guest_token := str(_personal_session.get("pending_guest_token", ""))
	if guest_token.is_empty():
		return {"ok": true, "migrated": false}
	var bearer := await _ensure_personal_token()
	if bearer.is_empty():
		return {"ok": false, "error": _last_personal_error if not _last_personal_error.is_empty() else "Сессия недоступна"}
	var response := await _request_json(
		"/v1/account/migrate-guest",
		HTTPClient.METHOD_POST,
		{"guest_token": guest_token},
		bearer
	)
	if not bool(response.get("ok", false)):
		return _personal_failure(response)
	_personal_session.erase("pending_guest_token")
	_save_personal_session()
	personal_session_changed.emit(personal_state())
	return {"ok": true, "migrated": true, "data": response.get("data", {})}

func logout_personal() -> Dictionary:
	if _personal_busy:
		return {"ok": false, "error": "Операция аккаунта уже выполняется"}
	_personal_busy = true
	var kind := str(_personal_session.get("kind", ""))
	var remote_revoked := false
	var warning := ""
	if kind == "account":
		var device_id := str(_personal_session.get("device_id", ""))
		var bearer := await _ensure_personal_token()
		if not bearer.is_empty() and not device_id.is_empty():
			var response := await _request_json(
				"/v1/account/devices/" + device_id.uri_encode(),
				HTTPClient.METHOD_DELETE,
				{},
				bearer
			)
			remote_revoked = bool(response.get("ok", false)) and bool((response.get("data", {}) as Dictionary).get("revoked", false))
			if not remote_revoked:
				warning = "Серверную сессию не удалось отозвать; локальные токены удалены"
	elif kind == "guest":
		warning = "Гостевая сессия забыта на этом устройстве"
	_clear_personal_session()
	_personal_memory_cache.clear()
	_last_personal_error = warning
	_personal_busy = false
	personal_session_changed.emit(personal_state())
	personal_memory_changed.emit([])
	return {"ok": true, "remote_revoked": remote_revoked, "warning": warning}

func fetch_personal_memories() -> Dictionary:
	var bearer := await _ensure_personal_token()
	if bearer.is_empty():
		return {"ok": false, "error": _last_personal_error if not _last_personal_error.is_empty() else "Войди в аккаунт или продолжи как гость"}
	var cursor := 0
	var pages := 0
	var latest: Dictionary = {}
	while pages < 20:
		var response := await _request_json(
			"/v1/sync/pull?cursor=%d&limit=500" % cursor,
			HTTPClient.METHOD_GET,
			{},
			bearer
		)
		if not bool(response.get("ok", false)):
			return _personal_failure(response)
		var data: Dictionary = response.get("data", {})
		var changes: Array = data.get("changes", [])
		for raw in changes:
			if not raw is Dictionary:
				continue
			var item: Dictionary = raw
			if str(item.get("entity_type", "")) != "memory":
				continue
			var entity_id := str(item.get("entity_id", ""))
			if entity_id.is_empty():
				continue
			var previous = latest.get(entity_id, null)
			if previous == null or int(item.get("revision", 0)) >= int((previous as Dictionary).get("revision", 0)):
				latest[entity_id] = item.duplicate(true)
		cursor = int(data.get("cursor", cursor))
		pages += 1
		if not bool(data.get("has_more", false)):
			break
	var items: Array = []
	for entity_id in latest.keys():
		var item: Dictionary = latest[entity_id]
		if bool(item.get("deleted", false)):
			continue
		items.append(item)
	items.sort_custom(func(a, b): return int(a.get("updated_at", 0)) > int(b.get("updated_at", 0)))
	_personal_memory_cache = items.duplicate(true)
	_last_personal_error = ""
	personal_memory_changed.emit(personal_memory_cache())
	personal_session_changed.emit(personal_state())
	return {"ok": true, "items": personal_memory_cache()}

func delete_personal_memory(entity_id: String, revision: int, payload: Variant) -> Dictionary:
	if entity_id.strip_edges().is_empty() or revision < 0:
		return {"ok": false, "error": "Некорректная запись памяти"}
	var bearer := await _ensure_personal_token()
	if bearer.is_empty():
		return {"ok": false, "error": _last_personal_error if not _last_personal_error.is_empty() else "Сессия недоступна"}
	var response := await _request_json(
		"/v1/sync/push",
		HTTPClient.METHOD_POST,
		{
			"items": [{
				"entity_type": "memory",
				"entity_id": entity_id,
				"base_revision": revision,
				"payload": payload,
				"deleted": true
			}]
		},
		bearer
	)
	if not bool(response.get("ok", false)):
		return _personal_failure(response)
	var data: Dictionary = response.get("data", {})
	var results: Array = data.get("results", [])
	if results.is_empty() or not results[0] is Dictionary:
		return {"ok": false, "error": "Сервер не подтвердил удаление памяти"}
	var status := str((results[0] as Dictionary).get("status", ""))
	if status == "conflict":
		return {"ok": false, "conflict": true, "error": "Память изменилась на другом устройстве. Обнови список и повтори."}
	await fetch_personal_memories()
	return {"ok": true, "status": status}

func _ensure_personal_token() -> String:
	var kind := str(_personal_session.get("kind", ""))
	if kind == "guest":
		var guest_token := str(_personal_session.get("guest_token", ""))
		if guest_token.is_empty():
			_last_personal_error = "Гостевая сессия повреждена"
		return guest_token
	if kind != "account":
		_last_personal_error = "Личная сессия не активна"
		return ""
	if _access_needs_refresh():
		var refreshed := await refresh_personal_session()
		if not bool(refreshed.get("ok", false)):
			return ""
	var access_token := str(_personal_session.get("access_token", ""))
	if access_token.is_empty():
		_last_personal_error = "Сессия требует повторного входа"
	return access_token

func _access_needs_refresh() -> bool:
	if str(_personal_session.get("kind", "")) != "account":
		return false
	var expires_at := int(_personal_session.get("access_expires_at", 0))
	return expires_at <= int(Time.get_unix_time_from_system()) + 30 or str(_personal_session.get("access_token", "")).is_empty()

func _request_json(path: String, method: int, payload: Dictionary = {}, bearer := "") -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = PERSONAL_REQUEST_TIMEOUT
	add_child(request)
	var headers := PackedStringArray(["Accept: application/json"])
	var body := ""
	if method != HTTPClient.METHOD_GET and not payload.is_empty():
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	if not bearer.is_empty():
		headers.append("Authorization: Bearer " + bearer)
	var err := request.request(personal_base_url() + path, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "error": "Сервис аккаунта недоступен: " + error_string(err)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var transport := int(completed[0])
	var status := int(completed[1])
	var raw: PackedByteArray = completed[3]
	var text := raw.get_string_from_utf8().strip_edges()
	var parsed: Variant = null
	if not text.is_empty():
		parsed = JSON.parse_string(text)
	if transport != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": status, "error": "Сервис аккаунта временно недоступен"}
	if status >= 200 and status < 300 and parsed is Dictionary:
		return {"ok": true, "status": status, "data": parsed}
	return {"ok": false, "status": status, "error": _response_error(parsed, text)}

func _response_error(parsed: Variant, fallback: String) -> String:
	if parsed is Dictionary:
		var detail = (parsed as Dictionary).get("detail", "")
		if detail is String and not str(detail).strip_edges().is_empty():
			return str(detail)
		if detail is Dictionary:
			return JSON.stringify(detail)
		var error := str((parsed as Dictionary).get("error", "")).strip_edges()
		if not error.is_empty():
			return error
	return fallback.substr(0, 600) if not fallback.is_empty() else "Сервис аккаунта вернул ошибку"

func _personal_failure(response: Dictionary) -> Dictionary:
	_last_personal_error = str(response.get("error", "Неизвестная ошибка")).strip_edges()
	if _last_personal_error.is_empty():
		_last_personal_error = "Сервис аккаунта недоступен"
	personal_request_failed.emit(_last_personal_error)
	personal_session_changed.emit(personal_state())
	return {"ok": false, "status": int(response.get("status", 0)), "error": _last_personal_error}

func _platform_name() -> String:
	return "android" if OS.get_name() == "Android" else "windows" if OS.get_name() == "Windows" else OS.get_name().to_lower()

func _device_name() -> String:
	return "AuroraFox %s" % ("Android" if OS.get_name() == "Android" else "Windows" if OS.get_name() == "Windows" else OS.get_name())

func _load_personal_session() -> void:
	_personal_session = {}
	if not FileAccess.file_exists(PERSONAL_SESSION_PATH):
		return
	var file := FileAccess.open(PERSONAL_SESSION_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_personal_session = (parsed as Dictionary).duplicate(true)

func _save_personal_session() -> void:
	var file := FileAccess.open(PERSONAL_SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_personal_session))
	file.close()

func _clear_personal_session() -> void:
	_personal_session.clear()
	_save_personal_session()

func _style(fill: Color, border: Color = BORDER, radius := 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _button(text: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	var border := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.82) if accent else BORDER
	button.add_theme_stylebox_override("normal", _style(SURFACE, border, 11))
	button.add_theme_stylebox_override("hover", _style(Color(0.10, 0.11, 0.17, 1.0), border, 11))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.10, 0.22, 1.0), border, 11))
	button.add_theme_color_override("font_color", WHITE)
	return button

func _build_popup() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 112
	add_child(layer)
	popup = PopupPanel.new()
	popup.size = Vector2i(720, 680)
	popup.add_theme_stylebox_override("panel", _style(BG, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.62), 18))
	layer.add_child(popup)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	popup.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "API и интеграции"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", WHITE)
	root.add_child(title)

	var description := Label.new()
	description.text = "Подключай Telegram/VK-ботов, сайты и приложения к тому же AgentCore, памяти и инструментам AuroraFox. API-диалоги и feedback участвуют в обучении."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("cbd4e8"))
	root.add_child(description)

	enabled_toggle = CheckButton.new()
	enabled_toggle.text = "Запускать локальный API вместе с AuroraFox"
	enabled_toggle.button_pressed = manager.enabled
	enabled_toggle.toggled.connect(_on_enabled_toggled)
	root.add_child(enabled_toggle)

	var endpoint_row := HBoxContainer.new()
	endpoint_row.add_theme_constant_override("separation", 8)
	root.add_child(endpoint_row)
	var endpoint_title := Label.new()
	endpoint_title.text = "Адрес"
	endpoint_title.custom_minimum_size.x = 80
	endpoint_row.add_child(endpoint_title)
	url_label = Label.new()
	url_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_label.add_theme_color_override("font_color", GREEN)
	endpoint_row.add_child(url_label)
	port_box = SpinBox.new()
	port_box.min_value = 1024
	port_box.max_value = 65535
	port_box.step = 1
	port_box.value = manager.port
	port_box.custom_minimum_size.x = 120
	port_box.value_changed.connect(_on_port_changed)
	endpoint_row.add_child(port_box)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	var note := Label.new()
	note.text = "По умолчанию API слушает только 127.0.0.1. Для сайта/бота на другом сервере позже можно включить защищённый relay, не открывая порт ПК напрямую."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", MUTED)
	root.add_child(note)
	root.add_child(HSeparator.new())

	var key_title := Label.new()
	key_title.text = "API-ключи"
	key_title.add_theme_font_size_override("font_size", 19)
	root.add_child(key_title)

	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	root.add_child(create_row)
	key_name = LineEdit.new()
	key_name.placeholder_text = "Например: Telegram VoxLyra"
	key_name.text = "Моя интеграция"
	key_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(key_name)
	var create := _button("Создать ключ", true)
	create.pressed.connect(_create_key)
	create_row.add_child(create)

	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 8)
	root.add_child(token_row)
	token_output = LineEdit.new()
	token_output.placeholder_text = "Новый ключ появится здесь один раз"
	token_output.editable = false
	token_output.secret = true
	token_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token_row.add_child(token_output)
	var copy := _button("Копировать")
	copy.pressed.connect(_copy_token)
	token_row.add_child(copy)

	var scope_hint := Label.new()
	scope_hint.text = "Новый ключ получает: chat, models.read, conversations.read, files, tools.read, feedback, memory.read, memory.write. Запуск системных tools через API по умолчанию не выдаётся."
	scope_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope_hint.add_theme_font_size_override("font_size", 12)
	scope_hint.add_theme_color_override("font_color", MUTED)
	root.add_child(scope_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	keys_box = VBoxContainer.new()
	keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_box.add_theme_constant_override("separation", 6)
	scroll.add_child(keys_box)

	var close := _button("Закрыть")
	close.pressed.connect(_close_popup)
	root.add_child(close)

func _inject_settings_button() -> void:
	var settings := get_parent().get_node_or_null("SettingsOverlay")
	if settings == null:
		return
	var settings_popup = settings.get("popup")
	if not settings_popup is PopupPanel:
		return
	if settings_popup.find_child("SettingsPages", true, false) != null:
		return
	var box := _find_main_vbox(settings_popup)
	if box == null:
		return
	var separator := HSeparator.new()
	var label := Label.new()
	label.text = "API и интеграции"
	label.add_theme_font_size_override("font_size", 20)
	var button := _button("Открыть API и интеграции", true)
	button.pressed.connect(show_api_settings)
	box.add_child(separator)
	box.add_child(label)
	box.add_child(button)
	var close_index := -1
	for i in range(box.get_child_count()):
		var child := box.get_child(i)
		if child is Button and str(child.text) == "Закрыть":
			close_index = i
			break
	if close_index >= 0:
		box.move_child(separator, close_index)
		box.move_child(label, close_index + 1)
		box.move_child(button, close_index + 2)

func _find_main_vbox(node: Node) -> VBoxContainer:
	for child in node.get_children():
		if child is VBoxContainer and child.get_child_count() >= 5:
			return child
		var found: VBoxContainer = _find_main_vbox(child)
		if found != null:
			return found
	return null

func show_api_settings() -> void:
	if popup == null:
		return
	_refresh()
	popup.popup_centered()

func _refresh() -> void:
	if manager == null or popup == null:
		return
	enabled_toggle.button_pressed = manager.enabled
	port_box.value = manager.port
	url_label.text = manager.base_url()
	_on_status_changed(manager.online, manager.last_status)
	_refresh_keys()

func _on_status_changed(is_online: bool, details: Dictionary) -> void:
	if status_label == null:
		return
	if is_online:
		var core_state := "подключён" if bool(details.get("agent_online", false)) else "ожидает AuroraFox"
		status_label.text = "API: работает • AgentCore " + core_state
		status_label.add_theme_color_override("font_color", GREEN)
	else:
		status_label.text = "API: запускается / не отвечает"
		status_label.add_theme_color_override("font_color", Color("ffb36d"))

func _on_enabled_toggled(value: bool) -> void:
	if manager != null:
		manager.set_enabled(value)

func _on_port_changed(value: float) -> void:
	if manager == null:
		return
	manager.set_port(int(value))
	url_label.text = manager.base_url()

func _copy_token() -> void:
	if token_output != null and not token_output.text.is_empty():
		DisplayServer.clipboard_set(token_output.text)

func _close_popup() -> void:
	if popup != null:
		popup.hide()

func _create_key() -> void:
	if manager == null or key_name == null:
		return
	var name := key_name.text.strip_edges()
	if name.is_empty():
		name = "AuroraFox integration"
	var result := manager.create_key(name)
	if not result.get("ok", false) and status_label != null:
		status_label.text = "Не удалось создать ключ: " + str(result.get("error", "unknown"))
	_refresh_keys()

func _on_key_created(api_key: String, _info: Dictionary) -> void:
	if token_output == null:
		return
	token_output.text = api_key
	token_output.secret = false
	DisplayServer.clipboard_set(api_key)
	if status_label != null:
		status_label.text = "Ключ создан и скопирован. Сохрани его: повторно полный ключ не показывается."

func _revoke_key(key_id: String) -> void:
	if manager != null:
		manager.revoke_key(key_id)
	_refresh_keys()

func _refresh_keys() -> void:
	if keys_box == null or manager == null:
		return
	for child in keys_box.get_children():
		child.queue_free()
	var result := manager.list_keys()
	if not result.get("ok", false):
		var label := Label.new()
		label.text = "Ключи станут доступны после подготовки API runtime."
		label.add_theme_color_override("font_color", MUTED)
		keys_box.add_child(label)
		return
	var data: Dictionary = result.get("data", {})
	var rows: Array = data.get("keys", [])
	for item in rows:
		if not item is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		keys_box.add_child(row)
		var label := Label.new()
		label.text = "%s  •  %s" % [str(item.get("name", "Ключ")), ", ".join(PackedStringArray(item.get("scopes", [])))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		if not bool(item.get("revoked", false)):
			var revoke := _button("Отозвать")
			var key_id := str(item.get("id", ""))
			revoke.pressed.connect(_revoke_key.bind(key_id))
			row.add_child(revoke)
