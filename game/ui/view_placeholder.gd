class_name ViewPlaceholder
extends Control
## Neutral stand-in shown when the pilot or controller view scene is not part
## of this build yet.

var role := ""


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.014, 0.018)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var what := "Pilot view" if role == "pilot" else ("Controller view" if role == "controller" else "View")
	var box := UiKit.vbox(8, [UiKit.label("%s not available" % what, &"Big"),
		UiKit.label("This build does not include the %s scene yet." % what.to_lower(), &"Dim")])
	center.add_child(box)
