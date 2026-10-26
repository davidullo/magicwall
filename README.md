<p align="center">
  <img src="docs/icon.png" width="144" alt="MagicWall app icon">
</p>

<h1 align="center">MagicWall</h1>

<p align="center">
  <b>Local video wallpapers for macOS.</b><br>
  <em>Native, lightweight and completely local.</em>
</p>

<p align="center">
  <a href="https://github.com/davidullo/magicwall/releases/latest"><img src="https://img.shields.io/badge/Download-0A84FF?style=flat&logo=apple&logoColor=white" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-5E5CE6?style=flat&labelColor=1c1c1e" alt="macOS 15 or later">
  <img src="https://img.shields.io/badge/SwiftUI-FF9F0A?style=flat&logo=swift&logoColor=white&labelColor=1c1c1e" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-30D158?style=flat&labelColor=1c1c1e" alt="MIT license"></a>
</p>

---

## ⬇️ Download

The latest release is **signed with a Developer ID and notarized by Apple**, so
it opens without Gatekeeper warnings.

1. Download `MagicWall-<version>.dmg` from the
   [releases page](https://github.com/davidullo/magicwall/releases/latest).
2. Open it and drag **MagicWall** into *Applications*.
3. On first launch the app creates its local library — import your videos and
   set them as wallpapers.

Requires **macOS 15 or later**. Builds are universal (Apple Silicon and Intel).

## ✨ Features

- **Local library** — drag & drop import of files and folders, automatically
  generated posters, categories, favorites, search and rename.
- **Fullscreen preview** — browse a video before applying it, with quick
  actions (play, rename, favorites, categories).
- **Multi-monitor** — a different video for each display; assignments survive
  restarts and are restored automatically.
- **Lock screen** (macOS 26+) — MagicWall ships a wallpaper extension, so macOS
  itself can play your library on the lock screen, with the native unlock
  transition and no grey flash. Pick MagicWall under "Screen Saver…" in System
  Settings → Wallpaper; Settings → General shows whether it is active and takes
  you straight to that pane. On macOS 15–25 the extension is simply never
  loaded and the app animates the desktop only.
- **Favorites rotation** — auto-swap your favorite wallpapers every 1–60
  minutes: the same clip on every display, or a different one per display;
  every favorite is shown once per cycle before repeating.
- **Starter wallpapers** — on first launch MagicWall offers five hand-picked 4K
  clips (Dreamscape, Clover Rainbow, Aurora Forest, Cherry Blossom Spring,
  Colorful Underwater Scene) in two quality tiers: **High quality** (~143 MB,
  x265 encodes from the 4K masters) and **Compact** (~57 MB, for slow
  connections). They are downloaded only if you accept, can be skipped, and can
  be removed or re-downloaded in the other quality later from Settings.
- **Power policy** — the wallpaper keeps playing on battery: automatic pausing
  is available (and off by default for the battery rule) for Low Power Mode,
  thermal pressure, screen lock or occluded desktop, with recovery after
  sleep/wake. When a rule stops it, the menu bar icon and a one-off notice say
  why, and every rule can be toggled in Settings → Playback.
- **Menu bar** — pause, shuffle, favorites, rotation and stop without opening
  the window.
- **Themes** — editable design tokens (colors, corner radii, gradients) plus
  light/dark appearance.
- **English and Italian** — the UI follows the system language.
- **Automatic updates** — the app checks the official GitHub releases once a
  day, verifies the signature of the download and installs it in place when
  you say so (checks can be turned off in Settings → About).
- **Completely local** — no accounts, no telemetry: your videos never leave
  your Mac. The only network requests are the daily update check and the
  optional starter-wallpaper download, which you can skip or remove.

## 🚀 Getting started

1. Open MagicWall → "+" (or drag MP4/MOV files and folders into the window).
2. Play a card to open the preview, then "Play as wallpaper" to apply it to
   every screen (or right-click → "Set on Screen" for a single monitor).
3. The app stays in the menu bar: pause, shuffle, favorites, stop. In
   Settings → Playback you can tune the automatic pauses (battery, Low Power
   Mode, thermal pressure, screen lock, hidden desktop).
4. Right-click a card (or use the pencil button in the preview) → **Rename** to
   give imported videos a custom title.
5. Per-screen assignments survive restarts and are restored automatically.
6. Open **Favorites**: the bar at the top rotates your favorite wallpapers
   automatically on every screen, with a 1–60 minute interval you choose.

## 📊 Project status

- **M1** (foundation): ✅ project, database schema, video import, posters, library
- **M2** (engine): ✅ per-screen desktop-level windows, gapless looping,
  per-monitor persistence, restore on launch, power policy, wake recovery
- **M3** (library UI): ✅ top bar + hero + carousels + Explore + fullscreen preview
- **M4** (hardening/release): ✅ power policy, E2E tests, themes, i18n,
  Developer ID signing + Apple notarization, Sparkle auto-updates, release
  script; ⏳ HEVC transcode (todo)
- **Lock screen** (macOS 26+): ✅ `com.apple.wallpaper` provider extension,
  library mirror into the extension container, status card in Settings → General
- **M5** (community): future

## 🖥️ Requirements

**To use the app**

- macOS 15 or later (developed and tested on macOS 27)
- for the lock screen wallpaper: macOS 26 or later — on older systems the
  extension is ignored and the app animates the desktop only

**To build**

- Xcode 27.x with the macOS SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- for release DMGs: [dmgbuild](https://github.com/dmgbuild/dmgbuild) 1.6.7+
  (`pipx install "dmgbuild>=1.6.7"`)

## 🛠️ Build & run

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# generate the Xcode project from project.yml (project.yml is the source of
# truth; never edit MagicWall.xcodeproj, it is generated and gitignored)
xcodegen generate

xcodebuild -project MagicWall.xcodeproj -scheme MagicWall \
  -configuration Debug -derivedDataPath /tmp/mw-dd build

open /tmp/mw-dd/Build/Products/Debug/MagicWall.app
```

Run the core tests:

```bash
cd Packages/MagicWallCore && swift test
```

## 📦 Release

One command does the whole release — version bump, tests, commit + push,
site placeholder sync, universal build, Developer ID signing, notarization,
DMG/ZIP/dSYM, signed appcast, GitHub release and feed verification:

```bash
./Scripts/publish            # next patch: 0.2.0 → 0.2.1
./Scripts/publish minor      # next feature release: 0.2.0 → 0.3.0
./Scripts/publish major      # 0.2.0 → 1.0.0
./Scripts/publish 1.2.3      # exact version
./Scripts/publish --dry-run  # print the plan without touching anything
```

The signing identity is detected from the keychain, the notary profile
defaults to `magicwall` (create it once with
`xcrun notarytool store-credentials magicwall --apple-id ... --team-id ...`)
and the build number is the current one plus one. Without `--yes` the release
starts after a short countdown, so a wrong invocation can be aborted with
Ctrl-C. Partial runs: `--skip-tests`, `--with-e2e`, `--no-publish`,
`--no-push`, `--no-commit`, `--build N`.

The script also updates the version placeholders in `site/` and invalidates
the landing page's release cache. Vercel redeploys the site automatically from
the push to `main`, and the release verifies the live page afterwards.

For a local build only (no git, no publishing):

```bash
./Scripts/release.sh            # universal build (arm64 + x86_64)
./Scripts/release.sh --native   # this Mac's architecture only, faster
```

The styled DMG installer window is built with
[dmgbuild](https://github.com/dmgbuild/dmgbuild) (1.6.7 or later):

```bash
pipx install "dmgbuild>=1.6.7"
```

The artwork source and layout specs live in
[`Scripts/dmg/`](Scripts/dmg/README.md); regenerate the background with
`./Scripts/dmg/render-background.sh`.

Artifacts are written to `dist/`:

- `MagicWall-<version>.dmg` (branded installer window + Applications drop target)
- `MagicWall-<version>.zip`
- `MagicWall-<version>.dSYM.zip` (symbols for crash reports)
- `appcast.xml` (Developer ID builds only — the Sparkle update feed)
- `SHA256SUMS.txt`

Local builds are ad-hoc signed: they run on this Mac, but other Macs will be
blocked by Gatekeeper because they are not notarized. Developer ID builds
(`SIGN_IDENTITY="Developer ID Application: ..."`) are notarized automatically
by the release script.

### Auto-updates (Sparkle)

Updates are delivered by [Sparkle 2](https://sparkle-project.org) and are only
possible on Developer ID builds (Sparkle validates the running app's signature
before installing anything). The release script:

1. builds with the Developer ID so `Sparkle.framework`, its XPC services and
   the app all carry the same signature;
2. signs the ZIP with the EdDSA key and generates `dist/appcast.xml`;
3. `./Scripts/publish` (or `release.sh --publish`) attaches the appcast to the
   release, which serves the feed at:

   `https://github.com/davidullo/magicwall/releases/latest/download/appcast.xml`

One-time setup (already done for this repository — public key lives in
`project.yml` as `SUPublicEDKey`):

```bash
# Sparkle's tools are downloaded with the package under
# build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/
./generate_keys            # creates the EdDSA key in the login keychain
./generate_keys -x key.txt # export the private key for a safe backup
```

Back up the private key: **without it you cannot sign future updates**.
`generate_appcast` reads it from the keychain; CI can pass
`SPARKLE_ED_KEY_FILE` instead.

Rules for every release:

- `./Scripts/publish` handles the build number: Sparkle compares
  `CURRENT_PROJECT_VERSION`, and the script always increments it;
- publish a normal (non-prerelease) GitHub release so `releases/latest` keeps
  resolving (the script does this and verifies the feed afterwards);
- the first Sparkle-enabled version (0.2.0) must be installed manually by
  existing users (older builds have no updater); every version after that
  updates itself.

Installed apps keep working with an out-of-date feed: Sparkle simply reports
"up to date". To test an update locally, build two Developer ID versions and
serve the appcast with `python3 -m http.server`, then launch the installed app
with `MW_UPDATE_FEED_URL=http://localhost:8000/appcast.xml`.

## 🏗️ Architecture

```
MagicWall/                    app target (SwiftUI, not sandboxed)
├── App/                      entrypoint, wiring, view model, window lifecycle
├── UI/                       library views (Netflix-style)
├── Engine/                   wallpaper engine (desktop-level NSWindow, AVPlayerLooper,
│                             PlaybackPolicy: battery/lock/thermal/occlusion/wake)
├── MenuBar/                  menu bar extra
├── Settings/                 settings window
└── Services/                 login item (SMAppService), library mirror + lock screen status

MagicWallWallpaperExtension/  ExtensionKit extension (macOS 26+, sandboxed):
                              provider for com.apple.wallpaper — desktop and
                              lock screen through macOS's own pipeline

Packages/MagicWallCore/       shared, testable logic
├── Models/                   Video, VideoCategory, Playlist, ScreenAssignment
├── Database/                 GRDB (schema + migrations + repository)
└── Media/                    AVFoundation probing, SHA-256, posters, import
```

### How the engine works

One borderless `NSWindow` per screen at `kCGDesktopWindowLevel` (verified:
Finder icons live at `kCGDesktopWindowLevel + 20`), driven by `AVQueuePlayer` +
`AVPlayerLooper` (gapless looping, hardware decoding). `ignoresMouseEvents`,
`canJoinAllSpaces`, no app activation required. Per-screen assignments are
persisted in the database (`screen_assignments`, key `display:<CGDirectDisplayID>`)
and restored on every launch.

### Lock screen wallpaper (macOS 26+)

The lock screen is drawn by the system's `WallpaperAgent`, outside the reach of
any app window, so the only way in is to be one of its providers.
`MagicWallWallpaperExtension` is an ExtensionKit extension for the
`com.apple.wallpaper` extension point: it renders through the private
`WallpaperExtensionKit` framework (loaded at runtime, never linked) and serves
the same library, mirrored by the app into the extension's sandbox container
with hard links — the videos are never duplicated on disk. Because it relies on
private APIs, MagicWall ships as a notarized Developer ID download and is **not**
Mac App Store material. The extension is inert unless it is the selected screen
saver, and macOS 15–25 never loads it at all.

### Window lifecycle

Closing the window does **not** quit the app: the engine keeps running so the
wallpaper never stops. Clicking the Dock icon again (or "Open MagicWall" from
the menu bar) recreates the window — see `MagicWall/App/MainWindow.swift`.

## 💾 Local data

```
~/Library/Application Support/MagicWall/
├── magicwall.sqlite
└── Library/
    ├── Videos/<uuid>.<ext>
    └── Posters/<uuid>.jpg
```

On macOS 26+ the app also mirrors the videos into the wallpaper extension's
sandbox container, `~/Library/Containers/app.magicwall.wallpaper-extension/Data/Documents/videos/`,
so the system can play them on the lock screen. The files there are hard links
to the ones above: they take no extra space, and removing them is harmless —
they are recreated on the next launch. Deleting a video in MagicWall removes
its copy too.

The app keeps your data on your Mac: no accounts, no telemetry. The only
network request is the update check against the official GitHub releases,
which you can turn off in Settings → About.

For development and tests you can move the whole data directory with the
`MAGICWALL_DATA_DIR` environment variable (also honored by `mwctl` and the E2E
tests).

## 🧪 Tests

Core (unit tests):

```bash
cd Packages/MagicWallCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

E2E UI tests (XCUITest, drives the real app):

```bash
./Scripts/e2e.sh                                       # full E2E suite
./Scripts/e2e.sh -only-testing:MagicWallUITests/MagicWallUITests/testTabNavigationSwitchesContent
```

Covers: complete sidebar, tab navigation, the "preview above the sidebar"
regression, preview dismissal via X and Esc, video rename, empty-library state,
Settings with the Theme tab, and window reopen after close (lifecycle
regression).

Notes:
- on the first run macOS may ask for **Accessibility**/**Automation** permission
  for Xcode/your terminal: grant it so synthetic clicks work;
- on macOS the tests use `click()` (not `tap()`);
- `e2e.sh` generates a test video, imports an isolated library into
  `/tmp/mw-e2e-data/seeded` and points the scheme's `MW_E2E_SEEDED_DATA_DIR`
  at it (xcodebuild does not forward the shell environment to the test runner,
  so the value lives in `project.yml`): your real library is never touched;
- the empty-library test creates an empty temporary directory instead;
- full log in `/tmp/mw-e2e.log`.

## 🔧 Dev tools

- `DevTools/make-test-video.swift` — generates an animated test video:
  `swift DevTools/make-test-video.swift DevFixtures/test-pattern.mp4`

## 📄 License

MagicWall is released under the **MIT** license (see [`LICENSE`](LICENSE)).
Third-party dependencies are listed in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
