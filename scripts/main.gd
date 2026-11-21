extends Node3D
## Thin application coordinator: simulation, presentation, input and progression.

const Combat = preload("res://scripts/combat_sim.gd")
const Progress = preload("res://scripts/progression.gd")
const Yard = preload("res://scripts/yard_view.gd")
const Interface = preload("res://scripts/game_ui.gd")
const Sound = preload("res://scripts/game_audio.gd")

var sim = Combat.new()
var progress = Progress.new()
var yard
var hud
var sound
var screen: String = "title"
var previous_screen: String = "title"
var paused: bool = false
var speed: float = 1.0
var chosen_breed: String = "retriever"
var selected_pad: int = -1
var run_id: String = ""
var result: Dictionary = {}
var status_text: String = "Choose a dog, then tap a paw-print pad."
var status_left: float = 0.0
var sound_enabled: bool = true
var ui_clock: float = 0.0
var last_phase: String = "build"
var background_pause: bool = false


func _ready() -> void:
	progress.load_save()
	sim.reset(progress.unlocked_dogs())
	yard = Yard.new()
	add_child(yard)
	yard.setup(sim)
	sound = Sound.new()
	add_child(sound)
	hud = Interface.new()
	add_child(hud)
	hud.setup(self)
	# Automated QA starts from the exact same entry scene as a normal player.
	if "--play" in OS.get_cmdline_user_args():
		begin_game()
	if "--smoke-demo" in OS.get_cmdline_user_args():
		begin_game()
		for p in [2, 4, 7]:
			if p < sim.pads.size():
				sim.place_dog("retriever", p)
		start_wave()
		if "--capture" in OS.get_cmdline_user_args():
			_capture_after_delay()


func _process(delta: float) -> void:
	var active: bool = screen == "game" and not paused
	if active:
		# Substeps preserve combat behavior if a device misses a frame.
		var remaining: float = minf(delta, 0.2) * speed
		while remaining > 0.00001:
			var tick: float = minf(remaining, 1.0 / 30.0)
			sim.step(tick)
			remaining -= tick
		if status_left > 0.0:
			status_left -= delta
			if status_left <= 0.0:
				status_text = _default_hint()
		for event in sim.consume_events():
			_handle_event(event)
		if sim.phase != last_phase:
			last_phase = sim.phase
			if sim.phase == "victory" or sim.phase == "defeat":
				finish_game()
	yard.sync(sim, delta if active or screen == "title" else 0.0)
	ui_clock += delta
	if ui_clock >= 0.10:
		ui_clock = 0.0
		hud.refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if screen == "kennel" or screen == "help":
				close_overlay()
			elif screen == "game":
				toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and screen == "game":
			if sim.phase == "build" and not paused:
				start_wave()
			else:
				toggle_pause()
			get_viewport().set_input_as_handled()
		elif screen == "game" and event.keycode >= KEY_1 and event.keycode <= KEY_4:
			choose_dog(["retriever", "dachshund", "bulldog", "malinois"][event.keycode - KEY_1])
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if screen != "game" or paused:
		return
	# Touch is emulated as mouse by Godot, avoiding duplicate placements.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pad_index: int = yard.pick_pad(event.position)
		if pad_index >= 0:
			select_pad(pad_index)


func begin_game() -> void:
	sim.reset(progress.unlocked_dogs())
	run_id = "%s-%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]
	screen = "game"
	paused = false
	speed = 1.0
	selected_pad = -1
	chosen_breed = "retriever"
	result = {}
	last_phase = "build"
	status_text = "Tap a paw-print pad to place your first Retriever."
	status_left = 0.0
	yard.clear_selection()
	hud.rebuild()
	sound.play_cue("click")


func select_pad(index: int) -> void:
	var dog: Dictionary = sim.dog_at_pad(index)
	if not dog.is_empty():
		selected_pad = index
		chosen_breed = ""
		yard.set_selection(index, float(dog.range))
		hud.rebuild_dock()
		return
	if chosen_breed.is_empty():
		selected_pad = -1
		yard.clear_selection()
		toast("Choose a dog from the pack below.")
		hud.rebuild_dock()
		return
	if sim.place_dog(chosen_breed, index):
		selected_pad = index
		dog = sim.dog_at_pad(index)
		yard.set_selection(index, float(dog.range))
		toast("%s is on puppy duty!" % sim.dog_defs[chosen_breed].name)
		chosen_breed = ""
		sound.play_cue("place")
		hud.rebuild_dock()
	else:
		toast("Not enough bones. Defeat critters or finish a wave to earn more.")
		sound.play_cue("error")


