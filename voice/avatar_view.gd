class_name AuroraFoxAvatarView
extends Control

var emotion := "neutral"
var intensity := 0.45
var amplitude := 0.0
var listening := false
var thinking := false
var tail_phase := 0.0
var blink := 0.0
var blink_clock := 2.2
var ear_level := 0.55
var tail_speed := 0.55
var paw_glow := 0.10
var blink_rate := 1.0

func _ready() -> void:
	custom_minimum_size = Vector2(176, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func set_emotion(value: String, p_intensity: float, profile: Dictionary) -> void:
	emotion = value
	intensity = p_intensity
	ear_level = float(profile.get("ear", 0.55))
	tail_speed = float(profile.get("tail_speed", 0.55))
	paw_glow = float(profile.get("paw_glow", 0.10))
	blink_rate = float(profile.get("blink_rate", 1.0))
	queue_redraw()

func set_amplitude(value: float) -> void:
	amplitude = lerpf(amplitude, clampf(value, 0.0, 1.0), 0.55)
	queue_redraw()

func set_listening(value: bool) -> void:
	listening = value
	queue_redraw()

func set_thinking(value: bool) -> void:
	thinking = value
	queue_redraw()

func _process(delta: float) -> void:
	tail_phase += delta * (1.4 + tail_speed * 4.5)
	blink_clock -= delta * blink_rate
	if blink_clock <= 0.0:
		blink = 1.0
		blink_clock = randf_range(2.1, 5.4)
	blink = maxf(0.0, blink - delta * 8.0)
	amplitude = lerpf(amplitude, 0.0, minf(1.0, delta * 5.5))
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.53, size.y * 0.48)
	var white := Color("f4f8ff")
	var shadow := Color(0.04, 0.06, 0.10, 0.95)
	var green := Color("60ff9a")
	var cyan := Color("32c9ff")
	var warning := Color("ff6c6c") if emotion in ["error", "warning"] else green

	var tail_angle := sin(tail_phase) * 0.35 * tail_speed
	var tail_base := center + Vector2(47, 28)
	var tail_tip := tail_base + Vector2(43 + 8 * cos(tail_angle), 12 + 24 * sin(tail_angle))
	draw_polyline(PackedVector2Array([tail_base, tail_base + Vector2(22, 4), tail_tip]), shadow, 18.0, true)
	draw_polyline(PackedVector2Array([tail_base, tail_base + Vector2(22, 4), tail_tip]), Color("111826"), 12.0, true)

	var lift := 9.0 * ear_level + (7.0 if listening else 0.0)
	var left_ear := PackedVector2Array([center + Vector2(-43, -25), center + Vector2(-26, -64 - lift), center + Vector2(-8, -28)])
	var right_ear := PackedVector2Array([center + Vector2(11, -28), center + Vector2(32, -64 - lift), center + Vector2(46, -22)])
	draw_colored_polygon(left_ear, white)
	draw_colored_polygon(right_ear, white)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-37,-30), center + Vector2(-26,-54-lift), center + Vector2(-14,-31)]), Color("d9c9e9"))
	draw_colored_polygon(PackedVector2Array([center + Vector2(17,-31), center + Vector2(32,-54-lift), center + Vector2(40,-27)]), Color("d9c9e9"))

	draw_circle(center, 48, shadow)
	draw_circle(center, 44, white)
	draw_circle(center + Vector2(0, 45), 31, white)

	var look := Vector2(3, -3) if thinking or emotion == "thinking" else Vector2.ZERO
	var eye_h := lerpf(10.0, 1.5, blink)
	for ex in [-18.0, 18.0]:
		_draw_ellipse_shape(center + Vector2(ex, -8) + look, Vector2(10, eye_h), shadow)
		_draw_ellipse_shape(center + Vector2(ex, -8) + look, Vector2(7, maxf(1.0, eye_h - 2.0)), green)
		if blink < 0.6:
			draw_circle(center + Vector2(ex - 2, -11) + look, 1.7, Color.WHITE)

	draw_circle(center + Vector2(0, 10), 4.3, shadow)
	var mouth_open := clampf(amplitude * 14.0, 1.0, 13.0)
	_draw_ellipse_shape(center + Vector2(0, 22), Vector2(8.5, mouth_open), shadow)
	if mouth_open > 5.0:
		_draw_ellipse_shape(center + Vector2(0, 24), Vector2(5.0, mouth_open * 0.52), Color("d86f92"))

	var paw := center + Vector2(48, 43)
	draw_line(paw + Vector2(-12,-18), paw + Vector2(2,7), Color("8894a8"), 9.0, true)
	draw_circle(paw + Vector2(3,8), 10, Color("333b4c"))
	var glow_color := warning.lerp(cyan, 0.25)
	draw_circle(paw + Vector2(3,8), 5.5, glow_color)
	if paw_glow > 0.3:
		var ring_color := Color(glow_color.r, glow_color.g, glow_color.b, 0.12 + paw_glow * 0.18)
		draw_arc(paw + Vector2(3,8), 12 + paw_glow * 6, 0.0, TAU, 36, ring_color, 2.0, true)

func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(32):
		var a := TAU * float(i) / 32.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, color)