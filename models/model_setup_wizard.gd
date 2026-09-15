class_name AuroraModelSetupWizard
extends Node

const STATE_PATH := "user://aurora_model_setup_state.json"
const LOCAL_MODEL_PATH := "user://models/aurorafox-main.gguf"
const FOX_LOGO: Texture2D = preload("res://assets/ui/fox_logo.svg")
var popup: PopupPanel
var stage_label: Label
var detail_label: Label
var shown := false
var startup_wait := 2.0

func _ready() -> void:
	if OS.get_name() != "Windows": return
	_build_ui(); set_process(true)

func _process(delta: float) -> void:
	if shown: return
	startup_wait -= delta
	if startup_wait > 0.0: return
	shown = true
	# AuroraFox Core is the primary runtime. Missing Ollama is never a startup error.
	if not await _core_ready(): popup.popup_centered()

func _core_ready() -> bool:
	var main := get_parent()
	if main != null:
		var existing_ai = main.get("ai")
		if existing_ai is AIClient:
			var info := existing_ai.runtime_info()
			if bool(info.get("model_installed", false)): return true
	return FileAccess.file_exists(LOCAL_MODEL_PATH)

func _build_ui() -> void:
	var layer := CanvasLayer.new(); layer.layer = 89; add_child(layer)
	popup = PopupPanel.new(); popup.size = Vector2i(680, 430); layer.add_child(popup)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: margin.add_theme_constant_override(side, 24)
	popup.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 14); margin.add_child(box)
	var title := Label.new(); title.text = "AuroraFox Core"; title.add_theme_font_size_override("font_size", 26); box.add_child(title)
	var description := Label.new(); description.text = "AuroraFox работает через собственное локальное ядро. Ollama больше не требуется для запуска. Установите или выберите локальную GGUF-модель AuroraFox. Совместимость с Ollama остаётся необязательным резервным режимом."; description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(description)
	stage_label = Label.new(); stage_label.text = "Локальная модель не установлена"; stage_label.add_theme_font_size_override("font_size", 18); box.add_child(stage_label)
	detail_label = Label.new(); detail_label.text = "Ожидаемый путь: %s\nМожно продолжить без Ollama и добавить модель позже." % LOCAL_MODEL_PATH; detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(detail_label)
	var info := Label.new(); info.text = "Поддержка базы знаний, памяти, агентов, Work, голоса и остальных функций не зависит от Ollama."; info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(info)
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; box.add_child(spacer)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_END; box.add_child(row)
	var later := Button.new(); later.text = "Продолжить"; later.pressed.connect(func(): popup.hide()); row.add_child(later)

func show_setup() -> void:
	if popup != null: popup.popup_centered()
