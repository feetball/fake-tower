extends RefCounted
## Settings > Volume: the three sliders (master, ambient noise, radio / ATC voice),
## what each one drives, and that they persist. UiSettings writes user://settings.cfg,
## so every test swaps in a scratch ConfigFile and puts the real one back afterwards.

const T := preload("res://tests/lib/t.gd")


class FakeVoice:
	extends RefCounted
	var volume := -1.0

	func set_volume(v: float) -> void:
		volume = v


## Runs `body` against an empty settings file, a fake Voice and the real Master bus
## (all restored afterwards). `body` takes the FakeVoice.
func _isolated(body: Callable) -> void:
	var had_file := FileAccess.file_exists(UiSettings.PATH)
	var real_cfg: ConfigFile = UiSettings._file()
	var real_voice: Object = Sess.voice_override
	var master := AudioServer.get_bus_index(&"Master")
	var master_db := AudioServer.get_bus_volume_db(master)
	var master_mute := AudioServer.is_bus_mute(master)
	var fake := FakeVoice.new()
	UiSettings._cfg = ConfigFile.new()
	Sess.voice_override = fake
	body.call(fake)
	UiSettings._cfg = real_cfg
	if had_file:
		real_cfg.save(UiSettings.PATH)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UiSettings.PATH))
	Sess.voice_override = real_voice
	AudioServer.set_bus_volume_db(master, master_db)
	AudioServer.set_bus_mute(master, master_mute)


func test_defaults_are_full_ambient_and_radio(t) -> void:
	_isolated(func(_fake: FakeVoice) -> void:
		t.near(UiSettings.volume(), 0.8, 0.0001, "master default")
		t.near(UiSettings.ambient_volume(), 1.0, 0.0001, "ambient default")
		t.near(UiSettings.radio_volume(), 1.0, 0.0001, "radio default"))
	t.done()


func test_ambient_and_radio_are_clamped_and_saved(t) -> void:
	_isolated(func(fake: FakeVoice) -> void:
		UiSettings.set_ambient_volume(3.0)
		t.near(UiSettings.ambient_volume(), 1.0, 0.0001, "ambient clamps high")
		UiSettings.set_ambient_volume(-1.0)
		t.near(UiSettings.ambient_volume(), 0.0, 0.0001, "ambient clamps low")
		UiSettings.set_ambient_volume(0.35)
		t.near(UiSettings.ambient_volume(), 0.35, 0.0001, "ambient stored")
		UiSettings.apply_radio_volume(0.4)
		t.near(UiSettings.radio_volume(), 0.4, 0.0001, "radio stored")
		t.near(fake.volume, 0.4, 0.0001, "radio volume reaches the voice buses")
		# apply_all (game start) restores the radio level without rewriting the file.
		fake.volume = -1.0
		UiSettings.apply_all()
		t.near(fake.volume, 0.4, 0.0001, "apply_all re-applies the radio volume"))
	t.done()


func test_master_no_longer_drives_the_voice_buses(t) -> void:
	_isolated(func(fake: FakeVoice) -> void:
		UiSettings.apply_radio_volume(0.5)
		UiSettings.apply_volume(0.2)
		t.near(fake.volume, 0.5, 0.0001, "moving Master leaves the radio level alone")
		var master := AudioServer.get_bus_index(&"Master")
		t.near(db_to_linear(AudioServer.get_bus_volume_db(master)), 0.2, 0.001, "Master bus follows Master")
		UiSettings.apply_volume(0.0)
		t.check(AudioServer.is_bus_mute(master), "Master at 0 mutes the bus"))
	t.done()


func test_read_aloud_follows_master_and_radio(t) -> void:
	_isolated(func(_fake: FakeVoice) -> void:
		UiSettings.apply_volume(0.8)
		UiSettings.apply_radio_volume(1.0)
		t.eq(UiSettings.read_aloud_volume(), 80, "master only")
		UiSettings.apply_radio_volume(0.5)
		t.eq(UiSettings.read_aloud_volume(), 40, "master x radio")
		UiSettings.apply_radio_volume(0.0)
		t.eq(UiSettings.read_aloud_volume(), 0, "radio at 0 silences the read-aloud voices")
		UiSettings.apply_radio_volume(1.0)
		UiSettings.set_ambient_volume(0.0)
		t.eq(UiSettings.read_aloud_volume(), 80, "ambient does not touch the read-aloud voices"))
	t.done()


func test_panel_sliders_show_and_drive_each_setting(t) -> void:
	_isolated(func(fake: FakeVoice) -> void:
		UiSettings.apply_volume(0.6)
		UiSettings.set_ambient_volume(0.25)
		UiSettings.apply_radio_volume(0.75)
		# The runner's root is not in the tree yet, so the panel is built detached.
		var panel := SettingsPanel.new()
		panel._ready()
		panel.open(false)
		var sliders: Array[HSlider] = []
		_collect(panel, sliders)
		t.eq(sliders.size(), 3, "three volume sliders")
		if sliders.size() == 3:
			t.near(sliders[0].value, 0.6, 0.0001, "master slider shows the saved value")
			t.near(sliders[1].value, 0.25, 0.0001, "ambient slider shows the saved value")
			t.near(sliders[2].value, 0.75, 0.0001, "radio slider shows the saved value")
			var label := sliders[1].get_meta(&"value_label") as Label
			t.eq(label.text, "25%", "ambient percentage label")
			_move(sliders[1], 0.5)
			t.near(UiSettings.ambient_volume(), 0.5, 0.0001, "ambient slider drives ambient volume")
			t.eq(label.text, "50%", "ambient label follows the slider")
			t.near(UiSettings.volume(), 0.6, 0.0001, "ambient slider leaves master alone")
			_move(sliders[2], 0.1)
			t.near(UiSettings.radio_volume(), 0.1, 0.0001, "radio slider drives radio volume")
			t.near(fake.volume, 0.1, 0.0001, "radio slider reaches the voice buses")
			t.near(UiSettings.ambient_volume(), 0.5, 0.0001, "radio slider leaves ambient alone")
		panel.free())
	t.done()


## A Range only emits value_changed inside the tree, and the panel is detached here.
func _move(slider: HSlider, v: float) -> void:
	slider.set_value_no_signal(v)
	slider.value_changed.emit(v)


func _collect(node: Node, out: Array[HSlider]) -> void:
	if node is HSlider:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
