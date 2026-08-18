extends Control

var ai := AIClient.new()
var memory := MemoryStore.new()
var tools := ToolRegistry.new()
var agent := AgentCore.new()
var improver := SelfImprover.new()

var output: RichTextLabel
var input: LineEdit
var status: Label

func _ready() -> void:
	add_child(ai)
	add_child(memory)
	add_child(tools)
	add_child(agent)
	add_child(improver)
	agent.setup(ai, memory, tools)
	improver.setup(tools, ai)
	_build_ui()
	await get_tree().process_frame
	var available := await ai.is_available()
	status.text = "Ollama: %s | Model: %s | Tools: %d" % ["online" if available else "offline", ai.model, tools.tools.size()]

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("101218")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "AUTONOMOUS AI • GODOT 4.7.1"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	status = Label.new()
	status.text = "Инициализация..."
	box.add_child(status)

	output = RichTextLabel.new()
	output.bbcode_enabled = true
	output.fit_content = false
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.text = "[b]Система запущена.[/b]\nПамять, интернет и инструменты подключены.\n"
	box.add_child(output)

	var row := HBoxContainer.new()
	box.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "Поставьте задачу ИИ..."
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(_on_submit)
	row.add_child(input)

	var send := Button.new()
	send.text = "Выполнить"
	send.pressed.connect(func(): _on_submit(input.text))
	row.add_child(send)

	var improve := Button.new()
	improve.text = "Найти улучшение"
	improve.pressed.connect(_on_improve)
	row.add_child(improve)

func _on_submit(text: String) -> void:
	if text.strip_edges().is_empty(): return
	input.clear()
	output.append_text("\n[color=#8bd5ff][b]Вы:[/b][/color] %s\n" % text)
	status.text = "ИИ работает..."
	var answer := await agent.run_task(text)
	output.append_text("[color=#b7ffcf][b]AI:[/b][/color] %s\n" % answer)
	status.text = "Готов | Tools: %d | Memory: %d | Knowledge: %d" % [tools.tools.size(), memory.memory.size(), memory.knowledge.size()]

func _on_improve() -> void:
	status.text = "Анализ собственного кода..."
	var proposal := await improver.propose_improvement("повысить качество рассуждений, памяти или инструментов")
	if not proposal.get("ok", false):
		output.append_text("\n[color=red]Не удалось создать улучшение: %s[/color]\n" % proposal.get("error", "unknown"))
		status.text = "Ошибка улучшения"
		return
	var p: Dictionary = proposal.proposal
	output.append_text("\n[b]Предложено улучшение:[/b] %s\nФайл: %s\n" % [p.get("reason", ""), p.get("path", "")])
	var applied := await improver.apply_generated_module(p)
	output.append_text("%s\n" % JSON.stringify(applied))
	status.text = "Модуль улучшения создан для проверки"
