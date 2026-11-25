extends Node
## Dev-only: shows the menu backdrop alone. User arg --framing=<name> picks an
## ApproachBackdrop framing (menu, lobby, cockpit, runway) for screenshots.

func _ready() -> void:
	var bd := $Backdrop as ApproachBackdrop
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--framing="):
			bd.set_framing(a.trim_prefix("--framing="), 0.0)
