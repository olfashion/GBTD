# Good Boys: Backyard Defense

A playful 3D tower defense game set on the edge of the Texas Hill Country.
Neighborhood dogs defend a puppy from backyard critters. Dogs can become
exhausted, but they never die: a short nap puts them back in the fight.

**First playable — v0.1.0.** One complete backyard level, built with
**Godot 4.7.2 and GDScript**. **iPhone is the first target**, with Android
support retained in the same project for later work. The source runs in
the Godot editor on your Mac. The iOS handoff is ready for your real Apple
Team ID and Xcode signing; a signed iPhone app still needs that local step.

## Play on your Mac

1. Install the standard, non-.NET [Godot 4.7.2 editor](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).
2. Extract the delivered source ZIP and open its `GBTD` folder. Once the
   source is pushed to GitHub, you can instead clone the project:

   ```bash
   git clone https://github.com/olfashion/GBTD.git
   cd GBTD
   ```

3. Open Godot, click **Import**, and select `project.godot`.
4. Press **F5** to run the game.

If Godot is on your shell path, launch directly with:

```bash
godot --path .
```

No third-party asset downloads, account login, or game server are required.

## First level: the backyard

- Defend the puppy through ten waves, starting with **20 lives** and
  **450 Bones**.
- Place dogs on marked pads beside the winding path.
- Fire ants, beetles, wolf spiders, and the final scorpion challenge the pack.
- Upgrade dogs during play, choose target priority, and sell a dog to
  recover part of its investment.
- Wildlife attacks nearby active dogs. Exhausted dogs retreat to their
  placement anchors, recover automatically, and briefly resist damage on return.
- Pause at any time or use 2× speed. Start each wave when ready.

### Controls

| Action | Touch or mouse |
| --- | --- |
| Place a dog | Select its kennel card, then tap an empty placement pad |
| Inspect a dog | Tap its occupied pad |
| Upgrade, change targeting, or sell | Use the selected dog's controls |
| Launch the next wave | Tap **Start wave** |
| Unlock a breed | Open the **Kennel** and spend earned Paw Badges |
| Try again | Use the result screen's replay button |

The game is designed for landscape play. Desktop mouse input and mobile
touch share the same controls.

## Earn your pack

There are two separate currencies. **Bones** are earned and spent during a
level and reset on replay. **Paw Badges** are permanent victory rewards used
to unlock breeds. They are saved on the device.

| Dog | Attack and role | Unlock | In-level cost |
| --- | --- | ---: | ---: |
| Golden Retriever | Tennis balls; general ranged damage | Starter | 150 Bones |
| Dachshund | Poop traps; path control | 2 Paw Badges | 190 Bones |
| Bulldog | Bark shockwaves; control and protection | 3 Paw Badges | 260 Bones |
| Belgian Malinois | Fast melee assault; dark tactical vest | 8 Paw Badges | 1,500 Bones |

The first victory gives **3 Paw Badges**: one for completing the level and
two as a first-clear bonus. Each later victory gives one. The first clear
therefore unlocks a choice between the Dachshund and Bulldog. Defeat grants
no badges. The Malinois is the most expensive dog to unlock and to deploy.

Your best performance earns stars: three for preserving all 20 lives,
two for finishing with at least 12, and one for any other victory.
Replay the backyard to earn more badges and try another pack composition.

## Play on iPhone

Follow [the iPhone build and playtest guide](docs/MOBILE.md) to export through
Godot, open the generated project in Xcode, and install it on your iPhone.
You need Xcode on your Mac and your real ten-character Apple Team ID entered
locally. The preset uses `com.olfashion.goodboys`, targets iPhone, and leaves
signing to Xcode. A Personal Team can be used for your own-device testing.

The source and iOS configuration are present; the export preflight stopped
at the missing Team ID. No signed IPA or physical-iPhone validation is
claimed. The Web preset also supports a browser preview of the same game
while native signing is being configured.

The [private browser playtest](https://good-boys-iphone-playtest.kyle-ambrosi.chatgpt.site/)
is available through the owner's ChatGPT account. Open it in Safari on an
iPhone and turn the phone sideways. This browser export has not yet been
validated on a physical iPhone; native installation still follows the
build guide above.

Android remains a secondary target. An ARM64 development APK was exported
and its signatures, alignment, and packaged data were verified; no physical
Android device was tested. The first playable is an offline game, and saves
stay on the device/browser where you play.

## Source layout

| Location | Purpose |
| --- | --- |
| `project.godot`, `scenes/main.tscn` | Engine configuration and entry scene |
| `scripts/main.gd`, `scripts/game_ui.gd` | Game flow, input, and interface |
| `scripts/combat_sim.gd` | Scene-independent combat and wave simulation |
| `scripts/yard_view.gd`, `scripts/models.gd` | Original procedural 3D map and characters |
| `scripts/progression.gd` | Saved unlocks, badges, and star records |
| `data/*.json` | Dog stats, enemy stats, placements, and wave composition |
| `tests/` | Headless gameplay and persistence checks |

Balance is data driven. Begin with the three JSON files in `data/` when
changing dog prices, enemy health, or wave composition.

## Validate changes

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_combat.gd
godot --headless --path . --script tests/test_progression.gd
godot --headless --path . --script tests/test_integration.gd
godot --headless --path . --quit-after 120
```

GitHub Actions repeats import, behavioral tests, and a main-scene smoke
test with the pinned engine version. Rendering and physical-device testing
are separate checks; the headless workflow does not establish frame rate,
touch ergonomics, or store readiness.

The initial validation passed 130 checks: 48 combat, 40 progression, and
42 scene/interface checks. This includes a complete ten-wave victory using
only the starter Retriever and phone-sized control geometry.

## Save behavior

`user://good_boys_save.json` records badges, unlocked dogs, best stars, and
rewarded run IDs. Reward IDs prevent the same victory from paying twice.
Unlocks and rewards only complete after a successful save. Writes use a
temporary file and replacement, retaining the previous valid save as a
backup. A damaged save is retained as `.corrupt`; a newer, unsupported save
is left untouched. No active-wave resume or cloud save is included yet.

## Next milestones

The first playable contains one level, four breeds, and simple three-level
upgrades. Additional maps, the broader dog roster, three specialization
paths per breed, final character art/audio, device performance tuning, and
store submission remain future work. The procedural characters and
environment are original first-pass game assets, ready to replace or refine.
