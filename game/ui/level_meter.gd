class_name LevelMeter
extends Control
## Segmented microphone level meter with a falling peak marker. Polls
## Voice.input_level (0..1) every frame unless `level` is driven externally.

@export var segments := 24
@export var gap := 3.0
@export var poll_voice := true

var level := 0.0
var _shown := 0.0
var _peak := 0.0
var _peak_hold := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(240.0, 12.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if poll_voice:
		level = Sess.input_level()
	# Fast attack, slow release, like a real PPM.
	_shown = level if level > _shown else maxf(level, _shown - delta * 1.6)
	if _shown >= _peak:
		_peak = _shown
		_peak_hold = 0.8
	else:
		_peak_hold -= delta
		if _peak_hold <= 0.0:
			_peak = maxf(_shown, _peak - delta * 0.6)
	queue_redraw()


func _draw() -> void:
	var w := (size.x - gap * (segments - 1)) / segments
	var lit := int(round(clampf(_shown, 0.0, 1.0) * segments))
	var peak_i := int(round(clampf(_peak, 0.0, 1.0) * segments)) - 1
	for i in segments:
		var f := float(i) / segments
		var col := UiTheme.ACCENT if f < 0.65 else (UiTheme.AMBER if f < 0.85 else UiTheme.RED)
		var on := i < lit or i == peak_i
		var c := col if on else Color(1, 1, 1, 0.07)
		draw_rect(Rect2(i * (w + gap), 0.0, w, size.y), c)
