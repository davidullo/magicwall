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
# (starter-wallpapers.json, with SHA-256 and size per file) is committed and the
# MP4s live in the `starter-v2` GitHub release. Each clip ships in two quality
# tiers, and the app picks one in the first-launch sheet:
#
#   high      x265 (software HEVC) CRF 22, from the 4K master — recommended
#   compact   VideoToolbox HEVC ~6 Mbps — the original v1 pack, small download
#
# Encoding is intentionally fixed and simple: the original resolution and frame
# rate (no downscaling: these are 4K clips), no audio, `hvc1` tag and
# `+faststart`, so AVFoundation streams them without a full download.
#
# Output (dist/starter/, gitignored):
#   high/<id>.mp4, compact/<id>.mp4, manifest.json
#
# The manifest is written twice: the copy attached to the release
# (dist/starter/manifest.json) and the one bundled with the app
# (Packages/MagicWallCore/Sources/MagicWallCore/Resources/starter-wallpapers.json).
#
# The script is idempotent: existing up-to-date encodes are reused and
# --publish always uploads with --clobber, so re-running never duplicates
# files or assets.
#
# Tunables: --input / --output; bitrates are set below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

input_dir="$ROOT/starter-input"
output_dir=dist/starter
base_url="https://github.com/davidullo/magicwall/releases/download/starter-v2/"
release_tag="starter-v2"
release_title="MagicWall starter wallpapers v2"
release_notes="Optional starter wallpapers for MagicWall (4K HEVC, no audio), in
two quality tiers: high (x265 CRF 22 from the 4K masters) and compact
(6 Mbps VideoToolbox). These media files are NOT covered by the MIT license of
the MagicWall app: they ship only as optional downloads and may not be
redistributed separately."
# High tier: software x265, 8-bit Main profile (hardware-decodable on every Mac
# that runs macOS 15). CRF 22 keeps SSIM > 0.99 against the masters at a
# fraction of the original H.264 bitrate.
high_encoder_args=(-c:v libx265 -preset slow -crf 22 -profile:v main)
# Compact tier: the original v1 pack.
compact_bitrate=6M
compact_maxrate=8M

manifest="Packages/MagicWallCore/Sources/MagicWallCore/Resources/starter-wallpapers.json"

# source file | id | title | trim (start:duration seconds, empty = full length)
entries=(
    "aesthetic-dreamscape_175732739579865.mp4|dreamscape|Dreamscape|"
    "alangaller_690115881200167.mp4|clover-rainbow|Clover Rainbow|"
    "aurora-borealis-forest_439761519316753.mp4|aurora-forest|Aurora Forest|"
    "cherry-blossoms-in-spring_878949321278126.mp4|cherry-blossom-spring|Cherry Blossom Spring|"
    "colorful-underwater-scene_196556831175761.mp4|colorful-underwater-scene|Colorful Underwater Scene|16:24"
)

PUBLISH=0
ENCODE_ONLY=0

