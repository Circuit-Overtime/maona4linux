#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

# Collect read-only diagnostics for the MAONO/DCMT 31b2:0011 microphone.

set -u

readonly VID="31b2"
readonly PID="0011"
readonly USB_ID="${VID}:${PID}"

output_parent="captures/linux"

usage() {
    cat <<'EOF'
Usage: collect-debug.sh [--output-dir DIRECTORY] [--help]

Collect read-only USB, ALSA, kernel, and audio-session diagnostics for the
MAONO/DCMT USB microphone with VID:PID 31b2:0011.

Options:
  --output-dir DIRECTORY  Parent for the timestamped bundle
                          (default: captures/linux)
  -h, --help              Show this help

Review the resulting bundle for identifying information before sharing it.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --output-dir)
            if (( $# < 2 )); then
                printf 'error: --output-dir requires a directory\n' >&2
                exit 2
            fi
            output_parent=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

umask 077
timestamp=$(date '+%Y-%m-%d-%H%M%S')
bundle_base="${output_parent%/}/${timestamp}"
bundle=$bundle_base
suffix=0
created=0
if ! mkdir -p -- "$output_parent"; then
    printf 'error: cannot create output parent: %s\n' "$output_parent" >&2
    exit 1
fi
while (( suffix < 100 )); do
    if mkdir -- "$bundle" 2>/dev/null; then
        created=1
        break
    fi
    suffix=$((suffix + 1))
    bundle="${bundle_base}-${suffix}"
done
if (( created == 0 )); then
    printf 'error: cannot create a unique bundle under: %s\n' "$output_parent" >&2
    exit 1
fi

manifest="$bundle/manifest.txt"
: > "$manifest"

record_status() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$manifest"
}

capture() {
    local relative_path=$1
    shift
    local destination="$bundle/$relative_path"
    local stderr_path="${destination}.stderr"
    local status

    mkdir -p -- "${destination%/*}"
    "$@" > "$destination" 2> "$stderr_path"
    status=$?
    record_status "$status" "$relative_path" "$*"
    return 0
}

capture_optional() {
    local relative_path=$1
    local command_name=$2
    shift 2

    if command -v "$command_name" >/dev/null 2>&1; then
        capture "$relative_path" "$command_name" "$@"
    else
        mkdir -p -- "$bundle/${relative_path%/*}"
        printf 'optional command not found: %s\n' "$command_name" > "$bundle/$relative_path"
        record_status 127 "$relative_path" "$command_name $*"
    fi
}

capture_file() {
    local relative_path=$1
    local source_path=$2

    if [[ -r "$source_path" ]]; then
        capture "$relative_path" cat "$source_path"
    else
        mkdir -p -- "$bundle/${relative_path%/*}"
        printf 'not readable or not present: %s\n' "$source_path" > "$bundle/$relative_path"
        record_status 1 "$relative_path" "cat $source_path"
    fi
}

find_usb_devices() {
    local vendor_file product_file vendor product

    for vendor_file in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$vendor_file" ]] || continue
        product_file="${vendor_file%/*}/idProduct"
        [[ -r "$product_file" ]] || continue
        read -r vendor < "$vendor_file" || continue
        read -r product < "$product_file" || continue
        if [[ "${vendor,,}" == "$VID" && "${product,,}" == "$PID" ]]; then
            printf '%s\n' "${vendor_file%/*}"
        fi
    done
}

find_alsa_cards_for_usb_path() {
    local usb_path=$1
    local card_path resolved card_name

    for card_path in /sys/class/sound/card[0-9]*; do
        [[ -e "$card_path" ]] || continue
        resolved=$(readlink -f -- "$card_path/device" 2>/dev/null) || continue
        if [[ "$resolved" == "$usb_path"/* ]]; then
            card_name=${card_path##*/card}
            printf '%s\n' "$card_name"
        fi
    done
}

printf 'MAONO/DCMT Linux diagnostic bundle\n' > "$bundle/README.txt"
printf 'Target USB ID: %s\n' "$USB_ID" >> "$bundle/README.txt"
printf 'Created: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)" >> "$bundle/README.txt"
printf 'Review all files for identifying information before sharing.\n' >> "$bundle/README.txt"

capture system/uname.txt uname -a
capture_optional system/modinfo-snd-usb-audio.txt modinfo snd_usb_audio

capture_optional usb/lsusb.txt lsusb
capture_optional usb/lsusb-tree.txt lsusb -t
capture_optional usb/target-descriptors.txt lsusb -v -d "$USB_ID"
capture_optional usb/usb-devices.txt usb-devices

capture_file alsa/cards.txt /proc/asound/cards
capture_optional alsa/arecord-list.txt arecord -l
capture_optional alsa/aplay-list.txt aplay -l

mapfile -t usb_paths < <(find_usb_devices)
if (( ${#usb_paths[@]} == 0 )); then
    printf 'Target %s was not found in USB sysfs.\n' "$USB_ID" > "$bundle/usb/target-sysfs.txt"
    record_status 1 usb/target-sysfs.txt "find target in USB sysfs"
else
    printf '%s\n' "${usb_paths[@]}" > "$bundle/usb/target-sysfs.txt"
    record_status 0 usb/target-sysfs.txt "find target in USB sysfs"
fi

declare -A seen_cards=()
for usb_path in "${usb_paths[@]}"; do
    usb_node=${usb_path##*/}
    for attribute in idVendor idProduct manufacturer product bcdDevice bcdUSB speed busnum devnum configuration; do
        capture_file "usb/sysfs-${usb_node}/${attribute}.txt" "$usb_path/$attribute"
    done

    while IFS= read -r card; do
        [[ -n "$card" ]] || continue
        seen_cards[$card]=1
    done < <(find_alsa_cards_for_usb_path "$usb_path")
done

if (( ${#seen_cards[@]} == 0 )); then
    printf 'No ALSA card was resolved for target %s.\n' "$USB_ID" > "$bundle/alsa/target-cards.txt"
    record_status 1 alsa/target-cards.txt "resolve target ALSA cards"
else
    printf '%s\n' "${!seen_cards[@]}" | sort -n > "$bundle/alsa/target-cards.txt"
    record_status 0 alsa/target-cards.txt "resolve target ALSA cards"
fi

for card in "${!seen_cards[@]}"; do
    for stream_path in "/proc/asound/card${card}"/stream*; do
        [[ -e "$stream_path" ]] || continue
        capture_file "alsa/card${card}-${stream_path##*/}.txt" "$stream_path"
    done
    capture_optional "alsa/card${card}-controls.txt" amixer -c "$card" contents
done

capture_optional pipewire/wpctl-status.txt wpctl status
capture_optional pipewire/pw-dump.json pw-dump
capture_optional pipewire/pactl-sources.txt pactl list sources

printf 'Bundle created at: %s\n' "$bundle"
printf 'Review it for identifying information before sharing.\n'
