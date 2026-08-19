class_name AuroraReleaseStatusOverlay
extends CanvasLayer

const VERSION_PATH := "res://project/version.json"
const PROGRESS_PATH := "res://agent/state/progress.json"

var version_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var _coordinator: AuroraAutonomousCoordinator

func _ready() -> void:
	layer = 120
	_build_ui()
	_refresh_version()
	_refresh_progress_from_file()
	call_deferred("_bind_coordinator")

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "AuroraReleaseStatus"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-320, -94)
	panel.size = Vector2(300, 76)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	version_label = Label.new()
	version_label.text = "🦊 V0.0.0.0"
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.add_theme_font_size_override("font_size", 15)
	box.add_child(version_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(270, 12)
	box.add_child(progress_bar)

	progress_label = Label.new()
	progress_label.text = "Эволюция: синхронизация…"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_label.add_theme_font_size_override("font_size", 12)
	box.add_child(progress_label)

func _bind_coordinator() -> void:
	var main := get_parent()
	if main == null:
		return
	var node := main.get_node_or_null("AutonomousCoordinator")
	if node is AuroraAutonomousCoordinator:
		_coordinator = node
		if not _coordinator.synchronization_completed.is_connected(_on_sync):
			_coordinator.synchronization_completed.connect(_on_sync)
		var report := await _coordinator.synchronize_all()
		_on_sync(report)

func _refresh_version() -> void:
	if not FileAccess.file_exists(VERSION_PATH):
		version_label.text = "🦊 V" + str(ProjectSettings.get_setting("application/config/version", "0.0.0.0"))
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(VERSION_PATH))
	if data is Dictionary:
		version_label.text = "🦊 " + str(data.get("version", "V0.0.0.0"))

func _refresh_progress_from_file() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH))
	if not data is Dictionary:
		return
	var percent := clampi(int(data.get("percent", 0)), 0, 100)
	progress_bar.value = percent
	progress_label.text = "%d%% • %s" % [percent, str(data.get("state", "эволюция"))]

func _on_sync(report: Dictionary) -> void:
	var components: Dictionary = report.get("components", {})
	var required := components.size()
	var ready := 0
	for value in components.values():
		if bool(value):
			ready += 1
	var missing_tools: Array = report.get("missing_required_tools", [])
	var denominator := maxi(1, required + missing_tools.size())
	var percent := clampi(int(round(float(ready) / float(denominator) * 100.0)), 0, 100)
	progress_bar.value = percent
	progress_label.text = "%d%% • %s" % [percent, "синхронизировано" if bool(report.get("compatible", false)) else "достраивается"]
