# iPhone first: build and playtest

**iPhone is the first target.** Android remains a supported export path for
later work. Both platforms use the same Godot project, gameplay, and local
save format. The first level is designed for landscape play with the
Compatibility renderer.

## Current build status

| Target | Verified now | Still required |
| --- | --- | --- |
| iPhone | Godot source, iOS preset, official export template, and export preflight | Real Apple Team ID, Xcode build/signing, installation, and physical-device playtest |
| Desktop | Playable Godot project and automated gameplay checks | Device-specific rendering/performance testing |
| Android, secondary | ARM64 development APK export, APK v2/v3 signature verification, alignment, and packaged data checks | Physical-device installation and gameplay validation |

The iOS export was attempted with **Export Project Only** enabled. Godot
4.7.2 stopped with **“App Store Team ID not specified.”** No placeholder
team ID or signing credential was invented, and no iOS IPA is claimed.
Project-only export skips the Xcode build, but the engine still requires
the real team identifier when configuring the generated project.

## Fastest native iPhone handoff

You need your **Mac, Xcode, iPhone, and an Apple Account configured in
Xcode**. The remaining project-specific input is your actual **ten-character
Apple Team ID**. Keep the selected bundle identifier,
`com.olfashion.goodboys`, or replace it if Xcode says it is unavailable.

1. Install the standard, non-.NET **Godot 4.7.2** editor and Xcode on your
   Mac. Open Xcode and finish its first-run setup.
2. In **Xcode → Settings → Apple Accounts**, sign in locally and select your
   development team. A Personal Team can be used to test on your own device;
   paid program membership is for distribution and additional capabilities.
3. Extract the source ZIP (or clone the populated repository), import
   `project.godot` in Godot, and press **F5**
   to confirm that the backyard opens on your Mac.
4. Open **Editor → Manage Export Templates** and install
   **4.7.2.stable** templates. The editor and templates must match.
5. Open **Project → Export → iOS**. Enter your actual **App Store Team ID**
   and confirm **Bundle Identifier** is `com.olfashion.goodboys`.
   The preset already selects iPhone, iOS 16 or later, and
   **Export Project Only**.
6. Create a fresh `builds/ios` directory, then export a debug project using
   the name `good_boys`. Avoid spaces in the exported project's filename.
7. Open the generated `.xcodeproj`. In **Signing & Capabilities**, select
   your team and enable **Automatically manage signing**. Connect and
   unlock the iPhone, choose it as the run destination, and follow Xcode's
   pairing/Developer Mode prompts.
8. Press **Run** in Xcode. It builds, signs, and installs the app on the
   connected phone. Turn the phone sideways and play the first level.

If Godot is on your shell path, step 6 can be run after entering the real
team ID in the preset:

```bash
mkdir -p builds/ios
godot --headless --path . --export-debug "iOS" builds/ios/good_boys.zip
```

Godot can prepare project files without running Xcode, but compiling,
signing, and installing the native iPhone app require the Apple toolchain.
This workspace has no Apple signing identity or connected iPhone.

### Finding the Team ID

For a developer-program team, use the Team ID shown in the Apple developer
account's membership details. For a Personal Team, use the
`DEVELOPMENT_TEAM` value from an Xcode project configured with that team.
It is the ten-character identifier, not your email address or display name.
Enter it on your Mac; no Apple password or certificate needs to be sent in chat.

A free Personal Team can install a development build on your own iPhone,
but its provisioning expires periodically and requires rebuilding/reinstalling.
TestFlight and App Store distribution require Apple Developer Program
membership and distribution setup. Neither is necessary for this first
personal-device playtest.

## iPhone browser playtest

The **Web** preset exports the same game as a browser build, with threading
turned off. An HTTPS-hosted Web build is a useful early way to test touch
controls and the landscape layout on iPhone while native signing is set up.
It is a separate preview of the game, not an installed native iOS app.

```bash
mkdir -p builds/web
godot --headless --path . --export-release "Web" builds/web/index.html
```

Serve the entire output directory together. Opening `index.html` directly
as a local file will not load the game correctly. The browser requires
WebAssembly/WebGL 2 support, and real iPhone Safari performance still needs
testing. Browser saves are stored for that browser/site and do not transfer
to the native app.

