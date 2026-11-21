extends RefCounted
## Permanent campaign rewards. Bones belong to CombatSim; Paw Badges live here.
## Mutations succeed only if their replacement save reaches disk.

const SAVE_VERSION: int = 1
const DEFAULT_PATH: String = "user://good_boys_save.json"
const DOG_DATA_PATH: String = "res://data/dogs.json"

var save_path: String = DEFAULT_PATH
var last_error: String = ""
var load_status: String = "new"
var _read_only: bool = false
var _state: Dictionary = _fresh_state()


static func _fresh_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"badges": 0,
		"unlocked": ["retriever"],
		"best_stars": 0,
		"clears": 0,
		"rewarded_runs": [],
	}


func load_save() -> void:
	last_error = ""
	_read_only = false
	_state = _fresh_state()
	load_status = "new"
	if not FileAccess.file_exists(save_path):
		# An interrupted replacement can leave a backup without a primary.
		var recovered: Dictionary = _read_valid(save_path + ".bak")
		if not recovered.is_empty():
			_state = recovered
			load_status = "recovered"
			save()
		return
	var parsed: Variant = _read_json(save_path)
	if parsed is Dictionary and _whole_number(parsed.get("version", 0)):
		if int(parsed.get("version", 0)) > SAVE_VERSION:
			_read_only = true
			load_status = "unsupported"
			last_error = "This save was created by a newer game version. It has been preserved."
			return
	var validated: Dictionary = _validate(parsed)
	if not validated.is_empty():
		_state = validated
		load_status = "loaded"
		return
	var backup: Dictionary = _read_valid(save_path + ".bak")
	if not backup.is_empty():
		_state = backup
		load_status = "recovered"
		save()
		return
	load_status = "reset"
	last_error = "The save could not be read. A fresh profile is active; the damaged file is preserved."


func badges() -> int:
	return int(_state.badges)


func unlocked_dogs() -> Array:
	return _state.unlocked.duplicate()


func best_stars() -> int:
	return int(_state.best_stars)


func unlock(breed: String, cost: int) -> bool:
	last_error = ""
	if _read_only:
		last_error = "A newer save cannot be changed by this version."
		return false
	var catalog: Dictionary = _dog_catalog()
	if not catalog.has(breed) or not catalog[breed] is Dictionary:
		last_error = "Unknown dog."
		return false
	var required: Variant = catalog[breed].get("unlock_cost", -1)
	if not _whole_number(required) or int(required) < 0 or cost != int(required):
		last_error = "The unlock price does not match the dog catalog."
		return false
	if breed in _state.unlocked:
		last_error = "This dog is already unlocked."
		return false
	if cost > badges():
		last_error = "Earn more Paw Badges by completing the backyard."
		return false
	var before: Dictionary = _state.duplicate(true)
	_state.badges = badges() - cost
	_state.unlocked.append(breed)
	if not save():
		_state = before
		return false
	return true


func record_victory(lives: int, run_id: String) -> Dictionary:
	last_error = ""
	if lives < 1 or lives > 20 or run_id.strip_edges().is_empty() or run_id.length() > 128:
		last_error = "Only a valid completed run can earn rewards."
		return _reward_result(0, false, 0, false)
	var stars: int = 3 if lives == 20 else (2 if lives >= 12 else 1)
	if run_id in _state.rewarded_runs:
		var duplicate: Dictionary = _reward_result(0, false, stars, true)
		duplicate["duplicate"] = true
		return duplicate
	if _read_only:
		last_error = "A newer save cannot be changed by this version."
		return _reward_result(0, false, stars, false)
	var before: Dictionary = _state.duplicate(true)
	var first_clear: bool = int(_state.clears) == 0
	var earned: int = 3 if first_clear else 1
	_state.badges = badges() + earned
	_state.best_stars = maxi(best_stars(), stars)
	_state.clears = int(_state.clears) + 1
	_state.rewarded_runs.append(run_id)
	if not save():
		_state = before
		return _reward_result(0, false, stars, false)
	return _reward_result(earned, first_clear, stars, true)


