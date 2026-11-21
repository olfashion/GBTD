extends Node3D
## Presentation only: the simulation owns every combat and economy decision.

const Models = preload("res://scripts/models.gd")

var camera: Camera3D
var _sim
var _dogs: Dictionary = {}
var _enemies: Dictionary = {}
var _projectiles: Dictionary = {}
var _hazards: Dictionary = {}
var _effects: Dictionary = {}
var _pads: Array[Node3D] = []
var _range: Node3D
var _selection: MeshInstance3D
var _puppy: Node3D
var _preview_breed := ""
var _selected_pad := -1
var _selection_radius := -1.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

func setup(sim) -> void:
	_sim = sim
	_rng.seed = 1836
	_make_lighting()
	_make_camera()
	_make_ground()
	_make_path(sim.path_points)
	_make_fence()
	_make_props()
	_make_pads(sim.pads)
	_range = Node3D.new()
	_range.name = "SelectedRange"
	add_child(_range)
	_range.hide()
	_selection = Models.annulus(0.96, 0.065, Color("ffe391"))
	_selection.position.y = 0.19
	add_child(_selection)
	_selection.hide()

func _make_lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("294d50")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.43
	# Keep the palette consistent on the Compatibility mobile renderer.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -35, 0)
	sun.light_color = Color.WHITE
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.3
	add_child(sun)

func _make_camera() -> void:
	camera = Camera3D.new()
	camera.name = "YardCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 26.2
	camera.near = 0.1
	camera.far = 150.0
	camera.position = Vector3(0, 29.5, 36.0)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 2.6), Vector3.UP)
	camera.current = true

func _make_ground() -> void:
	var base := Models.plinth(37.0, 23.0, -1.65, -0.5, Color("ae9464"), Color("806f51"))
	add_child(base)
	var earth := Models.plinth(36.7, 22.7, -0.52, -0.1, Color("bbad75"), Color("bc9c68"))
	add_child(earth)
	var grass := Models.plinth(36.6, 22.6, -0.12, 0.0, Color("89b260"), Color("62914e"))
	add_child(grass)
	# Low contrast patches keep the board lively without hiding the route.
	var tufts := Node3D.new()
	add_child(tufts)
	for i in 150:
		var point := Vector2(_rng.randf_range(-17.3, 17.3), _rng.randf_range(-10.5, 10.5))
		if _distance_to_path(point) < 1.1 or _distance_to_pad(point) < 1.05:
			continue
		var color := Color("79a858") if i % 3 else Color("9ab965")
		var size := _rng.randf_range(0.14, 0.35)
		Models.ball(tufts, Vector3(point.x, 0.03, point.y), Vector3(size, 0.045, size * 1.7), color)
	Models.bake(tufts)

func _make_path(points: Array) -> void:
	# Overlapping rounded bands match the simulation's exact polyline.
	var edging := Node3D.new()
	var dirt := Node3D.new()
	add_child(edging)
	add_child(dirt)
	for index in points.size() - 1:
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var middle := (a + b) * 0.5
		var length := a.distance_to(b)
		var angle := atan2((b - a).x, (b - a).y)
		var edge := Models.block(edging, Vector3(middle.x, 0.018, middle.y), Vector3(1.72, 0.035, length + 0.01), Color("b2955e"))
		edge.rotation.y = angle
		var road := Models.block(dirt, Vector3(middle.x, 0.044, middle.y), Vector3(1.49, 0.045, length + 0.01), Color("e4c68a"))
		road.rotation.y = angle
	for p in points:
		Models.part(edging, "cylinder", Vector3(p.x, 0.018, p.y), Vector3(1.72, 0.035, 1.72), Color("b2955e"))
		Models.part(dirt, "cylinder", Vector3(p.x, 0.044, p.y), Vector3(1.49, 0.045, 1.49), Color("e4c68a"))
	Models.bake(edging)
	Models.bake(dirt)
	var detail := Node3D.new()
	add_child(detail)
	for index in points.size() - 1:
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var steps := int(a.distance_to(b) / 0.65)
		for step in steps:
			var p := a.lerp(b, (float(step) + 0.5) / float(maxi(steps, 1)))
			p += normal * _rng.randf_range(-0.52, 0.52)
			var pebble := Models.ball(detail, Vector3(p.x, 0.08, p.y), Vector3(_rng.randf_range(0.08, 0.21), 0.035, _rng.randf_range(0.07, 0.16)), Color("cead76"))
			pebble.rotation.y = _rng.randf() * TAU
	Models.bake(detail)