func choose_dog(breed: String) -> void:
	if breed not in progress.unlocked_dogs():
		open_kennel()
		return
	chosen_breed = breed
	selected_pad = -1
	yard.clear_selection()
	toast("Choose a paw-print pad for your %s." % sim.dog_defs[breed].name)
	hud.rebuild_dock()
	sound.play_cue("click")


func selected_dog() -> Dictionary:
	return sim.dog_at_pad(selected_pad) if selected_pad >= 0 else {}


func deselect() -> void:
	selected_pad = -1
	chosen_breed = ""
	yard.clear_selection()
	hud.rebuild_dock()


func upgrade_selected() -> void:
	var dog: Dictionary = selected_dog()
	if not dog.is_empty() and sim.upgrade_dog(int(dog.id)):
		yard.set_selection(selected_pad, float(sim.get_dog(int(dog.id)).range))
		toast("Good dog. Even better defense.")
		sound.play_cue("upgrade")
		hud.rebuild_dock()
	else:
		toast("Earn more bones before the next upgrade.")


func sell_selected() -> void:
	var dog: Dictionary = selected_dog()
	if dog.is_empty():
		return
	var refunded: int = sim.sell_dog(int(dog.id))
	toast("Dog returned to the pack. +%s bones." % refunded)
	deselect()


func cycle_target() -> void:
	var dog: Dictionary = selected_dog()
	if dog.is_empty():
		return
	var modes: Array = ["first", "strongest", "closest", "last"]
	var next: int = (modes.find(dog.target_mode) + 1) % modes.size()
	sim.set_target_mode(int(dog.id), modes[next])
	hud.rebuild_dock()


func start_wave() -> void:
	if screen == "game" and not paused and sim.start_wave():
		toast("Wave %s. Protect the pup!" % sim.wave)
		sound.play_cue("wave")
		hud.refresh()


func toggle_pause() -> void:
	if screen != "game":
		return
	paused = not paused
	hud.rebuild_overlay()
	hud.refresh()


func toggle_speed() -> void:
	speed = 2.0 if speed == 1.0 else 1.0
	hud.refresh()


func toggle_sound() -> void:
	sound_enabled = not sound_enabled
	sound.enabled = sound_enabled
	hud.refresh()


func open_kennel() -> void:
	previous_screen = screen
	screen = "kennel"
	hud.rebuild_overlay()


func open_help() -> void:
	previous_screen = screen
	screen = "help"
	hud.rebuild_overlay()


func close_overlay() -> void:
	screen = previous_screen
	hud.rebuild_overlay()
	hud.rebuild_dock()


func unlock_dog(breed: String) -> void:
	var cost: int = int(sim.dog_defs[breed].unlock_cost)
	if progress.unlock(breed, cost):
		sim.unlocked = progress.unlocked_dogs()
		sound.play_cue("upgrade")
		hud.rebuild_overlay()
		hud.refresh()
	else:
		sound.play_cue("error")
		toast("That unlock could not be saved. Your badges have not been spent.")


func finish_game() -> void:
	screen = "results"
	paused = false
	if sim.phase == "victory":
		result = progress.record_victory(sim.lives, run_id)
		sound.play_cue("victory")
	else:
		result = {"earned": 0, "stars": 0, "first_clear": false, "total": progress.badges()}
		sound.play_cue("defeat")
	hud.rebuild_overlay()
	hud.refresh()


func retry_save_reward() -> void:
	if sim.phase == "victory":
		result = progress.record_victory(sim.lives, run_id)
		hud.rebuild_overlay()


func return_title() -> void:
	screen = "title"
	paused = false
	selected_pad = -1
	yard.clear_selection()
	progress.save()
	hud.rebuild()


func toast(message: String) -> void:
	status_text = message
	status_left = 4.0
	if is_instance_valid(hud):
		hud.refresh()


func _default_hint() -> String:
	if sim.phase == "build":
		return "Place or upgrade your pack, then start the next wave."
	return "Dogs recover automatically. Keep the path covered."


func _handle_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"exhausted":
			toast("Nap break! Your dog will recover automatically.")
		"wave_complete":
			toast("Wave cleared. Spend your bones and get ready.")
			sound.play_cue("complete")
		"leak":
			sound.play_cue("error")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if screen == "game" and not paused:
			paused = true
			background_pause = true
			if is_instance_valid(hud):
				hud.rebuild_overlay()
		if progress != null:
			progress.save()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "game":
			toggle_pause()
		elif screen == "kennel" or screen == "help":
			close_overlay()


func _capture_after_delay() -> void:
	await get_tree().create_timer(4.0).timeout
	if DisplayServer.get_name() != "headless":
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("user://first_level.png")
