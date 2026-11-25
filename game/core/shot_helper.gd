extends Node
## Screenshot helper for off-screen checks. Add as a child of any scene (or let
## main.tscn include it). If the game was started with the user args
## --shot=<path> [--shot-after=<seconds>], saves the viewport to <path> after
## the delay and quits. Does nothing otherwise.

func _ready() -> void:
	var path := ""
	var after := 4.0
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--shot="):
			path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-after="):
			after = float(a.trim_prefix("--shot-after="))
	if path == "":
		return
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
