extends RefCounted
## Deterministic, scene-independent combat rules. World Vector2 maps to 3D X/Z.
## Call step only while the game is unpaused; all timers use simulation seconds.

var dogs: Array = []
var enemies: Array = []
var projectiles: Array = []
var hazards: Array = []
var effects: Array = []
var bones: int = 450
var lives: int = 20
var wave: int = 0
var wave_total: int = 10
var time: float = 0.0
var phase: String = "build"
var path_points: Array = []
var pads: Array = []
var dog_defs: Dictionary = {}
var enemy_defs: Dictionary = {}
var unlocked: Array = ["retriever"]
var level_data: Dictionary = {}
var path_length: float = 0.0
var defeated_count: int = 0
var leaked_count: int = 0

var _path_lengths: Array = []
var _spawn_queue: Array = []
var _wave_time: float = 0.0
var _next_id: int = 1
var _events: Array = []


func _init() -> void:
	dog_defs = _read_json("res://data/dogs.json")
	enemy_defs = _read_json("res://data/enemies.json")
	level_data = _read_json("res://data/level_01.json")
	for point in level_data.get("path", []):
		path_points.append(Vector2(float(point[0]), float(point[1])))
	for point in level_data.get("pads", []):
		pads.append(Vector2(float(point[0]), float(point[1])))
	_path_lengths = [0.0]
	for index in range(1, path_points.size()):
		path_length += path_points[index - 1].distance_to(path_points[index])
		_path_lengths.append(path_length)
	wave_total = level_data.get("waves", []).size()
	reset()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing game data: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Invalid game data: " + path)
		return {}
	return parsed


func reset(available: Array = ["retriever"]) -> void:
	dogs.clear()
	enemies.clear()
	projectiles.clear()
	hazards.clear()
	effects.clear()
	_spawn_queue.clear()
	_events.clear()
	unlocked = available.duplicate()
	if not unlocked.has("retriever"):
		unlocked.append("retriever")
	bones = int(level_data.get("starting_bones", 450))
	lives = int(level_data.get("starting_lives", 20))
	wave = 0
	time = 0.0
	_wave_time = 0.0
	_next_id = 1
	defeated_count = 0
	leaked_count = 0
	phase = "build"


func _id() -> int:
	var result: int = _next_id
	_next_id += 1
	return result


func place_dog(breed: String, pad_index: int) -> bool:
	if phase == "victory" or phase == "defeat":
		return false
	if not dog_defs.has(breed) or not unlocked.has(breed):
		return false
	if pad_index < 0 or pad_index >= pads.size() or not dog_at_pad(pad_index).is_empty():
		return false
	var definition: Dictionary = dog_defs[breed]
	var cost: int = int(definition["cost"])
	if bones < cost:
		return false
	bones -= cost
	var dog: Dictionary = {
		"id": _id(), "breed": breed, "pad": pad_index,
		"pos": pads[pad_index], "anchor": pads[pad_index],
		"hp": float(definition["hp"]), "max_hp": float(definition["hp"]),
		"armor": float(definition["armor"]), "max_armor": float(definition["armor"]),
		"level": 1, "state": "active", "recovery_left": 0.0,
		"range": float(definition["range"]), "damage": float(definition["damage"]),
		"interval": float(definition["interval"]), "attack_cd": 0.12,
		"target_id": -1, "target_mode": "first", "attack_anim": 0.0,
		"protection": 0.0, "stun_left": 0.0, "poison_left": 0.0,
		"poison_tick": 0.0, "since_hit": 0.0, "invested": cost,
		"facing": Vector2(0, 1)
	}
	dogs.append(dog)
	_events.append({"type": "placed", "breed": breed, "id": dog["id"]})
	return true


func dog_at_pad(pad_index: int) -> Dictionary:
	for dog in dogs:
		if int(dog["pad"]) == pad_index:
			return dog
	return {}


