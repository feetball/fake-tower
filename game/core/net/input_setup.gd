extends RefCounted
## Registers the contract's input actions (ARCHITECTURE.md) when they are missing.
## Shift variants (hdg ×10, alt ×1000) are read by the views from the event's
## modifiers; flaps_up is Shift+F, so match flaps_down with exact_match = true.

## action -> [keycode, shift]
const ACTIONS := {
	"ptt": [KEY_SPACE, false],
	"hdg_left": [KEY_LEFT, false],
	"hdg_right": [KEY_RIGHT, false],
	"alt_up": [KEY_UP, false],
	"alt_down": [KEY_DOWN, false],
	"spd_up": [KEY_PAGEUP, false],
	"spd_down": [KEY_PAGEDOWN, false],
	"baro_down": [KEY_BRACKETLEFT, false],
	"baro_up": [KEY_BRACKETRIGHT, false],
	"baro_std": [KEY_B, false],
	"toggle_app": [KEY_A, false],
	"toggle_gear": [KEY_G, false],
	"flaps_down": [KEY_F, false],
	"flaps_up": [KEY_F, true],
	"show_atis": [KEY_I, false],
	"show_plate": [KEY_P, false],
}


static func register() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var spec: Array = ACTIONS[action]
		var ev := InputEventKey.new()
		ev.keycode = spec[0]
		ev.shift_pressed = spec[1]
		InputMap.action_add_event(action, ev)
