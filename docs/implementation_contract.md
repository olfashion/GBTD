# First playable implementation contract

Godot 4.7.2, GDScript, 3D Compatibility renderer. Root owns `project.godot`,
`scenes/main.tscn`, `scripts/main.gd`, `scripts/game_ui.gd` and integration.
Do not modify files owned by another contributor without coordination.

## Combat simulation (`scripts/combat_sim.gd`)

Extends RefCounted; pure simulation, no disk access or scene tree requirement.
Data lives in `data/dogs.json`, `data/enemies.json`, `data/level_01.json`.
Use explicit preloads/loads to avoid global class import order problems.

Public fields:

- `dogs`, `enemies`, `projectiles`, `hazards`, `effects`: Arrays of Dictionaries.
- `bones: int`, `lives: int`, `wave: int`, `wave_total: int`, `time: float`.
- `phase: String`: `build`, `wave`, `victory`, `defeat`.
- `path_points: Array` of Vector2 world X/Z points, `pads: Array` of Vector2.
- `dog_defs`, `enemy_defs`: Dictionaries keyed by breed/type ID.
- `unlocked: Array`: currently available dog IDs.

API: `reset(available: Array = ["retriever"])`, `place_dog(breed: String,
pad_index: int) -> bool`, `upgrade_dog(id: int) -> bool`, `sell_dog(id: int)
-> int`, `set_target_mode(id: int, mode: String)`, `start_wave() -> bool`,
`step(dt: float)`, `dog_at_pad(pad_index: int) -> Dictionary`,
`get_dog(id: int) -> Dictionary`, `upgrade_cost(id: int) -> int`,
`consume_events() -> Array`.

Dogs include `id`, `breed`, `pad`, `pos: Vector2`, `anchor: Vector2`, `hp`,
`max_hp`, `armor`, `max_armor`, `level` (1-3), `state` (`active`, `exhausted`),
`recovery_left`, `range`, `target_id`, `target_mode`, `attack_anim` (0-1 pulse).
Enemies include `id`, `type`, `pos: Vector2`, `direction: Vector2`, `hp`,
`max_hp`, `armor`, `progress` (distance), `slow`, `hit_flash` (0-1).
Projectiles include `id`, `pos: Vector2`, `height`, `kind`.
Hazards include `id`, `pos: Vector2`, `radius`, `life`, `kind`.
Effects include `id`, `pos: Vector2`, `kind`, `life`, `max_life`, `radius`.

Dog definition fields: `name`, `role`, `description`, `cost`, `unlock_cost`,
`hp`, `armor`, `damage`, `interval`, `range`, `recovery`, `color` (HTML).
IDs: retriever (150 bones, free), dachshund (190 bones, 2 badges), bulldog
(260 bones, 3 badges), malinois (1500 bones, 8 badges, highest price).
Start with 450 bones and 20 puppy lives. Ten waves. Normal + 2x speed.
Active defense: enemies stay on their path and attack nearby dogs. Dogs
exhaust at zero HP, become untargetable, then automatically recover with
70% HP and 2 seconds protection. Armor is absorption, not flat reduction.

## 3D view (`scripts/yard_view.gd`, `scripts/models.gd`)

`yard_view.gd` extends Node3D. API:
`setup(sim)` builds ground, path, pads, props, lighting, camera, puppy;
`sync(sim, delta: float)` updates actor meshes and animations;
`pick_pad(screen_position: Vector2) -> int` uses camera projection;
`set_selection(pad_index: int, radius: float, valid: bool = true)`;
`clear_selection()`; `set_preview(breed: String)` (optional);
`capture()` is not required. Expose `camera: Camera3D`.
World is Vector2(x,z); all map visuals use simulation path/pads.
Create a colorful, polished, low-poly Hill Country diorama: limestone,
live oaks, prickly pear, fence, bluebonnets, doghouse. Recognizable dogs,
ants, beetles, spiders, scorpion boss. Malinois must wear a dark tactical
vest and have black muzzle/ears. Scene is all original procedural meshes.
No game rules or UI in renderer. Landscape 1440x900 base viewport; reserve
top 95 and bottom 200 pixels for UI. Scene should stay readable there.

## Progression (`scripts/progression.gd`)

Extends RefCounted; `save_path` overridable for tests, default
`user://good_boys_save.json`. API: `load_save()`, `save() -> bool`,
`unlocked_dogs() -> Array`, `badges() -> int`, `best_stars() -> int`,
`unlock(breed: String, cost: int) -> bool`,
`record_victory(lives: int, run_id: String) -> Dictionary`.
Result has `earned`, `first_clear`, `stars`, `total`. Award 1 badge per win,
plus 2 on first clear. Stars 3 for 20 lives, 2 for >=12, else 1. Reject
duplicate awards for same run_id. Retriever unlocked on fresh save. No
microtransactions. Validate/migrate corrupt inputs conservatively; atomic
save, preserve backup. Caller refreshes sim.unlocked after unlocking.

## Input and UX

Tap/click a kennel dog, then a placement pad; tap an occupied pad to select,
upgrade, switch target priority or sell. Manual Start Wave. Pause, 1x/2x,
retry, help, kennel unlock screen, and victory/defeat overlays. Pausing
stops all simulation timers. Mobile lifecycle auto-pauses and saves progress.

## Validation

Godot `--headless --path . --editor --import --quit` then headless behavior
tests for economy, unlock persistence, exhaustion, victory/defeat and waves.
Run visual QA using native desktop if available. Export presets iOS,
Android and desktop/web for QA if feasible. No signing secrets in repo.