func get_dog(id: int) -> Dictionary:
	for dog in dogs:
		if int(dog["id"]) == id:
			return dog
	return {}


func upgrade_cost(id: int) -> int:
	var dog: Dictionary = get_dog(id)
	if dog.is_empty() or int(dog["level"]) >= 3:
		return 0
	return int(dog_defs[dog["breed"]]["upgrade_costs"][int(dog["level"]) - 1])


func upgrade_dog(id: int) -> bool:
	if phase == "victory" or phase == "defeat":
		return false
	var dog: Dictionary = get_dog(id)
	var cost: int = upgrade_cost(id)
	if dog.is_empty() or cost <= 0 or bones < cost:
		return false
	bones -= cost
	dog["invested"] += cost
	dog["level"] += 1
	var definition: Dictionary = dog_defs[dog["breed"]]
	var tier: int = int(dog["level"]) - 1
	dog["damage"] = float(definition["damage"]) * [1.0, 1.55, 2.30][tier]
	dog["interval"] = float(definition["interval"]) * [1.0, 0.88, 0.75][tier]
	dog["range"] = float(definition["range"]) + 0.45 * tier
	var old_max: float = float(dog["max_hp"])
	dog["max_hp"] = float(definition["hp"]) * (1.0 + tier * 0.3)
	# Upgrades do not revive or bypass exhaustion.
	if dog["state"] == "active":
		dog["hp"] = minf(float(dog["max_hp"]), float(dog["hp"]) + float(dog["max_hp"]) - old_max)
	dog["max_armor"] = float(definition["armor"]) * (1.0 + tier * 0.4)
	_events.append({"type": "upgraded", "id": id, "level": dog["level"]})
	return true


func sell_dog(id: int) -> int:
	if phase == "victory" or phase == "defeat":
		return 0
	var dog: Dictionary = get_dog(id)
	if dog.is_empty():
		return 0
	var refund: int = int(float(dog["invested"]) * 0.65)
	bones += refund
	dogs.erase(dog)
	# Purchased output may finish travelling; traps disappear with their owner.
	for hazard in hazards.duplicate():
		if int(hazard["owner"]) == id:
			hazards.erase(hazard)
	_events.append({"type": "sold", "id": id, "refund": refund})
	return refund


func set_target_mode(id: int, mode: String) -> void:
	if not ["first", "last", "strongest", "closest"].has(mode):
		return
	var dog: Dictionary = get_dog(id)
	if not dog.is_empty():
		dog["target_mode"] = mode


func start_wave() -> bool:
	if phase != "build" or wave >= wave_total or path_points.size() < 2:
		return false
	wave += 1
	phase = "wave"
	_wave_time = 0.0
	_spawn_queue.clear()
	var spawn_time: float = 0.5
	var wave_definition: Dictionary = level_data["waves"][wave - 1]
	for group in wave_definition["groups"]:
		for unused in range(int(group["count"])):
			_spawn_queue.append({"at": spawn_time, "type": str(group["type"])})
			spawn_time += float(group["interval"])
		spawn_time += 0.8
	_events.append({"type": "wave_started", "wave": wave, "name": wave_definition["name"]})
	return true


func step(dt: float) -> void:
	if dt <= 0.0 or not is_finite(dt) or phase == "victory" or phase == "defeat":
		return
	# Fixed-size substeps prevent high frame delta from skipping hits or recovery.
	var remaining: float = minf(dt, 2.0)
	while remaining > 0.000001:
		var tick: float = minf(remaining, 1.0 / 30.0)
		_step_tick(tick)
		remaining -= tick
		if phase == "victory" or phase == "defeat":
			break


