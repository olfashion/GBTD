extends CanvasLayer
## Native, scalable Godot UI. All screens use the same live game simulation.

const INK := Color("203b3d")
const PANEL := Color("1b3035")
const CARD := Color("2b4648")
const CREAM := Color("fff3d6")
const MUTED := Color("b3c9bd")
const GOLD := Color("ffca72")
const MINT := Color("8dd6ad")
const CORAL := Color("f09a83")
const ORDER: Array = ["retriever", "dachshund", "bulldog", "malinois"]

var app
var root: Control
var top: Control
var dock: Control
var overlay: Control
var hint_panel: Control
var hint_label: Label
var bones_label: Label
var lives_label: Label
var wave_label: Label
var badges_label: Label
var start_button: Button
var speed_button: Button
var pause_button: Button
var sound_button: Button
var upgrade_button: Button
var state_label: Label
var wave_detail: Label
var dog_buttons: Dictionary = {}
var portraits: Dictionary = {}
var selection_signature: String = ""
var safe_insets := Vector4.ZERO # left, top, right, bottom in UI coordinates
var phone_ui: bool = false


func setup(controller) -> void:
	app = controller
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 24
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_color("font_pressed_color", "Button", CREAM)
	theme.set_color("font_disabled_color", "Button", Color("7f9790"))
	theme.set_constant("outline_size", "Label", 0)
	root.theme = theme
	for breed in ORDER:
		portraits[breed] = _portrait(breed)
	root.resized.connect(_apply_safe_area)
	rebuild()


func rebuild() -> void:
	phone_ui = _is_phone_ui()
	_clear(root)
	dog_buttons.clear()
	_make_top()
	_make_hint()
	dock = PanelContainer.new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = 22
	dock.offset_right = -22
	dock.offset_top = -205
	dock.offset_bottom = -20
	dock.add_theme_stylebox_override("panel", _style(PANEL, 22, Color("536d60"), 1))
	overlay = Control.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rebuild_dock()
	rebuild_overlay()
	_apply_safe_area()
	refresh()


func _make_top() -> void:
	top = PanelContainer.new()
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22
	top.offset_right = -22
	top.offset_top = 18
	top.offset_bottom = 148 if phone_ui else 106
	top.add_theme_stylebox_override("panel", _style(PANEL, 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	top.add_child(_margin(row, 22, 10))
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/icon.svg")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(62, 62)
	row.add_child(mark)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -2)
	row.add_child(brand)
	brand.add_child(_label("GOOD BOYS", 29, CREAM, true))
	brand.add_child(_label("BACKYARD DEFENSE", 14, MINT, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	wave_label = _stat(row, "WAVE", "0 / 10", CREAM)
	bones_label = _stat(row, "BONES", "450", GOLD)
	lives_label = _stat(row, "PUPPY LIVES", "20", CORAL)
	badges_label = _stat(row, "PAW BADGES", "0", MINT)
	var kennel := _button("Pack", app.open_kennel, "quiet", 88)
	kennel.tooltip_text = "Unlock more dogs with earned Paw Badges"
	row.add_child(kennel)
	var help := _button("?", app.open_help, "quiet", 58)
	help.tooltip_text = "How to play"
	row.add_child(help)
	pause_button = _button("II", app.toggle_pause, "quiet", 64)
	pause_button.tooltip_text = "Pause / resume (Space or Escape)"
	row.add_child(pause_button)


func _make_hint() -> void:
	hint_panel = PanelContainer.new()
	root.add_child(hint_panel)
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_panel.offset_left = 30
	hint_panel.offset_right = -30
	hint_panel.offset_top = -254
	hint_panel.offset_bottom = -218
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.19, 0.19, 0.85), 13))
	hint_label = _label("", 21, CREAM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint_label)


