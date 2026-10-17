#!/usr/bin/env bash
#
# Measures how much the wallpaper costs on battery.
#
# Run it on a MacBook, on battery, lid open, with a fixed screen brightness and
# nothing else heavy going on. The script is interactive: it asks you to put
# MagicWall in each state, samples the battery draw for a few minutes and prints
# a table (watts and %/hour per state) plus a markdown-ready summary.
#
#   ./Scripts/battery-bench.sh                     # 10 minutes per state
#   ./Scripts/battery-bench.sh --minutes 15
#   ./Scripts/battery-bench.sh --states baseline,compact
#   ./Scripts/battery-bench.sh --out dist/battery-bench
#
# States:
#   baseline  no wallpaper playing (menu bar → "Stop all wallpapers")
#   compact   4K starter clip, quality tier "compact"
#   high      4K starter clip, quality tier "high"
#   hd        1080p clip (any import)
#
# Output: one CSV per state (raw samples) + summary.txt in the output folder.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

minutes=10
interval=5
states_csv="baseline,compact,high"
out_dir="dist/battery-bench"

usage() {
    cat <<'EOF'
Measures the battery draw of the wallpaper on a MacBook.

  ./Scripts/battery-bench.sh [--minutes N] [--states a,b,c] [--out DIR]

Options:
  --minutes N      minutes sampled per state (default: 10)
  --interval N     seconds between samples (default: 5)
  --states LIST    comma-separated subset of: baseline,compact,high,hd
                   (default: baseline,compact,high)
  --out DIR        output folder (default: dist/battery-bench)
  -h, --help       show this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --minutes) minutes="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        --states) states_csv="$2"; shift 2 ;;
        --out) out_dir="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

# ------------------------------------------------------------------ checks

if ! ioreg -rn AppleSmartBattery -w0 | grep -q "AppleSmartBattery"; then
    echo "No battery found: run this on a MacBook (a desktop Mac has no battery)." >&2
    exit 1
fi

if ! pmset -g ps | head -1 | grep -qi "battery power"; then
    echo "This Mac is on AC power. Unplug the charger and keep it unplugged for" >&2
    echo "the whole run (pausing on battery is part of what we measure)." >&2
    exit 1
fi

if pgrep -x MagicWall >/dev/null; then
    echo "  note: MagicWall is running"
else
    echo "Warning: MagicWall is not running — start it before the first state." >&2
fi

mkdir -p "$out_dir"

# --------------------------------------------------------------- sampling

# One battery sample, space separated:
#   capacity_percent voltage_mV amperage_mA watts
# `watts` is -1 when the machine does not expose voltage/amperage.
battery_sample() {
    local raw capacity voltage amperage watts
    raw="$(ioreg -rn AppleSmartBattery -w0)"
    capacity="$(awk -F'= ' '/"CurrentCapacity"/ {gsub(/[^0-9-]/, "", $2); print $2; exit}' <<<"$raw")"
    voltage="$(awk -F'= ' '/"Voltage"/ {gsub(/[^0-9-]/, "", $2); print $2; exit}' <<<"$raw")"
    amperage="$(awk -F'= ' '/"InstantAmperage"/ {gsub(/[^0-9-]/, "", $2); print $2; exit}' <<<"$raw")"
    if [[ -z "$amperage" ]]; then
        amperage="$(awk -F'= ' '/"Amperage"/ {gsub(/[^0-9-]/, "", $2); print $2; exit}' <<<"$raw")"
    fi

    watts="-1"
    if [[ -n "$voltage" && -n "$amperage" ]]; then
        watts="$(awk -v v="$voltage" -v i="$amperage" 'BEGIN { printf "%.2f", (v * (i < 0 ? -i : i)) / 1000000 }')"
    fi

    printf '%s %s %s %s\n' "${capacity:-0}" "${voltage:-0}" "${amperage:-0}" "$watts"
}

# Average CPU of the MagicWall process, as a second signal.
app_cpu() {
    local pid
    pid="$(pgrep -x MagicWall | head -1 || true)"
    [[ -z "$pid" ]] && { printf '0'; return; }
    ps -o %cpu= -p "$pid" 2>/dev/null | awk '{ sum += $1 } END { printf "%.1f", sum + 0 }'
}