func _step_tick(dt: float) -> void:
	time += dt
	_tick_effects(dt)
	_tick_dog_states(dt)
	if phase != "wave":
		return
	_wave_time += dt
	while not _spawn_queue.is_empty() and float(_spawn_queue[0]["at"]) <= _wave_time:
		_spawn_enemy(str(_spawn_queue.pop_front()["type"]))
	_tick_hazards(dt)
	_tick_dog_attacks(dt)
	_tick_projectiles(dt)
	_tick_enemies(dt)
	if lives <= 0:
		lives = 0
		phase = "defeat"
		_events.append({"type": "defeat", "wave": wave})
	elif _spawn_queue.is_empty() and enemies.is_empty():
		var bonus: int = int(level_data["waves"][wave - 1]["bonus"])
		bones += bonus
		projectiles.clear()
		_events.append({"type": "wave_complete", "wave": wave, "bonus": bonus})
		if wave >= wave_total:
			phase = "victory"
			_events.append({"type": "victory", "lives": lives})
		else:
			phase = "build"


func _tick_dog_states(dt: float) -> void:
	for dog in dogs:
		dog["attack_anim"] = maxf(0.0, float(dog["attack_anim"]) - dt * 5.0)
		dog["protection"] = maxf(0.0, float(dog["protection"]) - dt)
		dog["stun_left"] = maxf(0.0, float(dog["stun_left"]) - dt)
		dog["since_hit"] += dt
		if dog["state"] == "exhausted":
			dog["pos"] = dog["pos"].move_toward(dog["anchor"], dt * 15.0)
			dog["recovery_left"] = maxf(0.0, float(dog["recovery_left"]) - dt)
			if float(dog["recovery_left"]) <= 0.0:
				dog["state"] = "active"
				dog["hp"] = float(dog["max_hp"]) * 0.7
				dog["armor"] = float(dog["max_armor"]) * 0.5
				dog["protection"] = 2.0
				dog["attack_cd"] = 0.2
				_effect(dog["pos"], "recovered", 0.8, 1.1)
				_events.append({"type": "recovered", "id": dog["id"]})
			continue
		if float(dog["poison_left"]) > 0.0:
			dog["poison_left"] = maxf(0.0, float(dog["poison_left"]) - dt)
			dog["poison_tick"] -= dt
			if float(dog["poison_tick"]) <= 0.0:
				dog["poison_tick"] = 1.0
				_damage_dog(dog, 3.0)
		if dog["state"] == "active" and (phase == "build" or float(dog["since_hit"]) > 4.0):
			var rate: float = 0.12 if phase == "build" else 0.025
			dog["hp"] = minf(float(dog["max_hp"]), float(dog["hp"]) + float(dog["max_hp"]) * rate * dt)
			dog["armor"] = minf(float(dog["max_armor"]), float(dog["armor"]) + float(dog["max_armor"]) * rate * dt)
		if phase == "build":
			dog["pos"] = dog["pos"].move_toward(dog["anchor"], dt * 10.0)


func _tick_dog_attacks(dt: float) -> void:
	for dog in dogs:
		if dog["state"] != "active" or float(dog["stun_left"]) > 0.0:
			continue
		dog["attack_cd"] = maxf(0.0, float(dog["attack_cd"]) - dt)
		var target: Dictionary = _select_target(dog)
		if target.is_empty():
			dog["target_id"] = -1
			dog["pos"] = dog["pos"].move_toward(dog["anchor"], dt * 12.0)
			continue
		dog["target_id"] = target["id"]
		var direction: Vector2 = target["pos"] - dog["pos"]
		if direction.length_squared() > 0.001:
			dog["facing"] = direction.normalized()
		if dog["breed"] == "malinois":
			dog["pos"] = dog["pos"].move_toward(target["pos"], dt * 16.0)
			if dog["pos"].distance_to(target["pos"]) > 1.1:
				continue
		if float(dog["attack_cd"]) > 0.0:
			continue
		dog["attack_cd"] = float(dog["interval"])
		dog["attack_anim"] = 1.0
		match str(dog["breed"]):
			"retriever":
				projectiles.append({
					"id": _id(), "kind": "tennis_ball", "pos": dog["pos"],
					"origin": dog["pos"], "height": 0.8, "target_id": target["id"],
					"damage": dog["damage"], "speed": 21.0, "age": 0.0,
					"bounces": int(dog["level"]) - 1, "hit_ids": []
				})
			"dachshund":
				_drop_hazard(dog, target["pos"])
			"bulldog":
				_bark(dog, target)
			"malinois":
				_damage_enemy(target, float(dog["damage"]), 0.7)
				_effect(dog["pos"], "bite", 0.32, 1.0)
		_events.append({"type": "attack", "breed": dog["breed"], "id": dog["id"]})