usage() {
    cat <<'EOF'
Encodes the optional MagicWall starter wallpaper pack and writes its manifest.

  ./Scripts/starter-media.sh                 # encode + manifest (no upload)
  ./Scripts/starter-media.sh --publish       # also create/update the release
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

mkdir -p "$output_dir/high" "$output_dir/compact"

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
echo "  input:   $input_dir"
echo "  output:  $output_dir"
echo "  high:    libx265 CRF 22, preset slow, 8-bit Main"
echo "  compact: hevc_videotoolbox, $compact_bitrate (maxrate $compact_maxrate)"
echo

# ------------------------------------------------------------------- encode

for entry in "${entries[@]}"; do
    IFS='|' read -r src_file id title trim <<<"$entry"

    src="$input_dir/$src_file"
    if [[ ! -f "$src" ]]; then
        echo "Source file missing: $src" >&2
        exit 1
    fi

    # Optional per-clip trim so a long source becomes a shorter loop:
    # "start:duration" or just "duration" (from the beginning).
    trim_args=()
    if [[ -n "$trim" ]]; then
        trim_start="${trim%%:*}"
        trim_duration="${trim##*:}"
        if [[ "$trim" == *:* ]]; then
            [[ -n "$trim_start" ]] && trim_args+=(-ss "$trim_start")
            [[ -n "$trim_duration" ]] && trim_args+=(-t "$trim_duration")
        else
            trim_args+=(-t "$trim")
        fi
    fi

    for tier in high compact; do
        dst="$output_dir/$tier/$id.mp4"

        # Reuse an existing encode unless the source is newer, so re-runs are cheap.
        if [[ -f "$dst" && "$dst" -nt "$src" ]]; then
            echo "▸ $tier/$id.mp4 (up to date, skipping)"
            continue
        fi

        echo "▸ Encoding $tier/$id.mp4…"
        if [[ "$tier" == "high" ]]; then
            ffmpeg -y -v error "${trim_args[@]+"${trim_args[@]}"}" -i "$src" \
                "${high_encoder_args[@]}" \
                -tag:v hvc1 \
                -pix_fmt yuv420p \
                -an \
                -map_metadata -1 \
                -movflags +faststart \
                "$dst"
        else
            ffmpeg -y -v error "${trim_args[@]+"${trim_args[@]}"}" -i "$src" \
                -c:v hevc_videotoolbox \
                -b:v "$compact_bitrate" \
                -maxrate "$compact_maxrate" \
                -tag:v hvc1 \
                -pix_fmt yuv420p \
                -an \
                -map_metadata -1 \
                -movflags +faststart \
                "$dst"
        fi
    done
done

echo
echo "▸ Encoded files:"
ls -lh "$output_dir/high" "$output_dir/compact"
echo
echo "  high tier total:    $(du -sh "$output_dir/high" | cut -f1)"
echo "  compact tier total: $(du -sh "$output_dir/compact" | cut -f1)"
echo

if [[ "$ENCODE_ONLY" -eq 1 ]]; then
    echo "✓ Encoding only: manifest and release left untouched."
    exit 0
fi

# ------------------------------------------------------- checksums/metadata

variant_record() {
    local tier="$1"
    local id="$2"
    local file="$output_dir/$tier/$id.mp4"
    local sha bytes
    sha="$(shasum -a 256 "$file" | awk '{print $1}')"
    bytes="$(stat -f%z "$file")"

    if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Unexpected sha256 for $file: $sha" >&2
        exit 1
    fi
    if (( bytes <= 0 )); then
        echo "Empty file: $file" >&2
        exit 1
    fi

    printf '"quality": "%s", "fileName": "%s-%s.mp4", "sha256": "%s", "bytes": %s' \
        "$tier" "$id" "$tier" "$sha" "$bytes"
}

records=()
for entry in "${entries[@]}"; do
    IFS='|' read -r src_file id title _ <<<"$entry"
    high_file="$output_dir/high/$id.mp4"

    width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$high_file")"
    height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$high_file")"
    duration="$(format_duration "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$high_file")")"

    for value in "$width" "$height" "$duration"; do
        if [[ -z "$value" ]]; then
            echo "Could not read metadata for $high_file." >&2
            exit 1
        fi
    done

    records+=("$id|$title|$width|$height|$duration")
done

# ---------------------------------------------------------------- manifest

write_manifest() {
    local path="$1" index=0 total=${#records[@]}

    {
        echo "{"
        echo "  \"version\": 2,"
        echo "  \"baseURL\": \"$base_url\","
        echo "  \"wallpapers\": ["
        for record in "${records[@]}"; do
            IFS='|' read -r id title width height duration <<<"$record"
            index=$((index + 1))
            printf '    {\n'
            printf '      "id": "%s",\n' "$id"
            printf '      "title": "%s",\n' "$title"
            printf '      "width": %s,\n' "$width"
            printf '      "height": %s,\n' "$height"
            printf '      "duration": %s,\n' "$duration"
            printf '      "variants": [\n'
            printf '        { %s },\n' "$(variant_record high "$id")"
            printf '        { %s }\n' "$(variant_record compact "$id")"
            printf '      ]\n'
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
    # GitHub release assets are flat, while the encodes live in per-tier
    # folders: stage them under the names the manifest declares.
    upload_dir="$output_dir/upload"
    rm -rf "$upload_dir"
    mkdir -p "$upload_dir"
    for entry in "${entries[@]}"; do
        IFS='|' read -r src_file id title _ <<<"$entry"
        for tier in high compact; do
            src="$output_dir/$tier/$id.mp4"
            dst="$upload_dir/$id-$tier.mp4"
            [[ -f "$src" ]] || { echo "Missing encode: $src" >&2; exit 1; }
            ln -f "$src" "$dst" 2>/dev/null || cp "$src" "$dst"
        done
    done
    cp "$output_dir/manifest.json" "$upload_dir/manifest.json"

    assets=("$upload_dir"/*.mp4 "$upload_dir/manifest.json")

    # The upload endpoint can 404 right after a release is created (the new
    # release is not visible to it yet), so the release is created empty first
    # and the assets go up in a retried, clobbering pass.
    upload_assets() {
        local attempt
        for attempt in 1 2 3; do
            if gh release upload "$release_tag" --clobber "${assets[@]}"; then
                return 0
            fi
            echo "⚠ upload attempt $attempt failed, retrying in 5s…" >&2
            sleep 5
        done
        return 1
    }

    echo "▸ Publishing ${release_tag}…"
    if ! gh release view "$release_tag" >/dev/null 2>&1; then
        # --latest=false is load-bearing: installed apps read the Sparkle feed
        # from /releases/latest/download/appcast.xml, so this pack must never
        # take over the "Latest" slot.
        gh release create "$release_tag" \
            --title "$release_title" \
            --notes "$release_notes" \
            --latest=false
    fi

    upload_assets
    echo
    echo "✓ Release: $RELEASE_URL"
else
    echo "✓ Encoded and manifest written (not published)."
    echo "  Upload with: ./Scripts/starter-media.sh --publish"
    echo "  Release would be: $RELEASE_URL"
fi
