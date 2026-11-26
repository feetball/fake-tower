class_name TouchButton
extends Control
## A finger-sized button drawn in the shell's style (smoked glass, hairline
## border, phosphor accent). Multi-touch safe: it tracks the finger that
## pressed it by InputEventScreenTouch index, so any number of TouchButtons
## (and the 3D/scope gestures) work at the same time — holding PTT with one
## thumb never blocks the other hand. Mouse events emulated from touch are
## ignored; a real mouse still works (desktop `--touch` testing).
##
## Signals: `down` / `up` for hold semantics (PTT), `tapped` for a press-and-
## release inside (or on touch-down with `fire_on_down`), `repeated` every
## REPEAT_EVERY s once held longer than REPEAT_DELAY (with `repeat`).

signal down
signal up
signal tapped
signal repeated

const REPEAT_DELAY := 0.45
const REPEAT_EVERY := 0.14
## How far a finger may slide off the button before a release stops counting as a tap.
const SLOP := 24.0

## Small line at the top (e.g. "HDG"); empty = text centred alone.
@export var caption := "":
	set(v):
		if v != caption:
			caption = v
			queue_redraw()
@export var text := "":
	set(v):
		if v != text:
			text = v
			queue_redraw()
## Lit state (mode armed, page open, layer on...).
@export var lit := false:
	set(v):
		if v != lit:
			lit = v
			queue_redraw()
@export var disabled := false:
	set(v):
		if v != disabled:
			disabled = v
			if v:
				cancel()
			queue_redraw()
@export var tint := UiTheme.ACCENT:
	set(v):
		if v != tint:
			tint = v
			queue_redraw()
@export var font_size := 22
@export var caption_size := 15
@export var mono := false
@export var fire_on_down := false
@export var repeat := false
## Text colour override while lit (default: tint).
var lit_text_color := Color(0, 0, 0, 0):
	set(v):
		if v != lit_text_color:
			lit_text_color = v
			queue_redraw()
## Draw a dimmer, more transparent body (for buttons over the 3D view).
var glass_alpha := 0.78
var corner := 4

var held := false
var _finger := -100 ## touch index, -2 = real mouse, -100 = none
var _inside := true
var _held_t := 0.0
var _next_repeat := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			cancel())


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			if _finger == -100:
				_press(st.index)
		elif st.index == _finger:
			_release(_hit(st.position))
		accept_event()
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		if sd.index == _finger:
			_inside = _hit(sd.position)
		accept_event()
	elif e is InputEventMouse:
		if TouchMode.is_emulated(e):
			accept_event() # the finger is handled above
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed and _finger == -100:
				_press(-2)
			elif not mb.pressed and _finger == -2:
				_release(_hit(mb.position))
			accept_event()
		elif e is InputEventMouseMotion and _finger == -2:
			_inside = _hit((e as InputEventMouseMotion).position)


func _hit(local: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).grow(SLOP).has_point(local)


func _press(finger: int) -> void:
	if disabled:
		return
	_finger = finger
	_inside = true
	held = true
	_held_t = 0.0
	_next_repeat = REPEAT_DELAY
	queue_redraw()
	down.emit()
	if fire_on_down:
		tapped.emit()


func _release(inside: bool) -> void:
	if _finger == -100:
		return
	_finger = -100
	held = false
	queue_redraw()
	up.emit()
	if inside and _inside and not fire_on_down and not disabled:
		tapped.emit()


## Drop a hold without a tap (hidden, disabled, focus lost).
func cancel() -> void:
	if _finger == -100:
		return
	_finger = -100
	held = false
	queue_redraw()
	up.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel()


func _process(delta: float) -> void:
	if not held or not repeat:
		return
	_held_t += delta
	while _held_t >= _next_repeat:
		_next_repeat += REPEAT_EVERY
		repeated.emit()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := Color(0.02, 0.025, 0.03, glass_alpha)
	var border := Color(1, 1, 1, 0.18)
	var fg := UiTheme.TEXT
	if lit:
		bg = bg.blend(Color(tint, 0.16))
		border = Color(tint, 0.85)
		fg = lit_text_color if lit_text_color.a > 0.0 else tint
	if held:
		bg = bg.blend(Color(tint, 0.3))
		border = tint
		fg = Color.WHITE if not lit else fg.lerp(Color.WHITE, 0.4)
	if disabled:
		bg = Color(0.02, 0.025, 0.03, glass_alpha * 0.6)
		border = Color(1, 1, 1, 0.07)
		fg = UiTheme.FAINT
	var sb := UiTheme.flat(bg, border, 2 if (lit or held) else 1, corner, 0, 0)
	draw_style_box(sb, r)
	var font: Font = UiTheme.mono(600) if mono else UiTheme.sans(500)
	var cap_font: Font = UiTheme.mono(500)
	var has_cap := caption != ""
	var lines := text.split("\n")
	var line_h := font.get_height(font_size)
	var block_h := line_h * lines.size()
	var cap_h := cap_font.get_height(caption_size) if has_cap else 0.0
	var gap := 4.0 if has_cap else 0.0
	var y0 := (size.y - block_h - cap_h - gap) * 0.5
	if has_cap:
		var cap_col := UiTheme.DIM if not lit else Color(tint, 0.9)
		if disabled:
			cap_col = UiTheme.FAINT
		draw_string(cap_font, Vector2(0.0, y0 + cap_font.get_ascent(caption_size)), caption,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, caption_size, cap_col)
		y0 += cap_h + gap
	for i in lines.size():
		draw_string(font, Vector2(0.0, y0 + i * line_h + font.get_ascent(font_size)), lines[i],
			HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, fg)


## Convenience constructor.
static func make(txt: String, sz: Vector2, cap: String = "") -> TouchButton:
	var b := TouchButton.new()
	b.text = txt
	b.caption = cap
	b.custom_minimum_size = sz
	b.size = sz
	return b
