# MagicWall — marketing site

Static one-pager for [MagicWall](https://github.com/davidullo/magicwall), served at
<https://magicwall.davide.fyi>.

No build step and no dependencies: plain HTML, CSS and one small script. Everything in
this folder is deployed as-is.

```
site/
├── index.html                  the whole page (nav, hero, FAQ, CTA, footer)
├── styles/tokens.css           design tokens, @font-face, base type
├── styles/layout.css           nav, hero (Mac screen), sections, footer
├── styles/components.css       buttons, bricks, browser window, dock, FAQ
├── scripts/main.js             latest-release lookup, reveal, nav, dock, hero video
├── assets/icon/                favicons, PWA icons, apple-touch-icon, og.jpg
├── assets/dock/                dock icons (macOS Tahoe screenshots)
├── assets/media/               wallpaper.mp4 + wallpaper-poster.jpg
├── assets/font/                self-hosted Inter + Geist Mono (OFL)
├── tools/og.html + og.sh       renders the 1200×630 social card
├── tools/build-assets.sh       regenerates assets/media from a local source video
├── vercel.json                 caching + security headers
├── robots.txt, sitemap.xml     crawler files
└── site.webmanifest            name, icons, theme colour
```

## Preview locally

```bash
cd site && python3 -m http.server 4321
# open http://localhost:4321
```

## How the page is put together

**Hero.** A CSS mock of a Mac screen — a rounded aluminium frame around a dark stage
that keeps a wide cinema-ish ratio on big screens and relaxes as the viewport narrows.
The wallpaper is a looping cherry-blossom `<video>` (with `wallpaper-poster.jpg` as its
poster frame). On top of it sit a fake Safari window and a macOS-style dock. The browser
window contains a miniature copy of the page: everything inside it is sized in `cqw`
container-query units, so it scales with the window instead of breaking. The phrase
highlighted in that headline ("custom video wallpaper") is filled with an animated
rainbow gradient that loops seamlessly across the text; under
`prefers-reduced-motion: reduce` the animation stops and the gradient falls back to a
static rainbow.

The dock is light frosted glass: every icon rests at the same size (the MagicWall icon
sits in the middle, not enlarged) and only the icons near the pointer grow — a port of
the dock from the jollycat project. `scripts/main.js` maps the pointer onto a fractional
icon slot and lerps a CSS `zoom` on each `.dock-icon-zoom`; the markup stays plain
`<img>` tags, so the dock still reads fine when JavaScript is off, and under
`prefers-reduced-motion: reduce` the magnification is skipped entirely.

**The rest.** A FAQ built from seven `<details>` elements, a final CTA band, and the
footer. Everything else in `scripts/main.js` (scroll reveal, sticky nav, mobile panel)
is progressive enhancement — the page is complete without it.

**Nav & buttons.** The header is a floating centred pill (max-width 1120px, fully
rounded, frosted glass) rather than a full-width bar; it shrinks from 64px to 56px and
tucks 6px closer to the top once scrolled. The download calls to action use the ported
"argent" component — a metallic pink pill with a dark inner panel that fades away on
hover, a sweeping sheen, a soft outer halo — and every download button carries the
Apple logo while the GitHub call to action ("Star on GitHub") carries the GitHub mark,
with the icon and label on a single aligned line.

## The download button

Every `[data-release-link]` element points at the **latest GitHub release**. On load
`scripts/main.js` asks `api.github.com/repos/davidullo/magicwall/releases/latest` for
the newest `.dmg` asset, rewrites the links to that file (with `download`) and fills in
`[data-release-version]`, `[data-release-name]`, `[data-release-size]`,
`[data-release-date]` and `[data-release-status]`. The response is cached in
`sessionStorage` for 30 minutes; if the request fails, every link falls back to
`/releases/latest` and the page keeps working with its server-rendered placeholders.

## Assets

- `assets/icon/` — favicons at 16/32 px, 192/512 px PWA icons, apple-touch-icon, and
  `og.jpg`, the 1200×630 social card referenced by the Open Graph tags.
- `assets/dock/` — Finder, Clock, Maps and Photos, macOS Tahoe icon screenshots reused
  from the jollycat project (the fifth dock icon is MagicWall's own 192 px icon).
- `assets/media/` — `wallpaper.mp4` (1600×900, 13.2 s, H.264, no audio) and the matching
  `wallpaper-poster.jpg`. It also holds `footer-garden.jpg`, the 2400×1371 spring-garden
  photo used as a full-bleed footer background. A white veil (`rgba(253, 251, 252, 0.60)`
  at the top to `0.78` at the bottom) keeps the photo clearly visible while the footer
  text sits in the darker `--ink` / `--ink-2` tones so it still clears AA contrast.
- `assets/font/` — Inter and Geist Mono as latin variable `woff2`, self-hosted under the
  SIL Open Font License; the `OFL-*.txt` files ship next to them.

Regenerating the wallpaper assets needs the original cherry-blossom clip, which is
**not** committed to this repository:

```bash
./tools/build-assets.sh --input ~/Downloads/cherry-blossom.mp4
```

`tools/build-assets.sh` documents the whole derivation (scale/crop to 1600×900, x264
CRF 27, `+faststart`, poster frame at ~1 s) in named variables at the top. It refuses to
overwrite existing outputs unless you pass `--force`, since the current files are live
on the site. It needs `ffmpeg` and `ffprobe`; this ffmpeg build has no libwebp, so the
assets stay JPEG.

Regenerating `footer-garden.jpg` needs the original AVIF/PNG, which is **not**
committed either:

```bash
# da una sorgente AVIF/PNG non versionata (es. ~/Downloads/Giardino primaverile con muro rosa*.avif)
sips -s format jpeg -s formatOptions 72 --resampleWidth 2400 <sorgente> --out assets/media/footer-garden.jpg
```

The social card is rendered from `tools/og.html` with headless Chrome:

```bash
./tools/og.sh        # writes assets/icon/og.jpg (1200×630)
```

## Deploy

The Vercel project has this folder as its **root directory**, so a deploy ships exactly
the files above. It is linked to the GitHub repo: every push to `main` deploys `site/`
automatically. `Scripts/publish` keeps the release placeholders in `index.html` in sync
and bumps `RELEASE_KEY` in `scripts/main.js` to invalidate the page's release cache, so
a normal release needs no manual site step.

Manual production deploys are still available:

```bash
vercel deploy --prod      # from site/
```

`vercel.json` serves `/assets/*` with a one-year immutable `Cache-Control`, and adds a
Content-Security-Policy plus the usual `X-Content-Type-Options`, `Referrer-Policy` and
`Permissions-Policy` headers to everything else. The CSP is `default-src 'self'`;
`connect-src` additionally allows `https://api.github.com` for the release lookup, and
`style-src`/`script-src` allow inline code because the page has a tiny inline script and
style attributes.

DNS: `magicwall.davide.fyi` is a `CNAME` to `cname.vercel-dns.com` in Cloudflare, with
the proxy **off** (grey cloud, “DNS only”) so Vercel terminates TLS itself.
