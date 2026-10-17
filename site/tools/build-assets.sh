#!/usr/bin/env bash
#
# build-assets.sh — regenerate the hero wallpaper assets used by the MagicWall site.
#
# The source clip is NOT part of this repository. It is a cherry-blossom video
# that you supply yourself (any size or aspect ratio, 1600×900 or larger looks
# best). From it this script produces two files in assets/media/:
#
#   wallpaper.mp4          1600×900 H.264, CRF 27, no audio, +faststart
#                          (the committed one is 13.2 s / 30 fps / ~2.3 MB)
#   wallpaper-poster.jpg   a still frame from ~1 s, JPEG (ffmpeg -q:v 3)
#
# The committed copies were produced with exactly the settings below.
#
# Usage:
#   ./tools/build-assets.sh --input ~/Downloads/cherry-blossom.mp4
#   ./tools/build-assets.sh --input clip.mov --force
#
# Requires ffmpeg + ffprobe (brew install ffmpeg). Note: this ffmpeg has no
# libwebp, so the assets are JPEG only — never write .webp here.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site="$(cd "$here/.." && pwd)"
media="$site/assets/media"

# ── tunables ──────────────────────────────────────────────────────────────
width=1600          # output width  — scaled up to cover, then centre-cropped
height=900          # output height — 16:9, matches the hero's screen glass
crf=27              # x264 quality: lower = better/larger (18…28 is sane)
preset=slow         # x264 speed/size trade-off (slower = smaller file)
poster_at=1         # seconds into the clip used for the poster still
poster_quality=3    # ffmpeg -q:v for the JPEG (2 = best … 31 = worst)

out_video="$media/wallpaper.mp4"
out_poster="$media/wallpaper-poster.jpg"
# fill the 16:9 frame without stretching, then crop the overflow
scale_crop="scale=${width}:${height}:force_original_aspect_ratio=increase,crop=${width}:${height}"

usage() {
  cat <<'TXT'
Regenerate assets/media/wallpaper.mp4 and wallpaper-poster.jpg from a local
source video (not committed to the repository).

Usage:
  ./tools/build-assets.sh --input <path/to/source-video> [--force]

Options:
  --input <path>   The cherry-blossom source video (required).
  --force          Overwrite existing outputs. Without it the script stops,
                   because the current files are published on the site.
  -h, --help       Show this help.

Settings live in named variables at the top of the script.
TXT
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ── arguments ─────────────────────────────────────────────────────────────
input=""
force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      [[ $# -ge 2 ]] || die "--input needs a path"
      input="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$input" ]] || { usage >&2; die "--input is required"; }
[[ -f "$input" ]] || die "source video not found: $input"

command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found — install it with: brew install ffmpeg"
command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found — install it with: brew install ffmpeg"

if [[ "$force" -ne 1 ]]; then
  for existing in "$out_video" "$out_poster"; do
    [[ -e "$existing" ]] && die "$existing exists — re-run with --force to overwrite it"
  done
fi

mkdir -p "$media"

printf 'source: %s\n' "$input"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration \
  -of default=noprint_wrappers=1 "$input" || true

# ── video: scale to cover 1600×900, centre-crop, H.264, no audio ──────────
printf 'encoding %s …\n' "$out_video"
ffmpeg -y -loglevel error -stats -i "$input" \
  -vf "$scale_crop" \
  -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv420p -an \
  -movflags +faststart \
  "$out_video"

# ── poster: one JPEG frame from around ${poster_at}s, same framing ────────
printf 'extracting %s …\n' "$out_poster"
ffmpeg -y -loglevel error -ss "$poster_at" -i "$input" \
  -vf "$scale_crop" \
  -frames:v 1 -q:v "$poster_quality" \
  "$out_poster"

printf 'wrote %s (%s bytes)\n' "$out_video" "$(stat -f%z "$out_video")"
printf 'wrote %s (%s bytes)\n' "$out_poster" "$(stat -f%z "$out_poster")"
