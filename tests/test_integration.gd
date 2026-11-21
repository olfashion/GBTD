extends SceneTree
## Full entry-scene wiring checks; no access to the player's normal save file.
## Combat balancing and persistence edge cases live in the separate unit suites.

const MainScene = preload("res://scenes/main.tscn")
const Progression = preload("res://scripts/progression.gd")

var app
var checks: int = 0
var failures: Array[String] = []
var isolated_save: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1440, 900)
	isolated_save = "user://integration_tests/run_%s.json" % Time.get_ticks_usec()
	app = MainScene.instantiate()
	# _ready loads progress. Redirect it before the scene can enter the tree.
	app.progress.save_path = isolated_save
	root.add_child(app)
	app.set_process(false)
	# UI signals are exercised below; headless audio playback is not under test.
	# Keep the audio thread from retaining in-flight cues during rapid teardown.
	app.sound.enabled = false
	await _settle()
	_check(app.screen == "title", "Normal entry scene starts on the title screen")
	_check(app.progress.badges() == 0, "Scene uses a fresh isolated save")
	_check_overlay_bounds("title")
	_press("Protect the puppy")
	await _settle()
	_check(app.screen == "game" and app.sim.phase == "build", "Title play button enters the build phase")
	app.hud.dog_buttons["retriever"].pressed.emit()
	await _settle()
	_click_pad(12)
	await _settle()
	_check(app.sim.dogs.size() == 1 and app.selected_pad == 12, "Projected pad click places and selects the chosen Retriever")
	_check(app.sim.bones == 300 and not app.hud.upgrade_button.disabled, "First placement leaves enough bones for its visible upgrade")
	app.hud.upgrade_button.pressed.emit()
	await _settle()
	_check(app.selected_dog().level == 2 and app.sim.bones == 180, "Real upgrade button spends bones and updates the dog")
	app.hud.start_button.pressed.emit()
	_check(app.sim.phase == "wave" and app.sim.wave == 1, "Start Wave button launches the first wave")
	app._process(0.2)
	var dog: Dictionary = app.selected_dog()
	app.sim._damage_dog(dog, 10000.0)
	app.hud.speed_button.grab_focus()
	_send_key(KEY_SPACE)
	await _settle()
	_check(app.paused and app.speed == 1.0, "Reserved Space shortcut pauses even when another button has focus")
	_check_overlay_bounds("pause")
	var paused_time: float = app.sim.time
	var recovery_left: float = dog.recovery_left
	app._process(0.5)
	_check(app.sim.time == paused_time and dog.recovery_left == recovery_left, "Pause freezes combat and automatic recovery timers")
	_send_key(KEY_SPACE)
	_check(not app.paused, "Space resumes the same running wave")
	app.open_kennel()
	await _settle()
	_check_overlay_bounds("kennel")
	var scroll: ScrollContainer = _find_scroll(app.hud.overlay)
	_check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "Long kennel content is reachable by scrolling")
	app._process(0.5)
	_check(app.sim.time == paused_time and dog.recovery_left == recovery_left, "Kennel overlay freezes the live level without resetting it")
	_press("Back")
	_check(app.screen == "game" and app.sim.wave == 1, "Back from kennel resumes the existing level")
	app.open_help()
	await _settle()
	_check_overlay_bounds("help")
	_press("Got it")
	# The simulation suite proves the actual ten-wave win. This controlled
	# terminal fixture isolates the scene's result detection and reward wiring.
	app.sim.phase = "victory"
	app.sim.wave = app.sim.wave_total
	app.sim.lives = 20
	app.last_phase = "wave"
	app._process(0.01)
	await _settle()
	_check(app.screen == "results", "Terminal victory transitions to the result screen")
	_check(app.result.get("saved", false) and app.result.earned == 3, "Result flow saves the first-clear reward")
	_check_overlay_bounds("victory")
	var reloaded = Progression.new()
	reloaded.save_path = isolated_save
	reloaded.load_save()
	_check(reloaded.badges() == 3 and reloaded.best_stars() == 3, "Scene-earned rewards survive a fresh profile load")
	_press("Unlock more dogs")
	await _settle()
	var unlock_button: Button = _find_button(app.hud.overlay, "Unlock · 2", true)
	_check(unlock_button != null and not unlock_button.disabled, "Victory enables the earned Dachshund unlock")
	if unlock_button != null:
		unlock_button.pressed.emit()
	await _settle()
	_check(app.progress.badges() == 1 and "dachshund" in app.sim.unlocked, "Unlock button spends permanent badges and updates available towers")
	_press("Back")
	await _settle()
	_press("Play the yard again")
	await _settle()
	_check(app.sim.wave == 0 and app.sim.bones == 450 and app.sim.dogs.is_empty(), "Replay resets only the current run")
	app.hud.dog_buttons["dachshund"].pressed.emit()
	await _settle()
	_click_pad(12)
	await _settle()
	_check(app.sim.dog_at_pad(12).get("breed", "") == "dachshund" and app.sim.bones == 260, "Earned dog is usable through normal controls on replay")
	app.sim.phase = "defeat"
	app.sim.lives = 0
	app.last_phase = "wave"
	app._process(0.01)
	await _settle()
	_check(app.screen == "results" and app.result.earned == 0 and app.progress.badges() == 1, "Defeat returns results without creating permanent rewards")
	_check_overlay_bounds("defeat")
	reloaded.load_save()
	_check(reloaded.badges() == 1 and "dachshund" in reloaded.unlocked_dogs(), "UI unlock survives reload after a lost replay")
	# Check the same modal on the wider landscape canvas used by modern phones.
	root.size = Vector2i(1951, 900)
	app.open_kennel()
	await _settle()
	_check_overlay_bounds("wide-phone kennel")
	await _check_phone_layout()
	app.queue_free()
	await _settle()
	_cleanup_save()
	if failures.is_empty():
		print("PASS: %d entry-scene integration checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _settle() -> void:
	for unused in range(6):
		await process_frame


func _press(text: String) -> void:
	var button: Button = _find_button(app.hud.root, text)
	_check(button != null and not button.disabled, "Usable UI button exists: " + text)
	if button != null and not button.disabled:
		button.pressed.emit()


func _find_button(node: Node, text: String, prefix: bool = false) -> Button:
	if node is Button and (node.text.begins_with(text) if prefix else node.text == text):
		return node
	for child in node.get_children():
		var result: Button = _find_button(child, text, prefix)
		if result != null:
			return result
	return null


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var result: ScrollContainer = _find_scroll(child)
		if result != null:
			return result
	return null


func _click_pad(index: int) -> void:
	var pad: Vector2 = app.sim.pads[index]
	var position_3d := Vector3(pad.x, 0.12, pad.y)
	var mouse := InputEventMouseButton.new()
	mouse.position = app.yard.camera.unproject_position(position_3d)
	mouse.global_position = mouse.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse)
	mouse.pressed = false
	root.push_input(mouse)


