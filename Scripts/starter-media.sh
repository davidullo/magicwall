#!/usr/bin/env bash
#
# Encodes the optional "starter" wallpaper pack and publishes it.
#
#   ./Scripts/starter-media.sh                 # encode + manifest (no upload)
#   ./Scripts/starter-media.sh --publish       # also create/update the release
#   ./Scripts/starter-media.sh --encode-only   # only (re)encode the MP4s
#
# The starter wallpapers are an optional extra offered on first launch: the
# media is far too large for the repository, so only a manifest
# (starter-wallpapers.json, with SHA-256 and metadata per item) is committed
# and the MP4s live in the "starter-v1" GitHub release. The app downloads them
# on demand from base_url below.
#
# Encoding is intentionally fixed and simple: HEVC via VideoToolbox, the
# original resolution and frame rate (no downscaling: these are 4K clips),
# no audio, and a bitrate ceiling low enough to keep each file around 8-12 MB.
#
# Output (dist/starter/, gitignored):
#   dreamscape.mp4, clover-rainbow.mp4, aurora-forest.mp4,
#   cherry-blossom-spring.mp4, manifest.json
#
# The manifest is written twice: the copy attached to the release
# (dist/starter/manifest.json) and the one bundled with the app
# (Packages/MagicWallCore/Sources/MagicWallCore/Resources/starter-wallpapers.json).
#
# The script is idempotent: existing up-to-date encodes are reused and
# --publish always uploads with --clobber, so re-running never duplicates
# files or assets.
#
# Tunables (overridable via --input / --output):
#   input_dir   folder holding the source MP4s
#   output_dir  local staging folder for the encoded files
#   base_url    release asset prefix used by the app to fetch a wallpaper
#   tag         GitHub release that carries the starter media
#   bitrate     target video bitrate handed to ffmpeg
#   maxrate     peak bitrate ceiling handed to ffmpeg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

input_dir="$ROOT/starter-input"
output_dir=dist/starter
base_url="https://github.com/davidullo/magicwall/releases/download/starter-v1/"
release_tag="starter-v1"
release_title="MagicWall starter wallpapers v1"
release_notes="Optional starter wallpapers for MagicWall (4K HEVC, no audio).
These media files are NOT covered by the MIT license of
the MagicWall app: they ship only as optional downloads and may not be
redistributed separately."
bitrate=6M
maxrate=8M

manifest="Packages/MagicWallCore/Sources/MagicWallCore/Resources/starter-wallpapers.json"

# source file | id | title | output file name
entries=(
    "aesthetic-dreamscape_175732739579865.mp4|dreamscape|Dreamscape|dreamscape.mp4"
    "alangaller_690115881200167.mp4|clover-rainbow|Clover Rainbow|clover-rainbow.mp4"
    "aurora-borealis-forest_439761519316753.mp4|aurora-forest|Aurora Forest|aurora-forest.mp4"
    "cherry-blossoms-in-spring_878949321278126.mp4|cherry-blossom-spring|Cherry Blossom Spring|cherry-blossom-spring.mp4"
)

PUBLISH=0
ENCODE_ONLY=0

usage() {
    cat <<'EOF'
Encodes the optional MagicWall starter wallpaper pack and writes its manifest.

  ./Scripts/starter-media.sh                 # encode + manifest (no upload)
  ./Scripts/starter-media.sh --publish       # also create/update the GitHub release
  ./Scripts/starter-media.sh --encode-only   # only (re)encode the MP4s

Options:
  --input <dir>    folder with the source MP4s (default: ./starter-input)
  --output <dir>   staging folder for the encoded files (default: dist/starter)
  --encode-only    skip manifest generation and publishing
  --publish        create the release (or upload with --clobber if it exists)
  -h, --help       show this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input) input_dir="$2"; shift 2 ;;
        --output) output_dir="$2"; shift 2 ;;
        --encode-only) ENCODE_ONLY=1; shift ;;
        --publish) PUBLISH=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

for tool in ffmpeg ffprobe shasum; do
    command -v "$tool" >/dev/null || { echo "$tool is required." >&2; exit 1; }
done

if [[ "$PUBLISH" -eq 1 ]]; then
    if [[ "$ENCODE_ONLY" -eq 1 ]]; then
        echo "--publish and --encode-only are mutually exclusive." >&2
        exit 1
    fi
    command -v gh >/dev/null || { echo "--publish requires the GitHub CLI (gh)." >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated (run: gh auth login)." >&2; exit 1; }
fi

if [[ ! -d "$input_dir" ]]; then
    echo "Input folder not found: $input_dir" >&2
    exit 1
fi

mkdir -p "$output_dir"

# 12.366667 -> "12.37", 18.000000 -> "18.0": two decimals, at least one kept.
format_duration() {
    awk -v d="$1" 'BEGIN {
        s = sprintf("%.2f", d)
        sub(/0+$/, "", s)
        if (s ~ /\.$/) s = s "0"
        print s
    }'
}