func rebuild_dock() -> void:
	if not is_instance_valid(dock):
		return
	_clear(dock)
	dog_buttons.clear()
	upgrade_button = null
	state_label = null
	sound_button = null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	dock.add_child(_margin(row, 22, 16))
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	row.add_child(content)
	var dog: Dictionary = app.selected_dog()
	if dog.is_empty():
		_build_pack_cards(content)
	else:
		_build_selection(content, dog)
	var separator := VSeparator.new()
	row.add_child(separator)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 350 if phone_ui else 236
	actions.add_theme_constant_override("separation", 10)
	row.add_child(actions)
	wave_detail = _label("THE FIRST YARD", 22 if phone_ui else 18, MUTED, true)
	wave_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions.add_child(wave_detail)
	start_button = _button("Start wave 1", app.start_wave, "gold", 230)
	start_button.custom_minimum_size.y = 110 if phone_ui else 67
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 10)
	if phone_ui:
		actions.add_child(small)
		small.add_child(start_button)
	else:
		actions.add_child(start_button)
		actions.add_child(small)
	speed_button = _button("1x speed", app.toggle_speed, "quiet", 112)
	speed_button.custom_minimum_size.y = 110 if phone_ui else 44
	small.add_child(speed_button)
	if not phone_ui:
		sound_button = _button("Sound on", app.toggle_sound, "quiet", 112)
		sound_button.custom_minimum_size.y = 44
		small.add_child(sound_button)
	selection_signature = _signature()
	refresh()


