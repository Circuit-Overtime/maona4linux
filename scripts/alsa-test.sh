#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

# Exercise the raw ALSA capture path for the MAONO/DCMT 31b2:0011 microphone.

set -u

readonly VID="31b2"
readonly PID="0011"
readonly USB_ID="${VID}:${PID}"
readonly USB_SYSFS_ROOT="${MAONO_USB_SYSFS_ROOT:-/sys/bus/usb/devices}"
readonly SOUND_SYSFS_ROOT="${MAONO_SOUND_SYSFS_ROOT:-/sys/class/sound}"
readonly PROC_ASOUND_ROOT="${MAONO_PROC_ASOUND_ROOT:-/proc/asound}"

duration=10
output_parent="captures/linux"

usage() {
    cat <<'EOF'
Usage: alsa-test.sh [--duration SECONDS] [--output-dir DIRECTORY] [--help]

Discover the MAONO/DCMT 31b2:0011 microphone's ALSA capture device, print its
hardware parameters, and make a raw ALSA recording using parameters advertised
in /proc/asound.

Options:
  --duration SECONDS     Recording length (default: 10)
  --output-dir DIRECTORY Parent for the timestamped result directory
                         (default: captures/linux)
  -h, --help             Show this help

This script bypasses PipeWire and does not change mixer controls.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --duration)
            (( $# >= 2 )) || die "--duration requires a value"
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "duration must be a positive integer"
            duration=$2
            shift 2
            ;;
        --output-dir)
            (( $# >= 2 )) || die "--output-dir requires a directory"
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

command -v arecord >/dev/null 2>&1 || die "arecord is required (usually provided by alsa-utils)"

umask 077
timestamp=$(date '+%Y-%m-%d-%H%M%S')
result_base="${output_parent%/}/${timestamp}-alsa"
result_dir=$result_base
created=0
suffix=0

mkdir -p -- "$output_parent" || die "cannot create output parent: $output_parent"
while (( suffix < 100 )); do
    if mkdir -- "$result_dir" 2>/dev/null; then
        created=1
        break
    fi
    suffix=$((suffix + 1))
    result_dir="${result_base}-${suffix}"
done
(( created == 1 )) || die "cannot create a unique result directory under: $output_parent"

log="$result_dir/test.log"
: > "$log"

log_line() {
    printf '%s\n' "$*" | tee -a "$log"
}

find_usb_devices() {
    local vendor_file product_file vendor product

    for vendor_file in "$USB_SYSFS_ROOT"/*/idVendor; do
        [[ -f "$vendor_file" ]] || continue
        product_file="${vendor_file%/*}/idProduct"
        [[ -r "$product_file" ]] || continue
        read -r vendor < "$vendor_file" || continue
        read -r product < "$product_file" || continue
        if [[ "${vendor,,}" == "$VID" && "${product,,}" == "$PID" ]]; then
            readlink -f -- "${vendor_file%/*}"
        fi
    done
}

find_cards() {
    local usb_path=$1
    local card_path resolved

    for card_path in "$SOUND_SYSFS_ROOT"/card[0-9]*; do
        [[ -e "$card_path" ]] || continue
        resolved=$(readlink -f -- "$card_path/device" 2>/dev/null) || continue
        if [[ "$resolved" == "$usb_path"/* ]]; then
            printf '%s\n' "${card_path##*/card}"
        fi
    done
}

find_capture_devices() {
    local card=$1
    local pcm_path name

    for pcm_path in "$SOUND_SYSFS_ROOT"/pcmC"${card}"D*c; do
        [[ -e "$pcm_path" ]] || continue
        name=${pcm_path##*/}
        name=${name#pcmC"${card}"D}
        printf '%s\n' "${name%c}"
    done
}

descriptor_value() {
    local label=$1
    local descriptor=$2

    awk -v label="$label" '
        /^Capture:/ { capture = 1; next }
        capture && $1 == label ":" { print $2; exit }
    ' "$descriptor"
}

descriptor_rate() {
    local descriptor=$1

    awk '
        /^Capture:/ { capture = 1; next }
        capture && $1 == "Rates:" {
            line = $0
            if (line ~ /(^|[^0-9])48000([^0-9]|$)/) {
                print 48000
                exit
            }
            sub(/^[^0-9]*/, "", line)
            if (match(line, /^[0-9]+/)) {
                print substr(line, RSTART, RLENGTH)
                exit
            }
        }
    ' "$descriptor"
}

mapfile -t usb_paths < <(find_usb_devices)
if (( ${#usb_paths[@]} == 0 )); then
    log_line "Target $USB_ID was not found in USB sysfs."
    log_line "Result directory: $result_dir"
    exit 1
fi
if (( ${#usb_paths[@]} > 1 )); then
    printf '%s\n' "${usb_paths[@]}" > "$result_dir/usb-devices.txt"
    log_line "Multiple $USB_ID USB devices were found; refusing to choose silently."
    log_line "Paths were saved to $result_dir/usb-devices.txt"
    exit 1
fi

usb_path=${usb_paths[0]}
printf '%s\n' "$usb_path" > "$result_dir/usb-device.txt"

mapfile -t cards < <(find_cards "$usb_path")
(( ${#cards[@]} > 0 )) || die "the USB device was found at $usb_path, but no ALSA card is linked to it"
if (( ${#cards[@]} > 1 )); then
    printf '%s\n' "${cards[@]}" > "$result_dir/alsa-cards.txt"
    die "multiple ALSA cards are linked to the device; refusing to choose silently"
fi
card=${cards[0]}

mapfile -t devices < <(find_capture_devices "$card")
(( ${#devices[@]} > 0 )) || die "ALSA card $card has no capture PCM"
if (( ${#devices[@]} > 1 )); then
    printf '%s\n' "${devices[@]}" > "$result_dir/alsa-devices.txt"
    die "ALSA card $card has multiple capture PCMs; refusing to choose silently"
fi
device=${devices[0]}

descriptor="$PROC_ASOUND_ROOT/card${card}/stream${device}"
[[ -r "$descriptor" ]] || die "stream descriptor is not readable: $descriptor"
cp -- "$descriptor" "$result_dir/stream${device}.txt" || die "cannot save the stream descriptor"

format=$(descriptor_value Format "$descriptor")
channels=$(descriptor_value Channels "$descriptor")
rate=$(descriptor_rate "$descriptor")

[[ -n "$format" ]] || die "no advertised capture format found in $descriptor"
[[ "$channels" =~ ^[1-9][0-9]*$ ]] || die "no advertised capture channel count found in $descriptor"
[[ "$rate" =~ ^[1-9][0-9]*$ ]] || die "no advertised capture rate found in $descriptor"

alsa_device="hw:${card},${device}"
audio_file="$result_dir/capture-${format}-${channels}ch-${rate}hz.wav"

log_line "USB device: $usb_path"
log_line "ALSA device: $alsa_device"
log_line "Parameters: format=$format channels=$channels rate=$rate duration=${duration}s"
log_line "Hardware parameters: $result_dir/hw-params.txt"

arecord -D "$alsa_device" -f "$format" -c "$channels" -r "$rate" \
    --dump-hw-params -d 1 -t raw /dev/null \
    > "$result_dir/hw-params.txt" 2>&1
hw_status=$?
printf 'hw_params_exit=%s\n' "$hw_status" >> "$log"
if (( hw_status != 0 )); then
    log_line "Hardware-parameter probe failed with exit $hw_status; recording was not attempted."
    exit "$hw_status"
fi
cat -- "$result_dir/hw-params.txt"

log_line "Recording to: $audio_file"
arecord -D "$alsa_device" -f "$format" -c "$channels" -r "$rate" \
    -d "$duration" -t wav "$audio_file" \
    > "$result_dir/arecord.stdout.txt" 2> "$result_dir/arecord.stderr.txt"
record_status=$?
printf 'record_exit=%s\n' "$record_status" >> "$log"

if command -v dmesg >/dev/null 2>&1; then
    usb_node=${usb_path##*/}
    dmesg --level=err,warn 2> "$result_dir/dmesg.stderr.txt" \
        | awk -v usb_node="$usb_node" \
            'index($0, usb_node) || /31b2|0011|snd_usb_audio|snd-usb-audio/' \
            > "$result_dir/dmesg-warnings.txt"
    printf 'dmesg_exit=%s\n' "${PIPESTATUS[0]}" >> "$log"
fi

if (( record_status != 0 )); then
    log_line "Recording failed with exit $record_status."
    exit "$record_status"
fi

log_line "Recording completed successfully."
log_line "Listen for silence, distortion, dropouts, and incorrect speed before reporting success."
