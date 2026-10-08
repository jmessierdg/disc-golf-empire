# radio_manager.gd
# Disc Golf Empire Radio - self-contained music player and mobile banner.
extends CanvasLayer

const MUSIC_DIRECTORY := "res://music"
const SETTINGS_FILE := "user://radio_settings.cfg"
const BANNER_DURATION := 5.0

var tracks: Array[String] = []
var current_index: int = -1
var shuffle_enabled: bool = false
var music_volume: float = 0.65
var expanded: bool = false
var player: AudioStreamPlayer
var banner: PanelContainer
var banner_label: Label
var subtitle_label: Label
var controls: HBoxContainer
var play_button: Button
var shuffle_button: Button
var volume_slider: HSlider
var banner_timer: Timer
var randomizer := RandomNumberGenerator.new()

func _ready() -> void:
	randomizer.randomize()
	load_preferences()
	build_interface()
	load_playlist()
	if not tracks.is_empty():
		play_track(0)
	else:
		banner.visible = false
		print("Disc Golf Empire Radio: Add MP3 or OGG files to res://music/ to enable music.")

func load_playlist() -> void:
	tracks.clear()
	var directory := DirAccess.open(MUSIC_DIRECTORY)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var filename: String = directory.get_next()
		if filename.is_empty():
			break
		if directory.current_is_dir():
			continue
		var extension: String = filename.get_extension().to_lower()
		if extension == "mp3" or extension == "ogg" or extension == "wav":
			tracks.append(MUSIC_DIRECTORY.path_join(filename))
	directory.list_dir_end()
	tracks.sort()

func build_interface() -> void:
	player = AudioStreamPlayer.new()
	player.name = "RadioAudio"
	player.finished.connect(_on_track_finished)
	add_child(player)
	update_volume()

	banner_timer = Timer.new()
	banner_timer.one_shot = true
	banner_timer.wait_time = BANNER_DURATION
	banner_timer.timeout.connect(_on_banner_timeout)
	add_child(banner_timer)

	var root := Control.new()
	root.name = "RadioOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	banner = PanelContainer.new()
	banner.name = "NowPlayingBanner"
	banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	banner.anchor_left = 1.0
	banner.anchor_right = 1.0
	banner.offset_left = -300.0
	banner.offset_right = -12.0
	banner.offset_top = 58.0
	banner.offset_bottom = 138.0
	banner.custom_minimum_size = Vector2(288.0, 78.0)
	banner.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(banner)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.115, 0.14, 0.94)
	style.border_color = Color(0.34, 0.70, 0.49, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(13)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", style)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	banner.add_child(stack)

	var heading := Button.new()
	heading.text = "♪  DISC GOLF EMPIRE RADIO   ▾"
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.flat = true
	heading.add_theme_font_size_override("font_size", 12)
	heading.pressed.connect(toggle_expanded)
	stack.add_child(heading)

	banner_label = Label.new()
	banner_label.text = "Now Playing"
	banner_label.add_theme_font_size_override("font_size", 17)
	banner_label.add_theme_color_override("font_color", Color(0.94, 0.98, 0.92))
	stack.add_child(banner_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Original Game Soundtrack"
	subtitle_label.add_theme_font_size_override("font_size", 11)
	subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.70))
	stack.add_child(subtitle_label)

	controls = HBoxContainer.new()
	controls.visible = false
	controls.add_theme_constant_override("separation", 5)
	stack.add_child(controls)

	var previous_button := Button.new()
	previous_button.text = "|◀"
	previous_button.pressed.connect(previous_track)
	controls.add_child(previous_button)

	play_button = Button.new()
	play_button.text = "Ⅱ"
	play_button.pressed.connect(toggle_pause)
	controls.add_child(play_button)

	var next_button := Button.new()
	next_button.text = "▶|"
	next_button.pressed.connect(next_track)
	controls.add_child(next_button)

	shuffle_button = Button.new()
	shuffle_button.text = "Mix On" if shuffle_enabled else "Mix Off"
	shuffle_button.pressed.connect(toggle_shuffle)
	controls.add_child(shuffle_button)

	volume_slider = HSlider.new()
	volume_slider.custom_minimum_size = Vector2(70.0, 24.0)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = music_volume
	volume_slider.value_changed.connect(set_music_volume)
	controls.add_child(volume_slider)

	# Persistent mini-radio tab lets the player reopen the controls at any time.
	var tab := Button.new()
	tab.name = "RadioTab"
	tab.text = "♫"
	tab.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tab.anchor_left = 1.0
	tab.anchor_right = 1.0
	tab.offset_left = -51.0
	tab.offset_right = -12.0
	tab.offset_top = 12.0
	tab.offset_bottom = 50.0
	tab.pressed.connect(toggle_radio_visibility)
	root.add_child(tab)

func play_track(index: int) -> void:
	if tracks.is_empty():
		return
	current_index = posmod(index, tracks.size())
	var stream_resource: Resource = load(tracks[current_index])
	if not (stream_resource is AudioStream):
		push_warning("Disc Golf Empire Radio: Unable to load " + tracks[current_index])
		return
	player.stream = stream_resource as AudioStream
	player.stream_paused = false
	player.play()
	play_button.text = "Ⅱ"
	var track_title: String = tracks[current_index].get_file().get_basename().replace("_", " ")
	banner_label.text = track_title
	subtitle_label.text = "Now playing  •  Original Game Soundtrack"
	banner.visible = true
	if not expanded:
		banner_timer.start()

func _on_track_finished() -> void:
	next_track()

func next_track() -> void:
	if tracks.is_empty():
		return
	if shuffle_enabled and tracks.size() > 1:
		var offset: int = randomizer.randi_range(1, tracks.size() - 1)
		play_track(current_index + offset)
	else:
		play_track(current_index + 1)

func previous_track() -> void:
	if not tracks.is_empty():
		play_track(current_index - 1)

func toggle_pause() -> void:
	if player.stream == null:
		return
	player.stream_paused = not player.stream_paused
	play_button.text = "▶" if player.stream_paused else "Ⅱ"

func toggle_shuffle() -> void:
	shuffle_enabled = not shuffle_enabled
	shuffle_button.text = "Mix On" if shuffle_enabled else "Mix Off"
	save_preferences()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	update_volume()
	save_preferences()

func update_volume() -> void:
	if player != null:
		player.volume_db = linear_to_db(maxf(music_volume, 0.0001))

func toggle_expanded() -> void:
	expanded = not expanded
	controls.visible = expanded
	if expanded:
		banner_timer.stop()
		banner.visible = true
	else:
		banner_timer.start()

func toggle_radio_visibility() -> void:
	if not banner.visible:
		banner.visible = true
		expanded = true
		controls.visible = true
		banner_timer.stop()
	else:
		banner.visible = false
		expanded = false
		controls.visible = false

func _on_banner_timeout() -> void:
	if not expanded:
		banner.visible = false

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		music_volume = float(config.get_value("radio", "volume", 0.65))
		shuffle_enabled = bool(config.get_value("radio", "shuffle", false))

func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("radio", "volume", music_volume)
	config.set_value("radio", "shuffle", shuffle_enabled)
	config.save(SETTINGS_FILE)