func _build_pack_cards(content: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	content.add_child(header)
	header.add_child(_label("YOUR PACK", 18, MINT, true))
	var help := _label("  Choose a dog. Tap a paw-print pad.", 18, MUTED)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(help)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	content.add_child(cards)
	for breed in ORDER:
		var definition: Dictionary = app.sim.dog_defs[breed]
		var unlocked: bool = breed in app.progress.unlocked_dogs()
		var button := _button("", app.choose_dog.bind(breed), "quiet", 0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(180, 110)
		button.tooltip_text = definition.description
		cards.add_child(button)
		dog_buttons[breed] = button
		if breed == app.chosen_breed:
			button.add_theme_stylebox_override("normal", _style(Color("3d5550"), 16, GOLD, 2))
		var inner := HBoxContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 8
		inner.offset_right = -8
		inner.add_theme_constant_override("separation", 6)
		_ignore_mouse(inner)
		button.add_child(inner)
		var portrait := _portrait_node(breed, 62)
		if not unlocked:
			portrait.modulate = Color(0.65, 0.7, 0.67, 0.9)
		inner.add_child(portrait)
		var text := VBoxContainer.new()
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.add_theme_constant_override("separation", 3)
		inner.add_child(text)
		text.add_child(_label(_short_name(breed), 28 if phone_ui else 21, CREAM if unlocked else MUTED, true))
		if not phone_ui:
			text.add_child(_label(str(definition.role), 15, MUTED))
		text.add_child(_label("%s bones" % int(definition.cost) if unlocked else ("%s badges" if phone_ui else "%s badges to unlock") % int(definition.unlock_cost),
			25 if phone_ui else 17, GOLD if unlocked else MINT))
		_ignore_mouse(button, false)


func _build_selection(content: VBoxContainer, dog: Dictionary) -> void:
	if phone_ui:
		_build_phone_selection(content, dog)
		return
	var definition: Dictionary = app.sim.dog_defs[dog.breed]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	content.add_child(head)
	head.add_child(_portrait_node(dog.breed, 76))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(_label("%s   ·   LEVEL %s" % [definition.name, dog.level], 27, CREAM, true))
	state_label = _label("", 20, MINT)
	info.add_child(state_label)
	var close := _button("Pack", app.deselect, "quiet", 90)
	head.add_child(close)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 12)
	content.add_child(options)
	var upgrade_cost: int = app.sim.upgrade_cost(int(dog.id))
	upgrade_button = _button("Max level" if dog.level >= 3 else "Upgrade  ·  %s bones" % upgrade_cost,
		app.upgrade_selected, "mint", 270)
	upgrade_button.custom_minimum_size.y = 54
	options.add_child(upgrade_button)
	var target := _button("Target: %s" % str(dog.target_mode).capitalize(), app.cycle_target, "quiet", 230)
	target.custom_minimum_size.y = 54
	target.tooltip_text = "Cycle First, Strongest, Closest and Last"
	options.add_child(target)
	var sell := _button("Return to pack", app.sell_selected, "quiet", 230)
	sell.custom_minimum_size.y = 54
	sell.tooltip_text = "Remove this dog and refund part of its invested bones"
	options.add_child(sell)


func _build_phone_selection(content: VBoxContainer, dog: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	row.add_child(_portrait_node(dog.breed, 72))
	var summary := VBoxContainer.new()
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(summary)
	summary.add_child(_label("%s · Lv %s" % [_short_name(dog.breed), dog.level], 28, CREAM, true))
	state_label = _label("", 24, MINT)
	summary.add_child(state_label)
	var cost: int = app.sim.upgrade_cost(int(dog.id))
	upgrade_button = _button("Max level" if dog.level >= 3 else "Upgrade\n%s bones" % cost,
		app.upgrade_selected, "mint", 200)
	upgrade_button.custom_minimum_size.y = 110
	row.add_child(upgrade_button)
	var target := _button("Target\n%s" % str(dog.target_mode).capitalize(), app.cycle_target, "quiet", 170)
	target.custom_minimum_size.y = 110
	row.add_child(target)
	var sell := _button("Sell", app.sell_selected, "quiet", 110)
	sell.tooltip_text = "Return this dog to the pack for a partial bones refund"
	sell.custom_minimum_size.y = 110
	row.add_child(sell)
	var back := _button("Pack", app.deselect, "quiet", 110)
	back.custom_minimum_size.y = 110
	row.add_child(back)


func refresh() -> void:
	if not is_instance_valid(root) or not is_instance_valid(bones_label):
		return
	var gameplay: bool = app.screen != "title"
	top.visible = gameplay
	dock.visible = gameplay
	hint_panel.visible = gameplay
	bones_label.text = str(app.sim.bones)
	lives_label.text = str(app.sim.lives)
	wave_label.text = "%s / %s" % [app.sim.wave, app.sim.wave_total]
	badges_label.text = str(app.progress.badges())
	hint_label.text = app.status_text
	pause_button.text = "Play" if app.paused else "II"
	if is_instance_valid(speed_button):
		speed_button.text = "%sx" % int(app.speed) if phone_ui else "%sx speed" % int(app.speed)
	if is_instance_valid(sound_button):
		sound_button.text = "Sound on" if app.sound_enabled else "Sound off"
	if is_instance_valid(start_button):
		start_button.disabled = app.sim.phase != "build" or app.paused or app.screen != "game"
		start_button.text = "Start wave %s" % (app.sim.wave + 1) if app.sim.phase == "build" else "Wave in progress"
		if phone_ui and app.sim.phase == "wave":
			start_button.text = "Wave %s" % app.sim.wave
		if app.sim.phase == "victory":
			start_button.text = "Yard defended!"
		elif app.sim.phase == "defeat":
			start_button.text = "Try another plan"
	if is_instance_valid(wave_detail):
		wave_detail.text = "THE FIRST YARD" if app.sim.phase != "wave" else "%s CRITTERS LEFT" % app.sim.enemies_remaining()
	var dog: Dictionary = app.selected_dog()
	if is_instance_valid(state_label) and not dog.is_empty():
		if dog.state == "exhausted":
			state_label.text = "Nap break · back in %.1fs" % float(dog.recovery_left)
			state_label.modulate = GOLD
		else:
			state_label.text = ("Health %s/%s\nArmor %s/%s" if phone_ui else "Health %s/%s    Armor %s/%s") % [ceili(dog.hp), int(dog.max_hp), ceili(dog.armor), int(dog.max_armor)]
			state_label.modulate = Color.WHITE
	if is_instance_valid(upgrade_button) and not dog.is_empty():
		upgrade_button.disabled = dog.level >= 3 or app.sim.bones < app.sim.upgrade_cost(int(dog.id)) or app.paused
	if selection_signature != _signature():
		rebuild_dock()


func rebuild_overlay() -> void:
	if not is_instance_valid(overlay):
		return
	_clear(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if app.screen == "game" and not app.paused:
		return
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.11, 0.13, 0.63 if app.screen == "title" else 0.69)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	match app.screen:
		"title":
			_build_title()
		"kennel":
			_build_kennel()
		"help":
			_build_help()
		"results":
			_build_results()
		"game":
			_build_pause()


func _build_title() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = safe_insets.x
	center.offset_top = safe_insets.y
	center.offset_right = -safe_insets.z
	center.offset_bottom = -safe_insets.w
	overlay.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 86)
	center.add_child(row)
	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 480
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_theme_constant_override("separation", 12)
	row.add_child(identity)
	identity.add_child(_label("A LITTLE PUP. A BIG BACKYARD.", 20, MINT, true))
	var title := _label("GOOD\nBOYS", 104, CREAM, true)
	title.add_theme_constant_override("line_spacing", -15)
	identity.add_child(title)
	identity.add_child(_label("BACKYARD DEFENSE", 31, GOLD, true))
	identity.add_child(_label("Liberty Hill, Texas", 23, MUTED))
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 490
	panel.add_theme_stylebox_override("panel", _style(PANEL, 28, Color("607e67"), 1))
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(_margin(box, 34, 32))
	box.add_child(_label("LEVEL 01", 20, MINT, true))
	box.add_child(_label("The First Yard", 40, CREAM, true))
	box.add_child(_body("The gate is open. The critters are coming.\nThe neighborhood pack has puppy duty.", 24))
	box.add_child(_divider())
	box.add_child(_body("10 waves  ·  20 puppy lives\nEarn badges. Unlock your next good boy.", 22, MUTED))
	box.add_child(_button("Protect the puppy", app.begin_game, "gold", 400))
	box.add_child(_button("Meet the pack  ·  %s badges" % app.progress.badges(), app.open_kennel, "quiet", 400))
	box.add_child(_button("How to play", app.open_help, "quiet", 400))
	if app.progress.best_stars() > 0:
		box.add_child(_label("BEST CLEAR   " + _stars(app.progress.best_stars()), 22, GOLD, true))
	var foot := _label("FIRST PLAYABLE  /  v0.1     •     TAP OR CLICK TO PLAY", 18, MUTED)
	footer(foot)


func _build_kennel() -> void:
	var box := _modal("THE NEIGHBORHOOD PACK", "Good dogs. Earned the old-fashioned way.", 1140)
	var top_row := HBoxContainer.new()
	box.add_child(top_row)
	var summary := _label("YOUR PAW BADGES    %s" % app.progress.badges(), 27, GOLD, true)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(summary)
	top_row.add_child(_button("Back", app.close_overlay, "quiet", 100))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	box.add_child(cards)
	for breed in ORDER:
		var definition: Dictionary = app.sim.dog_defs[breed]
		var unlocked: bool = breed in app.progress.unlocked_dogs()
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size.x = 240
		panel.add_theme_stylebox_override("panel", _style(CARD, 18))
		cards.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 14)
		panel.add_child(_margin(column, 20, 20))
		column.add_child(_portrait_node(breed, 120))
		column.add_child(_label(_short_name(breed), 27, CREAM, true))
		column.add_child(_label(str(definition.role).to_upper(), 16, MINT, true))
		var text := _body(str(definition.description), 20, MUTED)
		text.custom_minimum_size = Vector2(200, 124)
		column.add_child(text)
		column.add_child(_label("%s bones in a level" % int(definition.cost), 18, GOLD))
		var unlock_button := _button("In your pack" if unlocked else "Unlock · %s badges" % int(definition.unlock_cost),
			app.unlock_dog.bind(breed), "mint" if not unlocked else "quiet", 200)
		unlock_button.custom_minimum_size.y = 104 if phone_ui else 62
		unlock_button.add_theme_font_size_override("font_size", 20)
		unlock_button.disabled = unlocked or app.progress.badges() < int(definition.unlock_cost)
		column.add_child(unlock_button)
	box.add_child(_body("Win a level: +1 badge. First victory: +2 bonus badges. Replay to grow your pack.\nUnlocks are permanent on this device. Bones reset each run.", 20, MUTED))