func _make_fence() -> void:
	var fence := Node3D.new()
	add_child(fence)
	for x in range(-17, 18, 2):
		_fence_post(fence, Vector3(float(x), 0, -10.1))
	for height in [0.5, 1.08]:
		Models.block(fence, Vector3(0, height, -10.1), Vector3(34, 0.17, 0.14), Color("c9a378"))
	for side in [-1, 1]:
		var x := float(side) * 17.3
		for z in [-9.0, -7.0, -3.0, -1.0, 1.0, 3.0]:
			_fence_post(fence, Vector3(x, 0, z))
		for height in [0.5, 1.08]:
			Models.block(fence, Vector3(x, height, -8), Vector3(0.14, 0.17, 2.1), Color("c9a378"))
			Models.block(fence, Vector3(x, height, 0), Vector3(0.14, 0.17, 6.1), Color("c9a378"))
	Models.bake(fence)

func _fence_post(parent: Node3D, point: Vector3) -> void:
	Models.block(parent, point + Vector3(0, 0.7, 0), Vector3(0.21, 1.4, 0.22), Color("aa835d"))
	Models.part(parent, "cone", point + Vector3(0, 1.45, 0), Vector3(0.28, 0.18, 0.28), Color("d4b68b"))

func _make_props() -> void:
	_place(Models.oak(3.8), Vector2(-15.1, 3.8), 0.5)
	_place(Models.oak(4.0), Vector2(-4.1, -8.9), 1.3)
	_place(Models.oak(3.3), Vector2(15.4, -8.4), 0.7)
	_place(Models.oak(3.1), Vector2(-15.4, -9.0), 0.0)
	_place(Models.cactus(1.15), Vector2(8.5, 8.6), 0.2)
	_place(Models.cactus(0.75), Vector2(9.6, 8.8), -0.4)
	_place(Models.cactus(1.1), Vector2(-11.7, 6.8), 0.4)
	_place(Models.cactus(0.75), Vector2(0.0, -7.7), -0.3)
	_place(Models.cactus(0.82), Vector2(16.2, -3.0), 0.1)
	var stones := [Vector2(-12.5, 7.8), Vector2(-10.6, 7.2), Vector2(9.0, 9.1), Vector2(10.2, 8.2), Vector2(16.1, -3.8), Vector2(-3.0, -8.5), Vector2(-15.7, 6.0), Vector2(1.0, -8.3)]
	for i in stones.size():
		var size := Vector3(_rng.randf_range(0.6, 1.3), _rng.randf_range(0.28, 0.75), _rng.randf_range(0.5, 1.0))
		_place(Models.rock(size), stones[i], _rng.randf() * TAU)
	var flower_spots := [Vector2(-13.7, 4.8), Vector2(-14.4, 5.1), Vector2(-12.5, -8.8), Vector2(-5.4, -8.1), Vector2(-3.2, -7.9), Vector2(0.7, -8.7), Vector2(8.7, 7.8), Vector2(9.6, 7.5), Vector2(15.4, -6.9), Vector2(16.0, -6.7), Vector2(14.3, 8.7), Vector2(-4.8, 8.9)]
	for i in flower_spots.size():
		_place(Models.flowers(i + 20, i % 4 != 0), flower_spots[i], _rng.randf() * TAU)
	var house := Models.doghouse()
	_place(house, Vector2(16.0, 8.2), 0.0)
	# The protected puppy is deliberately small, fluffy, and always on screen.
	_puppy = Models.dog("retriever")
	_puppy.name = "Puppy"
	_puppy.scale = Vector3.ONE * 0.78
	_puppy.position = Vector3(14.2, 0.1, 6.3)
	_puppy.rotation.y = -0.9
	add_child(_puppy)
	var safe_circle := Models.annulus(1.08, 0.035, Color(0.91, 0.91, 0.65, 0.75))
	safe_circle.position = Vector3(14.7, 0.085, 5.9)
	add_child(safe_circle)
	var bowl := Node3D.new()
	Models.part(bowl, "cylinder", Vector3.ZERO, Vector3(0.55, 0.18, 0.55), Color("539ca3"))
	Models.part(bowl, "cylinder", Vector3(0, 0.095, 0), Vector3(0.43, 0.035, 0.43), Color("7bd2d1"))
	Models.bake(bowl)
	_place(bowl, Vector2(14.3, 7.3))
	var entry := Node3D.new()
	Models.rod(entry, Vector3.ZERO, Vector3(0, 1.1, 0), 0.07, Color("8d704c"))
	Models.block(entry, Vector3(0, 1.05, 0), Vector3(1.15, 0.54, 0.12), Color("e0c28c"))
	Models.bake(entry)
	_place(entry, Vector2(-15.8, -6.6))
	var sign := Label3D.new()
	sign.text = "CRITTER\nCROSSING"
	sign.font_size = 44
	sign.pixel_size = 0.0045
	sign.modulate = Color("6b573d")
	sign.outline_size = 0
	sign.position = Vector3(-15.8, 1.06, -6.52)
	add_child(sign)

