extends SceneTree

const Progression = preload("res://scripts/progression.gd")
const TEST_DIRECTORY: String = "user://progression_tests"
var failures: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIRECTORY))
	_test_rewards_and_unlocks()
	_test_backup_recovery()
	_test_corrupt_and_newer_saves()
	_test_failed_mutation_rolls_back()
	print("Progression: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _profile(name: String):
	var profile = Progression.new()
	profile.save_path = TEST_DIRECTORY.path_join(name + ".json")
	for suffix: String in ["", ".bak", ".corrupt", ".tmp", ".bak.tmp"]:
		var path: String = ProjectSettings.globalize_path(profile.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	profile.load_save()
	return profile


func _write(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Fixture should be writable")
	file.store_string(contents)
	file.close()


func _test_rewards_and_unlocks() -> void:
	var profile = _profile("rewards")
	_check(profile.badges() == 0, "Fresh save has zero badges")
	_check(profile.unlocked_dogs() == ["retriever"], "Only Retriever starts unlocked")
	_check(not profile.unlock("dachshund", 2), "Cannot unlock without rewards")
	var reward: Dictionary = profile.record_victory(20, "first_run")
	_check(reward.saved and reward.earned == 3 and reward.first_clear, "First win saves three badges")
	_check(reward.stars == 3 and profile.best_stars() == 3, "Perfect win earns three stars")
	_check(profile.record_victory(20, "first_run").earned == 0, "Duplicate victory does not pay twice")
	_check(profile.badges() == 3, "Duplicate victory preserves balance")
	_check(not profile.unlock("dachshund", -2), "Negative price is rejected")
	_check(not profile.unlock("malinois", 1), "Spoofed price is rejected")
	_check(not profile.unlock("unknown_dog", 0), "Unknown dog is rejected")
	_check(profile.unlock("dachshund", 2), "Earned badges unlock Dachshund")
	_check(profile.badges() == 1, "Unlock deducts catalog price")
	_check(not profile.unlock("dachshund", 2) and profile.badges() == 1, "Repeated unlock does not charge")
	var restarted = Progression.new()
	restarted.save_path = profile.save_path
	restarted.load_save()
	_check(restarted.unlocked_dogs().has("dachshund") and restarted.badges() == 1, "Unlock persists after reload")
	_check(restarted.record_victory(12, "first_run").earned == 0, "Reward idempotency survives reload")
	var replay: Dictionary = restarted.record_victory(12, "second_run")
	_check(replay.earned == 1 and not replay.first_clear and replay.stars == 2, "Replay pays one badge")
	_check(restarted.best_stars() == 3, "Worse replay preserves personal best")
	_check(restarted.record_victory(1, "third_run").stars == 1, "One surviving life earns one star")
	_check(restarted.record_victory(0, "defeat").earned == 0, "Defeat receives no reward")
	_check(restarted.record_victory(21, "invalid").earned == 0, "Invalid lives receives no reward")
	_check(restarted.record_victory(20, " ").earned == 0, "Empty run ID receives no reward")
	var exposed: Array = restarted.unlocked_dogs()
	exposed.append("malinois")
	_check(not restarted.unlocked_dogs().has("malinois"), "Returned unlock list cannot mutate profile")


func _test_backup_recovery() -> void:
	var profile = _profile("backup")
	profile.record_victory(20, "one")
	profile.record_victory(18, "two")
	_check(FileAccess.file_exists(profile.save_path + ".bak"), "Second save retains last valid backup")
	_write(profile.save_path, "{broken json")
	var recovered = Progression.new()
	recovered.save_path = profile.save_path
	recovered.load_save()
	_check(recovered.load_status == "recovered", "Corrupt primary recovers the backup")
	_check(recovered.badges() == 3, "Recovered profile has last durable backup balance")
	_check(FileAccess.file_exists(profile.save_path + ".corrupt"), "Damaged save is retained")
	var restarted = Progression.new()
	restarted.save_path = profile.save_path
	restarted.load_save()
	_check(restarted.load_status == "loaded" and restarted.badges() == 3, "Recovery repairs the primary")


func _test_corrupt_and_newer_saves() -> void:
	var profile = _profile("malformed")
	_write(profile.save_path, JSON.stringify({
		"version": 1, "badges": -99, "unlocked": ["retriever", "malinois"],
		"best_stars": 7, "clears": 0, "rewarded_runs": [],
	}))
	profile.load_save()
	_check(profile.load_status == "reset" and profile.badges() == 0, "Invalid values reset conservatively")
	_check(profile.unlocked_dogs() == ["retriever"], "Corruption cannot unlock a dog")
	_check(profile.save(), "Fresh state replaces corrupt input only after preserving it")
	_check(FileAccess.file_exists(profile.save_path + ".corrupt"), "Corrupt original is not lost")
	var future = _profile("future")
	var future_text: String = JSON.stringify({"version": 999, "badges": 99})
	_write(future.save_path, future_text)
	future.load_save()
	_check(future.load_status == "unsupported", "Future schema is detected")
	_check(not future.save(), "Future save cannot be overwritten")
	_check(not future.record_victory(20, "future_run").saved, "Rewards do not overwrite a future save")
	_check(FileAccess.get_file_as_string(future.save_path) == future_text, "Newer save bytes stay unchanged")
	var malformed = _profile("duplicate_runs")
	_write(malformed.save_path, JSON.stringify({
		"version": 1, "badges": 4, "unlocked": ["retriever"],
		"best_stars": 3, "clears": 2, "rewarded_runs": ["same", "same"],
	}))
	malformed.load_save()
	_check(malformed.load_status == "reset", "Duplicate stored run IDs fail validation")


func _test_failed_mutation_rolls_back() -> void:
	var profile = _profile("rollback")
	profile.record_victory(20, "earned")
	var original_path: String = profile.save_path
	var blocking_directory: String = TEST_DIRECTORY.path_join("directory_not_file")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocking_directory))
	profile.save_path = blocking_directory
	_check(not profile.unlock("dachshund", 2), "Failed save rejects unlock")
	_check(profile.badges() == 3 and not profile.unlocked_dogs().has("dachshund"), "Failed unlock rolls back money and dog")
	var reward: Dictionary = profile.record_victory(20, "not_saved")
	_check(not reward.saved and reward.earned == 0 and profile.badges() == 3, "Failed reward rolls back balance")
	profile.save_path = original_path
	_check(profile.record_victory(20, "not_saved").earned == 1, "Failed reward can be retried after storage recovers")