func _build_help() -> void:
	var box := _modal("PUPPY DUTY 101", "A little strategy goes a long way.", 920)
	for item in [
		["PLACE", "Choose a dog from your pack, then tap a paw-print pad. Safe pads reach the path; close pads also invite critter attacks."],
		["DEFEND", "Start a wave. Dogs attack automatically. Tap a placed dog to upgrade it, change targeting, or return it to the pack for a partial refund."],
		["RECOVER", "Dogs never die. An exhausted dog naps, recovers automatically, and rejoins the fight. Cover its section of path with another dog."],
		["RECRUIT", "Survive all ten waves to earn Paw Badges. Spend them in the Pack screen to permanently unlock different breeds."]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		box.add_child(row)
		var label := _label(item[0], 21, MINT, true)
		label.custom_minimum_size.x = 125
		row.add_child(label)
		var body := _body(item[1], 22)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
	box.add_child(_divider())
	box.add_child(_body("Puppy lives reach zero? Try again with a different defense.\nDesktop: 1–4 choose dogs; Space starts/pauses; Esc pauses.\nOn a phone, play in landscape. Leaving the app pauses combat.", 20, MUTED))
	box.add_child(_button("Got it", app.close_overlay, "gold", 300))


func _build_pause() -> void:
	var box := _modal("TAKE A BREATHER", "The pack is waiting for you.", 570)
	box.add_child(_body("Combat, recovery timers, and wave progress are paused.", 23, MUTED))
	box.add_child(_button("Back to puppy duty", app.toggle_pause, "gold", 400))
	if phone_ui:
		sound_button = _button("Sound on" if app.sound_enabled else "Sound off", app.toggle_sound, "quiet", 400)
		box.add_child(sound_button)
	box.add_child(_button("How to play", app.open_help, "quiet", 400))
	box.add_child(_button("Restart this level", app.begin_game, "quiet", 400))
	box.add_child(_button("Main menu", app.return_title, "quiet", 400))


func _build_results() -> void:
	var won: bool = app.sim.phase == "victory"
	var box := _modal("YARD DEFENDED!" if won else "THE CRITTERS GOT THROUGH",
		"One safe puppy. A whole pack of good boys." if won else "The puppy is safe inside. Let's try a new plan.", 730)
	if won:
		var stars := _label(_stars(int(app.result.get("stars", 0))), 72, GOLD, true)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(stars)
		box.add_child(_body("All 10 waves survived  ·  %s / 20 puppy lives" % app.sim.lives, 24))
		box.add_child(_label("+%s PAW BADGES" % app.result.get("earned", 0), 36, MINT, true))
		if app.result.get("first_clear", false):
			box.add_child(_body("First victory bonus included! You can recruit a new dog from the Pack screen.", 23, MUTED))
		if not app.result.get("saved", true):
			box.add_child(_body("Your reward could not be saved. Retry saving before leaving this screen.", 22, CORAL))
			box.add_child(_button("Retry saving reward", app.retry_save_reward, "gold", 400))
		box.add_child(_button("Unlock more dogs", app.open_kennel, "gold", 400))
	else:
		box.add_child(_body("You reached wave %s of 10.\nTry covering multiple bends and upgrading before the next wave." % app.sim.wave, 25))
		box.add_child(_body("No dogs were lost. Your permanent unlocks are safe.", 22, MUTED))
	box.add_child(_button("Play the yard again" if won else "Try again", app.begin_game, "mint" if won else "gold", 400))
	box.add_child(_button("Main menu", app.return_title, "quiet", 400))


func _modal(title: String, subtitle: String, width: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = safe_insets.x
	center.offset_right = -safe_insets.z
	center.offset_top = 24 + safe_insets.y
	center.offset_bottom = -24 - safe_insets.w
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(PANEL, 25, Color("5f7964"), 1))
	center.add_child(panel)
	# A real scrolling viewport bounds long kennel/help content on phones.
	# CenterContainer alone lets a tall child's minimum size escape the screen.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var available: float = get_viewport().get_visible_rect().size.y - 116.0 - safe_insets.y - safe_insets.w
	var desired: float = 730.0 if app.screen == "kennel" else 620.0
	scroll.custom_minimum_size = Vector2(width - 68, maxf(320.0, minf(desired, available)))
	panel.add_child(_margin(scroll, 26, 22))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = width - 90
	box.add_theme_constant_override("separation", 19)
	scroll.add_child(box)
	box.add_child(_label(title, 38, CREAM, true))
	box.add_child(_body(subtitle, 23, MUTED))
	box.add_child(_divider())
	return box


func _button(text: String, callback: Callable, variant: String = "quiet", width: int = 0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(maxi(width, 104) if phone_ui else width, 104 if phone_ui else 66)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 28 if phone_ui else 23)
	var color: Color = CARD
	var font: Color = CREAM
	if variant == "gold":
		color = GOLD
		font = INK
	elif variant == "mint":
		color = MINT
		font = INK
	button.add_theme_stylebox_override("normal", _style(color, 14))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.08), 14, CREAM, 1))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.12), 14))
	button.add_theme_stylebox_override("disabled", _style(Color("2a3e3f"), 14))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 14, GOLD, 3))
	for setting in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(setting, font)
	button.pressed.connect(callback)
	return button