func _place(node: Node3D, point: Vector2, heading: float = 0.0) -> void:
	node.position = Vector3(point.x, 0.05, point.y)
	node.rotation.y = heading
	add_child(node)

func _make_pads(points: Array) -> void:
	for index in points.size():
		var point: Vector2 = points[index]
		var pad := Node3D.new()
		pad.position = Vector3(point.x, 0, point.y)
		Models.part(pad, "cylinder", Vector3(0, 0.07, 0), Vector3(1.76, 0.13, 1.76), Color("bfa879"))
		Models.part(pad, "cylinder", Vector3(0, 0.145, 0), Vector3(1.57, 0.035, 1.57), Color("b6cc89"))
		Models.bake(pad)
		var mark := Node3D.new()
		mark.name = "Marker"
		Models.ball(mark, Vector3(0, 0.18, 0.12), Vector3(0.39, 0.045, 0.32), Color("f2e5bd"))
		for toe in [Vector2(-0.25, -0.08), Vector2(-0.1, -0.24), Vector2(0.1, -0.24), Vector2(0.25, -0.08)]:
			Models.ball(mark, Vector3(toe.x, 0.18, toe.y), Vector3(0.14, 0.045, 0.18), Color("f2e5bd"))
		Models.bake(mark)
		pad.add_child(mark)
		add_child(pad)
		_pads.append(pad)

func pick_pad(screen_position: Vector2) -> int:
	if camera == null:
		return -1
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var collision = Plane(Vector3.UP, 0.12).intersects_ray(origin, direction)
	if collision == null:
		return -1
	var world := Vector2(collision.x, collision.z)
	var closest := -1
	# Slightly oversized hit regions support thumbs; actual placement is still
	# snapped to the unchanged simulation pad centers.
	var distance := 1.38
	for index in _sim.pads.size():
		var d: float = world.distance_to(_sim.pads[index])
		if d < distance:
			closest = index
			distance = d
	# Actor bodies extend above their pad. Clicking a dog's head also selects it.
	if closest == -1:
		var screen_radius := 44.0 * get_viewport().get_visible_rect().size.y / 900.0
		for dog in _sim.dogs:
			var position_3d := Vector3(dog.anchor.x, 0.85, dog.anchor.y)
			var d: float = screen_position.distance_to(camera.unproject_position(position_3d))
			if d < screen_radius:
				closest = dog.pad
				screen_radius = d
	return closest

func set_selection(pad_index: int, radius: float, valid: bool = true) -> void:
	if pad_index < 0 or pad_index >= _sim.pads.size():
		clear_selection()
		return
	var position_2d: Vector2 = _sim.pads[pad_index]
	_selected_pad = pad_index
	_selection.position = Vector3(position_2d.x, 0.2, position_2d.y)
	_selection.material_override = Models.material(Color("ffe391") if valid else Color("ee8f81"), true)
	_selection.show()
	if not is_equal_approx(_selection_radius, radius):
		for child in _range.get_children():
			child.queue_free()
		_range.add_child(Models.annulus(radius, 0.035, Color(0.98, 0.91, 0.62, 0.8)))
		var disk := Models.part(_range, "cylinder", Vector3.ZERO, Vector3(radius * 2, 0.012, radius * 2), Color(0.97, 0.89, 0.52, 0.08))
		disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_selection_radius = radius
	_range.position = Vector3(position_2d.x, 0.105, position_2d.y)
	_range.show()

func clear_selection() -> void:
	_selected_pad = -1
	if _selection != null:
		_selection.hide()
	if _range != null:
		_range.hide()

func set_preview(breed: String) -> void:
	_preview_breed = breed

func sync(sim, delta: float) -> void:
	_sim = sim
	_clock += delta
	_sync_dogs(sim)
	_sync_enemies(sim)
	_sync_projectiles(sim)
	_sync_hazards(sim)
	_sync_effects(sim)
	for index in _pads.size():
		var marker: Node3D = _pads[index].get_node("Marker")
		marker.visible = sim.dog_at_pad(index).is_empty()
		marker.position.y = sin(_clock * 2.5 + float(index)) * 0.025 if _preview_breed != "" else 0.0
	if _puppy != null:
		var visual: Node3D = _puppy.get_node("Visual")
		visual.position.y = maxf(0.0, sin(_clock * 6.0)) * 0.16 if sim.phase == "victory" else sin(_clock * 2.0) * 0.025
		var tail: Node3D = _puppy.get_node("Visual/Tail")
		tail.rotation.y = sin(_clock * 8.0) * 0.5