func _send_key(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	root.push_input(key)
	key.pressed = false
	root.push_input(key)


func _check_overlay_bounds(label: String) -> void:
	for child in app.hud.overlay.get_children():
		if child is CenterContainer and child.get_child_count() > 0:
			var content: Control = child.get_child(0)
			var rect: Rect2 = content.get_global_rect()
			_check(app.hud.overlay.get_global_rect().encloses(rect), "%s overlay stays within the visible canvas: %s" % [label, rect])
			return
	_check(false, label + " overlay has its expected central content")


func _cleanup_save() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp", ".corrupt"]:
		var path: String = ProjectSettings.globalize_path(isolated_save + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _check_phone_layout() -> void:
	var scroll: ScrollContainer = _find_scroll(app.hud.overlay)
	scroll.scroll_vertical = 10000
	await _settle()
	var last_unlock: Button = _find_button(app.hud.overlay, "Unlock · 8", true)
	_check(last_unlock != null and scroll.get_global_rect().encloses(last_unlock.get_global_rect()), "Phone kennel's last unlock is fully reachable by scrolling")
	app.begin_game()
	await _settle()
	_check(app.hud.phone_ui, "Wide iPhone aspect ratio activates the adaptive phone layout")
	_check(_phone_controls_fit(app.hud.top) and _phone_controls_fit(app.hud.dock), "Phone HUD and pack controls fit and provide at least 104px touch targets")
	var labels_fit: bool = true
	for button in app.hud.dog_buttons.values():
		labels_fit = labels_fit and _labels_fit_inside(button, button.get_global_rect())
	_check(labels_fit, "Locked and unlocked phone dog-card labels stay inside their cards")
	var pads_clear: bool = true
	for pad in app.sim.pads:
		var point: Vector2 = app.yard.camera.unproject_position(Vector3(pad.x, 0.12, pad.y))
		var hit_area := Rect2(point - Vector2(23, 23), Vector2(46, 46))
		for panel in [app.hud.top, app.hud.hint_panel, app.hud.dock]:
			pads_clear = pads_clear and not panel.get_global_rect().intersects(hit_area)
	_check(pads_clear, "All fourteen phone placement hit regions remain clear of HUD controls")
	_click_pad(12)
	await _settle()
	_check(_phone_controls_fit(app.hud.dock), "Phone selected-dog controls fit with large touch targets")
	app.toggle_pause()
	await _settle()
	var sound: Button = _find_button(app.hud.overlay, "Sound on")
	_check(sound != null and sound.size.y >= 104.0, "Phone Sound control remains available in the pause menu")


func _phone_controls_fit(node: Node) -> bool:
	if node is Button and node.is_visible_in_tree():
		if node.size.x < 104.0 or node.size.y < 104.0 or not app.hud.root.get_global_rect().encloses(node.get_global_rect()):
			return false
	for child in node.get_children():
		if not _phone_controls_fit(child):
			return false
	return true


func _labels_fit_inside(node: Node, bounds: Rect2) -> bool:
	if node is Label and not bounds.encloses(node.get_global_rect()):
		return false
	for child in node.get_children():
		if not _labels_fit_inside(child, bounds):
			return false
	return true
