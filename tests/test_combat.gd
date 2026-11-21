extends SceneTree
## Run: godot --headless --path . --script tests/test_combat.gd

const Simulation = preload("res://scripts/combat_sim.gd")
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	_test_economy()
	_test_recovery()
	_test_targeting_and_armor()
	_test_specialists()
	_test_active_combat()
	_test_no_tower_defeat()
	_test_retriever_campaign()
	_test_determinism()
	if failures.is_empty():
		print("PASS: %d combat checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_economy() -> void:
	var sim = Simulation.new()
	check(sim.bones == 450 and sim.lives == 20, "Fresh run has starting economy and puppy lives")
	check(sim.wave_total == 10 and sim.path_points.size() >= 2, "Ten waves and a usable path")
	check(not sim.place_dog("malinois", 0), "Locked dogs cannot be placed")
	check(not sim.place_dog("retriever", -1) and not sim.place_dog("retriever", 500), "Invalid pads rejected")
	check(sim.place_dog("retriever", 0), "Starter dog can be placed")
	var dog: Dictionary = sim.dog_at_pad(0)
	check(sim.bones == 300, "Placement spends exact cost")
	check(not sim.place_dog("retriever", 0), "Occupied pads rejected")
	check(sim.upgrade_cost(dog.id) == 120, "Tier two cost uses data")
	check(sim.upgrade_dog(dog.id) and sim.bones == 180, "Upgrade is paid once")
	check(not sim.upgrade_dog(dog.id) and sim.bones == 180, "Unaffordable upgrade leaves economy unchanged")
	var refund: int = sim.sell_dog(dog.id)
	check(refund == 175 and sim.bones == 355, "Selling returns 65 percent of invested bones")
	check(sim.sell_dog(dog.id) == 0, "A sold dog cannot be sold twice")
	check(sim.start_wave(), "First wave can start")
	check(not sim.start_wave() and sim.wave == 1, "Cannot overlap waves")


func _test_recovery() -> void:
	var sim = Simulation.new()
	sim.place_dog("retriever", 0)
	var dog: Dictionary = sim.dog_at_pad(0)
	sim._damage_dog(dog, 10000.0)
	check(dog.state == "exhausted" and sim.dogs.size() == 1, "Zero HP exhausts without removing dog")
	var remaining: float = dog.recovery_left
	sim._damage_dog(dog, 10000.0)
	check(dog.recovery_left == remaining, "Exhausted dogs cannot be damaged or reset")
	sim.upgrade_dog(dog.id)
	check(dog.state == "exhausted" and dog.hp == 0.0, "Upgrade does not skip exhaustion")
	for unused in range(80):
		sim.step(0.1)
	# Floating point can leave a tiny timer remainder at exactly eight seconds.
	sim.step(0.04)
	check(dog.state == "active" and dog.hp >= dog.max_hp * 0.7, "Automatic recovery restores at least 70 percent HP")
	check(dog.protection > 1.8, "Recovered dog receives brief protection")
	var recovered_hp: float = dog.hp
	sim._damage_dog(dog, 100.0)
	check(dog.hp == recovered_hp, "Protection prevents immediate exhaustion loop")
	check(dog.pos.distance_to(dog.anchor) < 0.01, "Recovered dog is at its placement anchor")


func _test_targeting_and_armor() -> void:
	var sim = Simulation.new()
	sim.reset(["retriever", "malinois", "bulldog"])
	sim.bones = 4000
	sim.place_dog("malinois", 0)
	var dog: Dictionary = sim.dog_at_pad(0)
	sim._damage_dog(dog, 50.0)
	check(dog.hp == dog.max_hp and dog.armor == 70.0, "Tactical vest absorbs damage before HP")
	sim._damage_dog(dog, 100.0)
	check(dog.armor == 0.0 and dog.hp == dog.max_hp - 30.0, "Armor overflow reaches HP exactly")
	sim._spawn_enemy("ant")
	sim._spawn_enemy("beetle")
	var ant: Dictionary = sim.enemies[0]
	var beetle: Dictionary = sim.enemies[1]
	ant.progress = 5.0
	ant.pos = sim.point_on_path(5.0)
	beetle.progress = 3.5
	beetle.pos = sim.point_on_path(3.5)
	sim.set_target_mode(dog.id, "first")
	check(sim._select_target(dog).id == ant.id, "First targeting chooses furthest path progress")
	sim.set_target_mode(dog.id, "strongest")
	check(sim._select_target(dog).id == beetle.id, "Strongest targeting includes remaining armor")
	sim.set_target_mode(dog.id, "invalid")
	check(dog.target_mode == "strongest", "Unknown target mode does not corrupt state")
	var armor_before: float = beetle.armor
	sim._damage_enemy(beetle, 20.0, 0.7)
	check(is_equal_approx(beetle.armor, armor_before - 6.0), "Melee armor piercing absorbs only non-piercing fraction")
	check(is_equal_approx(beetle.hp, beetle.max_hp - 14.0), "Piercing damage reaches enemy HP")


func _test_specialists() -> void:
	var sim = Simulation.new()
	sim.reset(["retriever", "dachshund", "bulldog", "malinois"])
	sim.bones = 6000
	sim.place_dog("dachshund", 0)
	var trapper: Dictionary = sim.dog_at_pad(0)
	for unused in range(7):
		sim._drop_hazard(trapper, Vector2(-11, -5))
	check(sim.hazards.size() == 4, "Dachshund has bounded active traps")
	sim._spawn_enemy("beetle")
	var beetle: Dictionary = sim.enemies[0]
	beetle.pos = Vector2(-11, -5)
	beetle.progress = 4.0
	sim._tick_hazards(0.1)
	check(beetle.slow < 1.0 and beetle.armor < 22.0, "Poop traps both slow and damage")
	sim.place_dog("bulldog", 12)
	var guardian: Dictionary = sim.dog_at_pad(12)
	sim._bark(guardian, beetle)
	var after_first: float = beetle.progress
	sim._bark(guardian, beetle)
	check(after_first < 4.0 and beetle.progress == after_first, "Bark pushes back but repeated immediate control is resisted")
	sim._spawn_enemy("scorpion_boss")
	var boss: Dictionary = sim.enemies[-1]
	boss.pos = Vector2(-11, -5)
	boss.progress = 4.0
	sim._bark(guardian, boss)
	check(boss.progress > after_first and boss.progress < 4.0, "Boss knockback resistance is applied")
	sim.sell_dog(trapper.id)
	check(sim.hazards.is_empty(), "Selling a trapper removes owned hazards")


func _test_no_tower_defeat() -> void:
	var sim = Simulation.new()
	for unused in range(10000):
		if sim.phase == "build":
			sim.start_wave()
		sim.step(0.2)
		if sim.phase == "defeat":
			break
	check(sim.phase == "defeat" and sim.lives == 0, "An undefended puppy eventually loses the level")
	check(sim.wave == 2, "No-tower defeat occurs during the second wave")
	var finished_time: float = sim.time
	sim.step(1.0)
	check(sim.time == finished_time, "Finished simulation cannot keep progressing")
	check(not sim.place_dog("retriever", 0), "Cannot mutate finished battle by placing dogs")


func _test_active_combat() -> void:
	var pressure = Simulation.new()
	pressure.place_dog("retriever", 2)
	pressure.start_wave()
	pressure._spawn_queue.clear()
	var defender: Dictionary = pressure.dog_at_pad(2)
	for unused in range(12):
		pressure._spawn_enemy("scorpion")
		var attacker: Dictionary = pressure.enemies[-1]
		attacker.progress = 16.6
		attacker.pos = pressure.point_on_path(16.6)
	pressure.step(1.0)
	check(defender.state == "exhausted", "Nearby wildlife attacks can exhaust a placed tower")
	check(pressure._enemy_target(pressure.enemies[0]).is_empty(), "Wildlife stops targeting an exhausted dog")
	for unused in range(90):
		pressure.step(0.1)
	check(defender.state == "active", "Exhaustion recovers during a live wave without player input")
	var melee = Simulation.new()
	melee.reset(["retriever", "malinois"])
	melee.bones = 1500
	melee.place_dog("malinois", 0)
	melee.start_wave()
	melee._spawn_queue.clear()
	melee._spawn_enemy("beetle")
	var target: Dictionary = melee.enemies[0]
	target.progress = 4.0
	target.pos = melee.point_on_path(4.0)
	var assault: Dictionary = melee.dog_at_pad(0)
	melee.step(0.15)
	check(assault.pos.distance_to(assault.anchor) > 1.0, "Malinois physically intercepts enemies inside its patrol range")
	melee.step(1.0)
	check(melee.defeated_count == 1, "Malinois melee defeats an armored enemy through actual combat")


func _test_retriever_campaign() -> void:
	var sim = Simulation.new()
	var pad_order: Array = [12, 0, 13, 1, 2, 4, 7, 6, 9, 10, 11, 8, 3, 5]
	for pad in [12, 0, 13]:
		sim.place_dog("retriever", pad)
	var iterations: int = 0
	while not ["victory", "defeat"].has(sim.phase) and iterations < 15000:
		if sim.phase == "build":
			# Player-like strategy: strengthen the front line, then cover the rest.
			for dog in sim.dogs:
				while sim.upgrade_cost(dog.id) > 0 and sim.bones >= sim.upgrade_cost(dog.id):
					sim.upgrade_dog(dog.id)
			for pad in pad_order:
				if sim.bones >= 150 and sim.dog_at_pad(pad).is_empty():
					sim.place_dog("retriever", pad)
			sim.start_wave()
		sim.step(0.1)
		sim.consume_events()
		iterations += 1
	print("Retriever campaign: phase=%s lives=%d bones=%d dogs=%d defeated=%d time=%.1fs" % [sim.phase, sim.lives, sim.bones, sim.dogs.size(), sim.defeated_count, sim.time])
	check(sim.phase == "victory" and sim.wave == 10, "Starter-only strategy can complete all ten waves")
	check(sim.lives > 0 and sim.defeated_count > 200, "Victory is earned through real combat")
	check(sim.bones >= 0, "Campaign never creates negative currency")
	check(sim.enemies.is_empty(), "Victory waits until the last enemy is resolved")


func _test_determinism() -> void:
	var first = Simulation.new()
	var second = Simulation.new()
	for sim in [first, second]:
		sim.place_dog("retriever", 12)
		sim.place_dog("retriever", 0)
		sim.start_wave()
	for unused in range(400):
		first.step(0.05)
		second.step(0.05)
	check(first.bones == second.bones and first.lives == second.lives, "Identical inputs produce identical economy")
	check(first.enemies == second.enemies and first.dogs == second.dogs, "Identical steps produce identical combat state")