func _sync_dogs(sim) -> void:
	var live: Dictionary = {}
	for dog in sim.dogs:
		var id: int = dog.id
		live[id] = true
		if _dogs.has(id) and _dogs[id].get_meta("level", 1) != dog.level:
			_dogs[id].queue_free()
			_dogs.erase(id)
		if not _dogs.has(id):
			var model: Node3D = Models.dog(dog.breed, dog.level)
			model.set_meta("level", dog.level)
			_make_health_bar(model, 1.95 if dog.breed == "malinois" else 1.75)
			var sleep_label := Label3D.new()
			sleep_label.name = "SleepLabel"
			sleep_label.text = "z Z"
			sleep_label.font_size = 60
			sleep_label.pixel_size = 0.01
			sleep_label.position.y = 1.65
			sleep_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sleep_label.modulate = Color("e6f4d7")
			sleep_label.outline_modulate = Color("486553")
			sleep_label.outline_size = 8
			model.add_child(sleep_label)
			add_child(model)
			_dogs[id] = model
		var model: Node3D = _dogs[id]
		model.position = Vector3(dog.pos.x, 0.16, dog.pos.y)
		var facing: Vector2 = dog.get("facing", Vector2(0, 1))
		if facing.length_squared() > 0.01:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.y), 0.23)
		var resting: bool = dog.state == "exhausted"
		var visual: Node3D = model.get_node("Visual")
		visual.rotation.z = 0.15 if resting else 0.0
		visual.position.y = -0.24 if resting else sin(_clock * 2.0 + id) * 0.025
		var attack: float = dog.get("attack_anim", 0.0)
		visual.rotation.x = -sin(attack * PI) * 0.16 if not resting else 0.1
		model.get_node("Visual/Tail").rotation.y = sin(_clock * (7.0 if not resting else 1.5) + id) * 0.48
		model.get_node("Visual/Head").rotation.x = 0.23 if resting else sin(_clock * 1.8 + id) * 0.035
		for i in 4:
			var leg: Node3D = model.get_node("Visual/Leg%d" % i)
			leg.scale.y = 0.3 if resting else 1.0
			var moving: bool = dog.pos.distance_to(dog.anchor) > 0.12
			leg.rotation.x = sin(_clock * 22.0 + float(i) * PI) * 0.5 if moving and not resting else 0.0
		model.get_node("SleepLabel").visible = resting
		_update_health_bar(model, float(dog.hp) / maxf(float(dog.max_hp), 1.0), resting or dog.hp < dog.max_hp or dog.pad == _selected_pad, Color("9bd689") if not resting else Color("edbd68"))
	_remove_missing(_dogs, live)

func _sync_enemies(sim) -> void:
	var live: Dictionary = {}
	for enemy in sim.enemies:
		var id: int = enemy.id
		live[id] = true
		if not _enemies.has(id):
			var model: Node3D = Models.enemy(enemy.type)
			_make_health_bar(model, 1.85 if enemy.type == "scorpion_boss" else 1.15)
			add_child(model)
			_enemies[id] = model
		var model: Node3D = _enemies[id]
		model.position = Vector3(enemy.pos.x, 0.1, enemy.pos.y)
		var direction: Vector2 = enemy.direction
		if direction.length_squared() > 0.01:
			model.rotation.y = atan2(direction.x, direction.y)
		var pace := _clock * 15.0 + float(id) * 1.3
		model.get_node("Body").position.y = sin(pace) * 0.025
		model.get_node("LegsA").rotation.y = sin(pace) * 0.13
		model.get_node("LegsB").rotation.y = -sin(pace) * 0.13
		model.get_node("Body").rotation.z = sin(float(enemy.get("hit_flash", 0)) * PI) * 0.12
		_update_health_bar(model, float(enemy.hp) / maxf(float(enemy.max_hp), 1.0), enemy.hp < enemy.max_hp or enemy.type == "scorpion_boss", Color("efac74"))
	_remove_missing(_enemies, live)

func _sync_projectiles(sim) -> void:
	var live: Dictionary = {}
	for projectile in sim.projectiles:
		var id: int = projectile.id
		live[id] = true
		if not _projectiles.has(id):
			var model := Node3D.new()
			Models.ball(model, Vector3.ZERO, Vector3.ONE * 0.26, Color("e7eb84"))
			Models.rod(model, Vector3(-0.11, 0.02, 0.06), Vector3(0.11, 0.02, 0.06), 0.012, Color("ffffd5"))
			Models.bake(model)
			add_child(model)
			_projectiles[id] = model
		var model: Node3D = _projectiles[id]
		model.position = Vector3(projectile.pos.x, float(projectile.get("height", 0.5)) + 0.12, projectile.pos.y)
		model.rotation = Vector3(_clock * 10, _clock * 8, _clock * 7)
	_remove_missing(_projectiles, live)