func _label(text: String, size: int = 24, color: Color = CREAM, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		var variation := FontVariation.new()
		variation.base_font = ThemeDB.fallback_font
		variation.variation_embolden = 0.6
		label.add_theme_font_override("font", variation)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _body(text: String, size: int = 23, color: Color = CREAM) -> Label:
	var label := _label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing", 5)
	return label


func _stat(parent: Control, caption: String, value: String, color: Color) -> Label:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 112
	column.add_theme_constant_override("separation", -3)
	parent.add_child(column)
	column.add_child(_label(caption, 14, MUTED, true))
	var label := _label(value, 31, color, true)
	column.add_child(label)
	return label


func _style(color: Color, radius: int = 16, border: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _margin(child: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	margin.add_child(child)
	return margin


func _divider() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_constant_override("separation", 8)
	return line


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _ignore_mouse(node: Node, include_self: bool = true) -> void:
	if include_self and node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _signature() -> String:
	var dog: Dictionary = app.selected_dog()
	return "%s:%s:%s" % [app.selected_pad, dog.get("level", 0), dog.get("target_mode", "")]


func _apply_safe_area() -> void:
	if not is_instance_valid(top) or not is_instance_valid(dock):
		return
	if phone_ui != _is_phone_ui():
		phone_ui = _is_phone_ui()
		call_deferred("rebuild")
		return
	var previous: Vector4 = safe_insets
	safe_insets = Vector4.ZERO
	if OS.has_feature("ios") or OS.has_feature("android"):
		var area: Rect2i = DisplayServer.get_display_safe_area()
		var pixels: Vector2i = DisplayServer.window_get_size()
		var logical: Vector2 = get_viewport().get_visible_rect().size
		if area.size.x > 0 and area.size.y > 0 and pixels.x > 0 and pixels.y > 0:
			var factor := logical / Vector2(pixels)
			safe_insets = Vector4(maxf(0, area.position.x * factor.x),
				maxf(0, area.position.y * factor.y),
				maxf(0, (pixels.x - area.end.x) * factor.x),
				maxf(0, (pixels.y - area.end.y) * factor.y))
	elif OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		# Safari exposes notch/home-indicator margins as CSS environment values.
		# Convert CSS pixels to Godot's logical UI coordinates just like native.
		var bridge = Engine.get_singleton("JavaScriptBridge")
		var encoded = bridge.eval("""(function () {
var probe = document.getElementById('good-boys-safe-area');
if (!probe) {
  probe = document.createElement('div');
  probe.id = 'good-boys-safe-area';
  probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
  document.body.appendChild(probe);
}
var s = getComputedStyle(probe);
return JSON.stringify([parseFloat(s.paddingLeft)||0,parseFloat(s.paddingTop)||0,
  parseFloat(s.paddingRight)||0,parseFloat(s.paddingBottom)||0,innerWidth,innerHeight]);
})()""", true)
		if encoded is String:
			var css = JSON.parse_string(encoded)
			if css is Array and css.size() == 6 and float(css[4]) > 0 and float(css[5]) > 0:
				var logical: Vector2 = get_viewport().get_visible_rect().size
				safe_insets = Vector4(float(css[0]) * logical.x / float(css[4]),
					float(css[1]) * logical.y / float(css[5]),
					float(css[2]) * logical.x / float(css[4]),
					float(css[3]) * logical.y / float(css[5]))
	top.offset_left = 22 + safe_insets.x
	top.offset_right = -22 - safe_insets.z
	top.offset_top = 18 + safe_insets.y
	top.offset_bottom = (148 if phone_ui else 106) + safe_insets.y
	dock.offset_left = 22 + safe_insets.x
	dock.offset_right = -22 - safe_insets.z
	dock.offset_top = -205 - safe_insets.w
	dock.offset_bottom = -20 - safe_insets.w
	hint_panel.offset_left = 30 + safe_insets.x
	hint_panel.offset_right = -30 - safe_insets.z
	hint_panel.offset_top = -254 - safe_insets.w
	hint_panel.offset_bottom = -218 - safe_insets.w
	if previous != safe_insets and is_instance_valid(overlay):
		rebuild_overlay()


func _is_phone_ui() -> bool:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return OS.has_feature("ios") or OS.has_feature("android") or DisplayServer.is_touchscreen_available() or size.x / maxf(size.y, 1.0) >= 1.95


func _short_name(breed: String) -> String:
	return {"retriever": "Retriever", "dachshund": "Dachshund", "bulldog": "Bulldog", "malinois": "Malinois"}.get(breed, breed)


func _stars(count: int) -> String:
	return "★".repeat(count) + "☆".repeat(3 - count)


func footer(label: Label) -> void:
	overlay.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_bottom = -26
	label.offset_top = -58
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _portrait_node(breed: String, size: int) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.texture = portraits[breed]
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(size, size)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return portrait


func _portrait(breed: String) -> ImageTexture:
	var fur: String = "e9b45f"
	var ear: String = "b77b3c"
	var muzzle: String = "ffe0a0"
	var ears: String = '<ellipse cx="30" cy="63" rx="16" ry="30" fill="#EAR"/><ellipse cx="98" cy="63" rx="16" ry="30" fill="#EAR"/>'
	var vest: String = '<path d="M30 110Q64 95 98 110L94 128H34Z" fill="#e16d53"/>'
	if breed == "dachshund":
		fur = "9e643b"
		ear = "503a2d"
		muzzle = "d39c60"
		ears = '<ellipse cx="29" cy="76" rx="13" ry="38" fill="#EAR"/><ellipse cx="99" cy="76" rx="13" ry="38" fill="#EAR"/>'
		vest = '<path d="M30 110Q64 95 98 110L94 128H34Z" fill="#69b5ae"/>'
	elif breed == "bulldog":
		fur = "c9bda3"
		ear = "8c8270"
		muzzle = "f9ebce"
		ears = '<path d="M25 60 19 29 51 36M103 60 109 29 77 36" fill="#EAR"/>'
		vest = '<path d="M30 110Q64 95 98 110L94 128H34Z" fill="#6c8db5"/>'
	elif breed == "malinois":
		fur = "c49659"
		ear = "2d3030"
		muzzle = "3c3932"
		ears = '<path d="M27 58 25 5 54 40M101 58 103 5 74 40" fill="#EAR"/>'
		vest = '<path d="M24 104Q64 90 104 104L100 128H28Z" fill="#263d39"/><rect x="35" y="107" width="58" height="14" rx="3" fill="#536754"/><path d="M40 99V128M88 99V128" stroke="#a7a77b" stroke-width="5"/>'
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 128 138"><circle cx="64" cy="68" r="60" fill="#45615a"/>EARS<rect x="28" y="32" width="72" height="83" rx="31" fill="#FUR"/><ellipse cx="64" cy="86" rx="30" ry="24" fill="#MUZZLE"/><ellipse cx="47" cy="65" rx="5" ry="7" fill="#192d30"/><ellipse cx="81" cy="65" rx="5" ry="7" fill="#192d30"/><circle cx="48" cy="63" r="1.6" fill="white"/><circle cx="82" cy="63" r="1.6" fill="white"/><path d="M54 79Q64 73 74 79 73 90 64 91 55 90 54 79" fill="#152c2e"/><path d="M59 98Q64 102 69 98V110Q64 119 59 110Z" fill="#e7857a"/>VEST</svg>'
	svg = svg.replace("EARS", ears).replace("VEST", vest).replace("#FUR", "#" + fur).replace("#EAR", "#" + ear).replace("#MUZZLE", "#" + muzzle)
	var image := Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)