For a static host with a 25 MiB per-file limit, prepare and verify the hosted
preview after exporting. This preserves the original game binary while
serving it in smaller ordered parts; it also adds the branded loader and
portrait rotation hint.

```bash
python3 tools/prepare_web_preview.py --input builds/web --output builds/web-hosted
node tools/verify_web_preview.mjs builds/web-hosted
```

Publish the complete `builds/web-hosted` directory. Run both commands again
after every fresh Web export so the preview matches the current game.

## Shared export configuration

Export presets are tracked in `export_presets.cfg`; signing material and
installed SDKs stay on the developer's machine. The iOS preset is listed
first to match the platform priority. The `data/*.json` include filter in
every preset is required: plain JSON game data must be shipped even with
**All resources** selected.

Keep the real Team ID and local signing changes out of commits while
iterating. The current iOS preset targets iPhone with an iOS 16 deployment
floor. iPad support and a broader supported-device list need separate layout
and hardware validation.

## Android development APK

Godot's Android guide specifies **OpenJDK 17** and an Android SDK setup.
Install Android Studio and its SDK components, then follow the exact
package requirements in the linked guide for the engine version in use.

1. Install OpenJDK 17 and Android Studio. Complete Android Studio's first-run
   SDK setup.
2. In Godot's **Editor Settings → Export → Android**, set **Java SDK Path**
   and **Android SDK Path**. On a Mac the SDK is commonly installed under
   `~/Library/Android/sdk`.
3. Select **Project → Export → Android**. The included preset is a
   development APK targeting ARM64 phones, with package ID
   `com.olfashion.goodboys` and version `0.1.0`.
4. Export with **Export With Debug** enabled. Godot uses its configured
   local debug signing setup. If no debug keystore is configured, follow
   the editor's export validation instructions to create/configure one.
5. Enable Developer Options and USB debugging on the phone, connect it,
   and confirm that `adb devices` lists it.
6. Install the generated APK:

   ```bash
   adb install -r builds/android/good-boys.apk
   ```

After the editor paths are configured, the equivalent export is:

```bash
godot --headless --path . --export-debug "Android" builds/android/good-boys.apk
```

The ARM64 preset targets physical phones. For an x86_64 Android emulator,
enable that architecture in a separate local export preset.

### Build an APK with GitHub Actions

The repository also includes a manual **Build Android debug APK** workflow.
Open the repository's **Actions** tab, select that workflow, choose **Run
workflow**, and wait for a successful run. Download its
`good-boys-android-debug` artifact, extract the APK, and install it on an
ARM64 Android device. A failed run produces no verified APK.

Each workflow run creates a temporary development signing key. To replace
an APK from an earlier run, you may need to uninstall the previous build
first because the keys differ; that can remove its local progression.
Use a persistent, securely stored development key for regular device testing.
This workflow does not publish to Google Play.

### Google Play release

Google Play distribution uses an Android App Bundle (AAB). Install Godot's
Android Gradle build template, enable Gradle build, select AAB, and configure
release signing. Store signing keys outside the repository and supply
credentials through local editor configuration or Godot's documented
environment variables. Review the current target SDK and store policies at
submission time; the development APK configuration is not a release checklist.

## Save and lifecycle checks on a device

- Complete the backyard, unlock a dog, close and reopen the app, and confirm
  the badge balance and unlock survive.
- Background the app during a wave; it should pause rather than advance
  combat while hidden. Returning should allow an intentional resume.
- Test at least one narrow and one wide landscape screen for readable
  controls, safe areas, and placement accuracy.
- Check a large final wave and the Malinois's melee effect on a lower-end
  target device. Headless tests do not measure rendering performance.
- Clearing application data or uninstalling can remove the local save;
  this first version has no account or cross-device save service.

## Official references

- [Godot 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)
- [Godot iOS export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)
- [Pinned 4.7.2 Apple exporter: required Team ID and project-only behavior](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform_apple_embedded.cpp)
- [Apple account and Personal Team setup](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Xcode device signing and running](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Godot Web export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Godot Android export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)
- [Android Gradle builds](https://docs.godotengine.org/en/stable/tutorials/export/android_gradle_build.html)