func _sync_hazards(sim) -> void:
	var live: Dictionary = {}
	for hazard in sim.hazards:
		var id: int = hazard.id
		live[id] = true
		if not _hazards.has(id):
			var model := Node3D.new()
			Models.ball(model, Vector3(0, 0.12, 0), Vector3(0.66, 0.28, 0.64), Color("8a5e3b"))
			Models.ball(model, Vector3(0.02, 0.27, 0), Vector3(0.45, 0.25, 0.43), Color("996b43"))
			Models.part(model, "cone", Vector3(0.03, 0.43, 0), Vector3(0.28, 0.29, 0.28), Color("a47748"))
			Models.bake(model)
			add_child(model)
			_hazards[id] = model
		var model: Node3D = _hazards[id]
		model.position = Vector3(hazard.pos.x, 0.07, hazard.pos.y)
		model.scale = Vector3.ONE * minf(1.0, float(hazard.life) * 2.0)
	_remove_missing(_hazards, live)

func _sync_effects(sim) -> void:
	var live: Dictionary = {}
	for effect in sim.effects:
		var id: int = effect.id
		live[id] = true
		if not _effects.has(id):
			var model := Node3D.new()
			var kind: String = effect.kind
			if kind == "bark":
				var ring := Models.annulus(1.0, 0.07, Color(0.8, 0.94, 1.0, 0.9), 48)
				model.add_child(ring)
			elif kind == "recovered":
				model.add_child(Models.annulus(1.0, 0.08, Color("eaf7ad"), 40))
			else:
				var color := Color("f5e9a9") if kind != "defeated" else Color("ead5a0")
				for i in 5:
					var a := float(i) / 5.0 * TAU
					Models.ball(model, Vector3(cos(a) * 0.3, 0.3 + sin(a) * 0.15, sin(a) * 0.3), Vector3.ONE * 0.14, color)
				Models.bake(model)
			add_child(model)
			_effects[id] = model
		var model: Node3D = _effects[id]
		var progress := 1.0 - clampf(float(effect.life) / maxf(float(effect.max_life), 0.01), 0.0, 1.0)
		model.position = Vector3(effect.pos.x, 0.2, effect.pos.y)
		var radius: float = effect.get("radius", 1.0)
		var size := (0.35 + progress * 0.9) * maxf(0.7, radius)
		model.scale = Vector3.ONE * size
		if effect.kind != "bark" and effect.kind != "recovered":
			model.position.y += progress * 0.35
	_remove_missing(_effects, live)

func _make_health_bar(model: Node3D, height: float) -> void:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	bar.position.y = height
	model.add_child(bar)
	var background := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.095)
	background.mesh = quad
	background.material_override = Models.material(Color("314e44"), true)
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(background)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(0.84, 0.052)
	fill.mesh = fill_mesh
	fill.position.z = 0.012
	fill.material_override = Models.material(Color("a1d98c"), true)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(fill)
	bar.hide()

func _update_health_bar(model: Node3D, fraction: float, shown: bool, color: Color) -> void:
	var bar: Node3D = model.get_node("HealthBar")
	bar.visible = shown
	if not shown:
		return
	bar.look_at(camera.global_position, Vector3.UP, true)
	var fill: MeshInstance3D = bar.get_node("Fill")
	fill.scale.x = maxf(0.001, clampf(fraction, 0, 1))
	fill.position.x = -(1.0 - fill.scale.x) * 0.42
	fill.material_override = Models.material(color, true)

func _remove_missing(collection: Dictionary, live: Dictionary) -> void:
	for id in collection.keys():
		if not live.has(id):
			collection[id].queue_free()
			collection.erase(id)

func _distance_to_path(point: Vector2) -> float:
	var distance := 1000.0
	for index in _sim.path_points.size() - 1:
		var a: Vector2 = _sim.path_points[index]
		var b: Vector2 = _sim.path_points[index + 1]
		var nearest := Geometry2D.get_closest_point_to_segment(point, a, b)
		distance = minf(distance, point.distance_to(nearest))
	return distance

func _distance_to_pad(point: Vector2) -> float:
	var distance := 1000.0
	for pad in _sim.pads:
		distance = minf(distance, point.distance_to(pad))
	return distance
