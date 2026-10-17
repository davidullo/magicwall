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
- **Favorites rotation** — auto-swap your favorite wallpapers on all screens
  every 1–60 minutes; every favorite is shown once per cycle before repeating.
- **Power policy** — automatic pausing on battery, Low Power Mode, thermal
  pressure, screen lock or occluded desktop, with recovery after sleep/wake.
- **Menu bar** — pause, shuffle, favorites, rotation and stop without opening
  the window.
- **Themes** — editable design tokens (colors, corner radii, gradients) plus
  light/dark appearance.
- **English and Italian** — the UI follows the system language.
- **Automatic updates** — the app checks the official GitHub releases once a
  day, verifies the signature of the download and installs it in place when
  you say so (checks can be turned off in Settings → About).
- **Completely local** — no accounts, no telemetry: your videos never leave
  your Mac. The update check is the only network access the app makes.

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
- **M5** (community): future

## 🖥️ Requirements

**To use the app**

- macOS 15 or later (developed and tested on macOS 27)

**To build**

- Xcode 27.x with the macOS SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

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

The version lives in `project.yml` (`MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`). To produce the distributable artifacts:

```bash
./Scripts/release.sh            # universal build (arm64 + x86_64)
./Scripts/release.sh --native   # this Mac's architecture only, faster
```

Artifacts are written to `dist/`:

- `MagicWall-<version>.dmg` (app + Applications symlink)
- `MagicWall-<version>.zip`
- `MagicWall-<version>.dSYM.zip` (symbols for crash reports)
- `appcast.xml` (Developer ID builds only — the Sparkle update feed)
- `SHA256SUMS.txt`

Local builds are ad-hoc signed: they run on this Mac, but other Macs will be
blocked by Gatekeeper because they are not notarized. For a frictionless
release you need an Apple Developer account:

```bash
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE=magicwall \
./Scripts/release.sh --notarize
```

Create the `magicwall` profile once with
`xcrun notarytool store-credentials magicwall --apple-id ... --team-id ...`.
To publish the GitHub release (after configuring the remote and
`gh auth login`):

```bash
./Scripts/release.sh --publish
```

The script never pushes the repository: it only creates the `v<version>`
release with the artifacts attached.

### Auto-updates (Sparkle)

Updates are delivered by [Sparkle 2](https://sparkle-project.org) and are only
possible on Developer ID builds (Sparkle validates the running app's signature
before installing anything). The release script:

1. builds with the Developer ID so `Sparkle.framework`, its XPC services and
   the app all carry the same signature;
2. signs the ZIP with the EdDSA key and generates `dist/appcast.xml`;
3. `--publish` attaches the appcast to the release, which serves the feed at:

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

- bump `CURRENT_PROJECT_VERSION` — Sparkle compares the build number;
- publish a normal (non-prerelease) GitHub release so `releases/latest` keeps
  resolving;
- the first Sparkle-enabled version must be installed manually by existing
  users (older builds have no updater); every version after that updates
  itself.

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
└── Services/                 login item (SMAppService)

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
