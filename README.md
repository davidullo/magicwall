# MagicWall

Wallpaper video locali per macOS. App nativa Swift/SwiftUI, leggera e senza dipendenze
esterne a runtime oltre a GRDB (SQLite).

## Stato

- **M1** (fondamenta): ✅ progetto, schema DB, import video, poster, libreria
- **M2** (engine): ✅ finestre desktop-level per schermo, loop gapless, persistenza
  per-monitor, restore all'avvio, policy energia (batteria / risparmio energetico /
  pressione termica / schermo bloccato / sleep / occlusione desktop), recovery al wake
- **M3** (UI Netflix-style): ✅ top bar + hero + caroselli + Explore + preview fullscreen;
  ⏳ transcode HEVC (da fare)
- **M4** (hardening/benchmark): in corso — misure: ~0.5–3.5% CPU, ~130 MB RSS con un 1080p
- **M5** (community): futuro

## Come si usa

1. Apri MagicWall → "+" (o trascina file/cartelle MP4/MOV nella finestra).
2. Nella card premi play → preview; "Riproduci come wallpaper" per applicarlo a tutti
   gli schermi (o tasto destro → "Set on Screen" per un singolo monitor).
3. L'app resta nel menu bar: pausa, shuffle, preferiti, stop. Da Impostazioni →
   Riproduzione puoi regolare le pause automatiche (batteria, risparmio energetico,
   pressione termica, schermo bloccato, desktop nascosto).
4. Gli assegnamenti per schermo sopravvivono al riavvio e vengono ripristinati
   automaticamente.

## Requisiti

- macOS 15+ (sviluppato e testato su macOS 27)
- Xcode 27.x con SDK macOS
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# genera il progetto Xcode da project.yml (la source of truth è project.yml,
# non editare MagicWall.xcodeproj: è generato e in .gitignore)
xcodegen generate

xcodebuild -project MagicWall.xcodeproj -scheme MagicWall \
  -configuration Debug -derivedDataPath /tmp/mw-dd build

open /tmp/mw-dd/Build/Products/Debug/MagicWall.app
```

Test del core:

```bash
cd Packages/MagicWallCore && swift test
```

## Architettura

```
MagicWall/                    app target (SwiftUI, non sandboxed)
├── App/                      entrypoint, wiring, view model
├── UI/                       viste della libreria (stile Netflix)
├── Engine/                   engine wallpaper (NSWindow desktop-level, AVPlayerLooper,
│                             PlaybackPolicy: batteria/lock/termico/occlusione/wake)
├── MenuBar/                  menu bar extra
├── Settings/                 finestra impostazioni
└── Services/                 login item (SMAppService)

Packages/MagicWallCore/       logica condivisa e testabile
├── Models/                   Video, VideoCategory, Playlist, ScreenAssignment
├── Database/                 GRDB (schema + migrazioni + repository)
└── Media/                    probe AVFoundation, SHA-256, poster, import
```

### Come funziona l'engine

Una `NSWindow` borderless per schermo al livello `kCGDesktopWindowLevel`
(verificato: le icone del Finder stanno a `kCGDesktopWindowLevel + 20`), con
`AVQueuePlayer` + `AVPlayerLooper` (loop senza salti, decodifica hardware).
`ignoresMouseEvents`, `canJoinAllSpaces`, nessuna attivazione app richiesta.
Gli assegnamenti per schermo sono persistiti nel DB (`screen_assignments`,
chiave `display:<CGDirectDisplayID>`) e ripristinati a ogni avvio.

## Dati locali

```
~/Library/Application Support/MagicWall/
├── magicwall.sqlite
└── Library/
    ├── Videos/<uuid>.<ext>
    └── Posters/<uuid>.jpg
```

## Dev tools

- `DevTools/make-test-video.swift` — genera un video di test animato:
  `swift DevTools/make-test-video.swift DevFixtures/test-pattern.mp4`