run_state() {
    local state="$1"
    local samples_file="$out_dir/$state.csv"
    local prompt

    case "$state" in
        baseline) prompt="Stop every wallpaper (menu bar → “Stop all wallpapers”)" ;;
        compact)  prompt="Set a starter wallpaper with quality “Compact” (Settings → Starter wallpapers)" ;;
        high)     prompt="Set a starter wallpaper with quality “High quality” (Settings → Starter wallpapers)" ;;
        hd)       prompt="Set a 1080p clip as the wallpaper on every screen" ;;
        *)        echo "Unknown state: $state" >&2; exit 1 ;;
    esac

    echo
    echo "── state: $state"
    echo "   1. $prompt"
    echo "   2. Keep the desktop visible: no full-screen apps (the wallpaper pauses when hidden)."
    read -r -p "   Ready? Press Return to start sampling for $minutes minute(s)… " _

    local deadline=$(( $(date +%s) + minutes * 60 ))
    echo "epoch,clock,capacity_percent,voltage_mV,amperage_mA,watts,app_cpu_percent" >"$samples_file"

    while [[ $(date +%s) -lt $deadline ]]; do
        local capacity voltage amperage watts cpu left
        read -r capacity voltage amperage watts <<<"$(battery_sample)"
        cpu="$(app_cpu)"

        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$(date +%s)" "$(date +%H:%M:%S)" "$capacity" "$voltage" "$amperage" "$watts" "$cpu" \
            >>"$samples_file"

        left=$(( deadline - $(date +%s) ))
        printf '\r   %4ds left · %s%% · %s W · MagicWall CPU %s%%   ' "$left" "$capacity" "$watts" "$cpu"
        sleep "$interval"
    done
    printf '\n'
}

# --------------------------------------------------------------- run

echo "▸ MagicWall battery bench"
echo "  states:    $states_csv"
echo "  per state: $minutes minute(s), sample every ${interval}s"
echo "  output:    $out_dir"
echo "  reminder:  keep the screen brightness fixed for the whole run"

IFS=',' read -r -a states <<<"$states_csv"
for state in "${states[@]}"; do
    run_state "$state"
done

# --------------------------------------------------------------- summary

summary="$out_dir/summary.txt"
: >"$summary"

{
    echo "MagicWall battery bench — $(date '+%Y-%m-%d %H:%M')"
    echo "machine: $(sysctl -n hw.model 2>/dev/null || echo unknown) · macOS $(sw_vers -productVersion)"
    echo "minutes per state: $minutes"
    echo
    printf '%-9s %10s %9s %9s %13s\n' "state" "avg_watts" "avg_cpu%" "avg_cap%" "discharge_%/h"
    for state in "${states[@]}"; do
        awk -F',' -v state="$state" '
            NR == 1 { next }
            {
                n++
                if ($6 >= 0) { watts += $6; watts_n++ }
                cpu += $7
                cap += $3
                if (first_epoch == "") { first_epoch = $1; first_cap = $3 }
                last_epoch = $1; last_cap = $3
            }
            END {
                if (n == 0) { printf "%-9s %10s %9s %9s %13s\n", state, "-", "-", "-", "-"; exit }
                hours = (last_epoch - first_epoch) / 3600
                rate = hours > 0 ? (first_cap - last_cap) / hours : 0
                printf "%-9s %10s %9s %9s %13s\n",
                    state,
                    watts_n > 0 ? sprintf("%.2f", watts / watts_n) : "-",
                    sprintf("%.1f", cpu / n),
                    sprintf("%.1f", cap / n),
                    hours > 0 ? sprintf("%.1f", rate) : "-"
            }
        ' "$out_dir/$state.csv" >>"$summary"
    done
}

cat "$summary"
echo
echo "▸ Raw samples:"
ls -1 "$out_dir"
echo
echo "✓ Done. The wallpaper's cost is the delta between 'baseline' and a playing"
echo "  state; paste summary.txt (or its numbers) into README and the site FAQ."