func _select_target(dog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var score: float = -INF
	for enemy in enemies:
		if float(enemy["hp"]) <= 0.0 or dog["anchor"].distance_to(enemy["pos"]) > float(dog["range"]):
			continue
		var value: float = float(enemy["progress"])
		match str(dog["target_mode"]):
			"last": value = -float(enemy["progress"])
			"strongest": value = float(enemy["hp"]) + float(enemy["armor"])
			"closest": value = -dog["pos"].distance_squared_to(enemy["pos"])
		if value > score:
			score = value
			result = enemy
	return result


func _tick_projectiles(dt: float) -> void:
	for projectile in projectiles.duplicate():
		projectile["age"] += dt
		var target: Dictionary = _get_enemy(int(projectile["target_id"]))
		if target.is_empty() or float(projectile["age"]) > 3.0:
			projectiles.erase(projectile)
			continue
		projectile["pos"] = projectile["pos"].move_toward(target["pos"], float(projectile["speed"]) * dt)
		projectile["height"] = 0.5 + absf(sin(float(projectile["age"]) * 11.0)) * 0.75
		if projectile["pos"].distance_to(target["pos"]) > 0.38:
			continue
		projectile["hit_ids"].append(target["id"])
		_damage_enemy(target, float(projectile["damage"]))
		if int(projectile["bounces"]) > 0:
			var next_enemy: Dictionary = _bounce_target(projectile)
			if not next_enemy.is_empty():
				projectile["target_id"] = next_enemy["id"]
				projectile["bounces"] -= 1
				projectile["damage"] *= 0.75
				continue
		projectiles.erase(projectile)


func _bounce_target(projectile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var nearest: float = 2.6
	for enemy in enemies:
		if projectile["hit_ids"].has(enemy["id"]):
			continue
		var distance: float = projectile["pos"].distance_to(enemy["pos"])
		if distance < nearest:
			nearest = distance
			result = enemy
	return result


func _drop_hazard(dog: Dictionary, pos: Vector2) -> void:
	var own_hazards: Array = []
	for hazard in hazards:
		if int(hazard["owner"]) == int(dog["id"]):
			own_hazards.append(hazard)
	if own_hazards.size() >= 4:
		hazards.erase(own_hazards[0])
	var tier: int = int(dog["level"]) - 1
	hazards.append({
		"id": _id(), "owner": dog["id"], "pos": pos, "kind": "poop",
		"radius": 1.15 + tier * 0.28, "life": 14.0, "damage": dog["damage"],
		"tick": 0.0, "slow": 0.62 - tier * 0.06
	})


func _tick_hazards(dt: float) -> void:
	for enemy in enemies:
		enemy["slow"] = 1.0
	for hazard in hazards.duplicate():
		hazard["life"] -= dt
		if float(hazard["life"]) <= 0.0:
			hazards.erase(hazard)
			continue
		hazard["tick"] -= dt
		var should_damage: bool = float(hazard["tick"]) <= 0.0
		if should_damage:
			hazard["tick"] = 0.55
		for enemy in enemies.duplicate():
			if hazard["pos"].distance_to(enemy["pos"]) <= float(hazard["radius"]):
				var multiplier: float = float(enemy_defs[enemy["type"]].get("control_multiplier", 1.0))
				var slow: float = 1.0 - (1.0 - float(hazard["slow"])) * multiplier
				enemy["slow"] = minf(float(enemy["slow"]), slow)
				if should_damage:
					_damage_enemy(enemy, float(hazard["damage"]))


func _bark(dog: Dictionary, target: Dictionary) -> void:
	var radius: float = 1.9 + (int(dog["level"]) - 1) * 0.35
	var center: Vector2 = target["pos"]
	_effect(dog["pos"], "bark", 0.5, float(dog["range"]))
	for enemy in enemies.duplicate():
		if enemy["pos"].distance_to(center) > radius:
			continue
		_damage_enemy(enemy, float(dog["damage"]))
		if float(enemy["hp"]) <= 0.0:
			continue
		# Per-enemy protection prevents multiple Bulldogs from permanent stun locks.
		if float(enemy["control_cooldown"]) <= 0.0:
			var multiplier: float = float(enemy_defs[enemy["type"]].get("control_multiplier", 1.0))
			enemy["progress"] = maxf(0.0, float(enemy["progress"]) - (1.0 + 0.25 * int(dog["level"])) * multiplier)
			enemy["pos"] = point_on_path(float(enemy["progress"]))
			enemy["stun_left"] = 0.45 * multiplier
			enemy["control_cooldown"] = 1.9


func _spawn_enemy(kind: String) -> void:
	var definition: Dictionary = enemy_defs[kind]
	enemies.append({
		"id": _id(), "type": kind, "pos": path_points[0],
		"direction": (path_points[1] - path_points[0]).normalized(),
		"hp": float(definition["hp"]), "max_hp": float(definition["hp"]),
		"armor": float(definition["armor"]), "progress": 0.0,
		"slow": 1.0, "hit_flash": 0.0, "attack_cd": 0.6,
		"stun_left": 0.0, "control_cooldown": 0.0,
		"scale": float(definition["scale"]), "attack_anim": 0.0
	})
	if bool(definition.get("boss", false)):
		_events.append({"type": "boss", "name": definition["name"]})


func _tick_enemies(dt: float) -> void:
	for enemy in enemies.duplicate():
		var definition: Dictionary = enemy_defs[enemy["type"]]
		enemy["hit_flash"] = maxf(0.0, float(enemy["hit_flash"]) - dt * 7.0)
		enemy["attack_anim"] = maxf(0.0, float(enemy["attack_anim"]) - dt * 6.0)
		enemy["control_cooldown"] = maxf(0.0, float(enemy["control_cooldown"]) - dt)
		enemy["attack_cd"] = maxf(0.0, float(enemy["attack_cd"]) - dt)
		if float(enemy["stun_left"]) > 0.0:
			enemy["stun_left"] = maxf(0.0, float(enemy["stun_left"]) - dt)
			continue
		# Wildlife never abandons the route. Attacking briefly reduces movement.
		var movement_scale: float = 1.0
		if float(enemy["attack_cd"]) <= 0.0:
			var defender: Dictionary = _enemy_target(enemy)
			if not defender.is_empty():
				enemy["attack_cd"] = float(definition["attack_interval"])
				enemy["attack_anim"] = 1.0
				_damage_dog(defender, float(definition["damage"]))
				if defender["state"] == "active" and float(defender["protection"]) <= 0.0:
					if enemy["type"] == "spider":
						defender["stun_left"] = maxf(float(defender["stun_left"]), 0.2)
					elif str(enemy["type"]).begins_with("scorpion"):
						defender["poison_left"] = 3.0
				movement_scale = 0.6
		var old_pos: Vector2 = enemy["pos"]
		enemy["progress"] += float(definition["speed"]) * float(enemy["slow"]) * movement_scale * dt
		enemy["pos"] = point_on_path(float(enemy["progress"]))
		if old_pos.distance_squared_to(enemy["pos"]) > 0.000001:
			enemy["direction"] = (enemy["pos"] - old_pos).normalized()
		if float(enemy["progress"]) >= path_length:
			lives = maxi(0, lives - int(definition["leak"]))
			leaked_count += 1
			_effect(enemy["pos"], "leak", 0.7, 1.5)
			_events.append({"type": "leak", "damage": definition["leak"], "lives": lives})
			enemies.erase(enemy)


func _enemy_target(enemy: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var best: float = -INF
	var reach: float = float(enemy_defs[enemy["type"]]["attack_range"])
	for dog in dogs:
		if dog["state"] != "active":
			continue
		var distance: float = dog["pos"].distance_to(enemy["pos"])
		if distance > reach:
			continue
		var priority: float = 10.0 - distance
		if dog["breed"] == "bulldog":
			priority += 20.0
		if priority > best:
			best = priority
			result = dog
	return result


func _damage_dog(dog: Dictionary, amount: float) -> void:
	if dog["state"] != "active" or float(dog["protection"]) > 0.0:
		return
	dog["since_hit"] = 0.0
	var absorbed: float = minf(float(dog["armor"]), amount)
	dog["armor"] -= absorbed
	dog["hp"] = maxf(0.0, float(dog["hp"]) - (amount - absorbed))
	if float(dog["hp"]) <= 0.0:
		dog["state"] = "exhausted"
		dog["target_id"] = -1
		dog["recovery_left"] = float(dog_defs[dog["breed"]]["recovery"])
		dog["poison_left"] = 0.0
		dog["stun_left"] = 0.0
		_effect(dog["pos"], "exhausted", 1.0, 1.0)
		_events.append({"type": "exhausted", "id": dog["id"]})


func _damage_enemy(enemy: Dictionary, amount: float, armor_pierce: float = 0.0) -> void:
	if float(enemy["hp"]) <= 0.0:
		return
	var absorbable: float = amount * (1.0 - armor_pierce)
	var absorbed: float = minf(float(enemy["armor"]), absorbable)
	enemy["armor"] -= absorbed
	enemy["hp"] = maxf(0.0, float(enemy["hp"]) - (amount - absorbed))
	enemy["hit_flash"] = 1.0
	_effect(enemy["pos"], "hit", 0.18, 0.35)
	if float(enemy["hp"]) <= 0.0:
		bones += int(enemy_defs[enemy["type"]]["reward"])
		defeated_count += 1
		_effect(enemy["pos"], "defeated", 0.45, 0.8)
		_events.append({"type": "defeated", "enemy": enemy["type"], "reward": enemy_defs[enemy["type"]]["reward"]})
		enemies.erase(enemy)


func _get_enemy(id: int) -> Dictionary:
	for enemy in enemies:
		if int(enemy["id"]) == id:
			return enemy
	return {}


func point_on_path(progress: float) -> Vector2:
	if path_points.is_empty():
		return Vector2.ZERO
	if progress <= 0.0:
		return path_points[0]
	for index in range(1, path_points.size()):
		if progress <= float(_path_lengths[index]):
			var start: float = float(_path_lengths[index - 1])
			var length: float = float(_path_lengths[index]) - start
			return path_points[index - 1].lerp(path_points[index], (progress - start) / length)
	return path_points[-1]


func _effect(pos: Vector2, kind: String, duration: float, radius: float) -> void:
	effects.append({"id": _id(), "pos": pos, "kind": kind, "life": duration, "max_life": duration, "radius": radius})
	# Visual effects are bounded even under a very large number of hits.
	if effects.size() > 100:
		effects.pop_front()


func _tick_effects(dt: float) -> void:
	for effect in effects.duplicate():
		effect["life"] -= dt
		if float(effect["life"]) <= 0.0:
			effects.erase(effect)


func consume_events() -> Array:
	var result: Array = _events.duplicate()
	_events.clear()
	return result


func wave_name() -> String:
	var index: int = clampi(wave if phase == "build" else wave - 1, 0, wave_total - 1)
	return str(level_data["waves"][index]["name"])


func enemies_remaining() -> int:
	return enemies.size() + _spawn_queue.size()