func _reward_result(earned: int, first_clear: bool, stars: int, saved: bool) -> Dictionary:
	return {
		"earned": earned,
		"first_clear": first_clear,
		"stars": stars,
		"total": badges(),
		"saved": saved,
		"error": last_error,
	}


func save() -> bool:
	if _read_only:
		last_error = "A newer save cannot be overwritten by this version."
		return false
	if _validate(_state).is_empty():
		last_error = "Progress data failed validation. The existing save is unchanged."
		return false
	var absolute: String = ProjectSettings.globalize_path(save_path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		last_error = "The save directory could not be created."
		return false
	var temporary: String = absolute + ".tmp"
	var output: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if output == null:
		last_error = "Progress could not be saved. Check available storage."
		return false
	output.store_string(JSON.stringify(_state, "\t"))
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "Progress could not be written. The previous save is unchanged."
		return false
	# Back up only a valid primary; never rotate corruption over a good backup.
	if FileAccess.file_exists(absolute):
		if not _read_valid(absolute).is_empty():
			var backup_temporary: String = absolute + ".bak.tmp"
			var copy_error: Error = DirAccess.copy_absolute(absolute, backup_temporary)
			if copy_error == OK:
				copy_error = DirAccess.rename_absolute(backup_temporary, absolute + ".bak")
			if copy_error != OK:
				DirAccess.remove_absolute(temporary)
				last_error = "The backup could not be saved. Progress was not changed."
				return false
		elif not FileAccess.file_exists(absolute + ".corrupt"):
			if DirAccess.copy_absolute(absolute, absolute + ".corrupt") != OK:
				DirAccess.remove_absolute(temporary)
				last_error = "The damaged save could not be preserved. Progress was not changed."
				return false
	# Same-directory rename replaces the file only after the full write succeeds.
	var replace_error: Error = DirAccess.rename_absolute(temporary, absolute)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "Progress could not be replaced. The previous save is unchanged."
		return false
	last_error = ""
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var input: FileAccess = FileAccess.open(path, FileAccess.READ)
	if input == null or input.get_length() > 16 * 1024 * 1024:
		return null
	var parser: JSON = JSON.new()
	if parser.parse(input.get_as_text()) != OK:
		return null
	return parser.data


func _read_valid(path: String) -> Dictionary:
	return _validate(_read_json(path))


func _dog_catalog() -> Dictionary:
	var parsed: Variant = _read_json(DOG_DATA_PATH)
	return parsed if parsed is Dictionary else {}


func _validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	for key: String in ["version", "badges", "best_stars", "clears"]:
		if not raw.has(key) or not _whole_number(raw[key]):
			return {}
	if int(raw.version) != SAVE_VERSION or int(raw.badges) < 0 or int(raw.badges) > 1000000000:
		return {}
	if int(raw.best_stars) < 0 or int(raw.best_stars) > 3 or int(raw.clears) < 0:
		return {}
	if not raw.get("unlocked") is Array or not raw.get("rewarded_runs") is Array:
		return {}
	if raw.rewarded_runs.size() != int(raw.clears):
		return {}
	if (int(raw.clears) == 0) != (int(raw.best_stars) == 0):
		return {}
	var catalog: Dictionary = _dog_catalog()
	var unlocked: Array = []
	for breed: Variant in raw.unlocked:
		if not breed is String or not catalog.has(breed) or breed in unlocked:
			return {}
		unlocked.append(breed)
	if not "retriever" in unlocked:
		return {}
	var rewarded: Array = []
	var seen: Dictionary = {}
	for run_id: Variant in raw.rewarded_runs:
		if not run_id is String or run_id.strip_edges().is_empty() or run_id.length() > 128:
			return {}
		if seen.has(run_id):
			return {}
		seen[run_id] = true
		rewarded.append(run_id)
	return {
		"version": SAVE_VERSION,
		"badges": int(raw.badges),
		"unlocked": unlocked,
		"best_stars": int(raw.best_stars),
		"clears": int(raw.clears),
		"rewarded_runs": rewarded,
	}


static func _whole_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and floorf(value) == value