echo "▸ Starter wallpapers"
echo "  input:  $input_dir"
echo "  output: $output_dir"
echo "  codec:  hevc_videotoolbox, $bitrate (maxrate $maxrate), no audio"
echo

# ------------------------------------------------------------------- encode

for entry in "${entries[@]}"; do
    IFS='|' read -r src_file id title file_name <<<"$entry"

    src="$input_dir/$src_file"
    dst="$output_dir/$file_name"

    if [[ ! -f "$src" ]]; then
        echo "Source file missing: $src" >&2
        exit 1
    fi

    # Reuse an existing encode unless the source is newer, so re-runs are cheap.
    if [[ -f "$dst" && "$dst" -nt "$src" ]]; then
        echo "▸ ${file_name} (up to date, skipping)"
    else
        # Brace the variable: bash 3.2 misparses a name followed by a
        # multi-byte character, which would trip "set -u".
        echo "▸ Encoding ${file_name}…"
        ffmpeg -y -i "$src" \
            -c:v hevc_videotoolbox \
            -b:v "$bitrate" \
            -maxrate "$maxrate" \
            -tag:v hvc1 \
            -pix_fmt yuv420p \
            -an \
            -map_metadata -1 \
            -movflags +faststart \
            "$dst"
    fi

done

echo
echo "▸ Encoded files:"
ls -lh "$output_dir"
echo

if [[ "$ENCODE_ONLY" -eq 1 ]]; then
    echo "✓ Encoding only: manifest and release left untouched."
    exit 0
fi

# ------------------------------------------------------- checksums/metadata

records=()
for entry in "${entries[@]}"; do
    IFS='|' read -r src_file id title file_name <<<"$entry"
    dst="$output_dir/$file_name"

    sha="$(shasum -a 256 "$dst" | awk '{print $1}')"
    bytes="$(stat -f%z "$dst")"
    width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$dst")"
    height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$dst")"
    duration="$(format_duration "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dst")")"

    for value in "$sha" "$bytes" "$width" "$height" "$duration"; do
        if [[ -z "$value" ]]; then
            echo "Could not read metadata for $dst." >&2
            exit 1
        fi
    done

    if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Unexpected sha256 for $dst: $sha" >&2
        exit 1
    fi
    if (( bytes <= 0 )); then
        echo "Empty file: $dst" >&2
        exit 1
    fi

    records+=("$id|$title|$file_name|$sha|$bytes|$width|$height|$duration")
done

# ---------------------------------------------------------------- manifest

write_manifest() {
    local path="$1" index=0 total=${#records[@]}

    {
        echo "{"
        echo "  \"version\": 1,"
        echo "  \"baseURL\": \"$base_url\","
        echo "  \"wallpapers\": ["
        for record in "${records[@]}"; do
            IFS='|' read -r id title file_name sha bytes width height duration <<<"$record"
            index=$((index + 1))
            printf '    {\n'
            printf '      "id": "%s",\n' "$id"
            printf '      "title": "%s",\n' "$title"
            printf '      "fileName": "%s",\n' "$file_name"
            printf '      "sha256": "%s",\n' "$sha"
            printf '      "bytes": %s,\n' "$bytes"
            printf '      "width": %s,\n' "$width"
            printf '      "height": %s,\n' "$height"
            printf '      "duration": %s,\n' "$duration"
            printf '      \n'
            printf '    }%s\n' "$([[ "$index" -lt "$total" ]] && echo ',' || echo '')"
        done
        echo "  ]"
        echo "}"
    } >"$path"
}

write_manifest "$manifest"
write_manifest "$output_dir/manifest.json"

echo "▸ Manifest written:"
echo "  $manifest"
echo "  $output_dir/manifest.json"
echo

# ----------------------------------------------------------------- publish

RELEASE_URL="https://github.com/davidullo/magicwall/releases/tag/$release_tag"

if [[ "$PUBLISH" -eq 1 ]]; then
    assets=("$output_dir"/*)
    echo "▸ Publishing ${release_tag}…"
    if gh release view "$release_tag" >/dev/null 2>&1; then
        gh release upload "$release_tag" --clobber "${assets[@]}"
    else
        # --latest=false is load-bearing: installed apps read the Sparkle feed
        # from /releases/latest/download/appcast.xml, so this pack must never
        # take over the "Latest" slot.
        gh release create "$release_tag" \
            --title "$release_title" \
            --notes "$release_notes" \
            --latest=false \
            "${assets[@]}"
    fi
    echo
    echo "✓ Release: $RELEASE_URL"
else
    echo "✓ Encoded and manifest written (not published)."
    echo "  Upload with: ./Scripts/starter-media.sh --publish"
    echo "  Release would be: $RELEASE_URL"
fi
