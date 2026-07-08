#!/usr/bin/env bash

set -euo pipefail

log_wrapper() {
    local message="[peertube-runner-gpu ffmpeg] $1"
    local self_stderr
    local container_stderr

    echo "$message" >&2

    if [ ! -e /proc/1/fd/2 ]; then
        return
    fi

    self_stderr="$(readlink /proc/self/fd/2 2>/dev/null || true)"
    container_stderr="$(readlink /proc/1/fd/2 2>/dev/null || true)"

    if [ -n "$container_stderr" ] && [ "$self_stderr" != "$container_stderr" ]; then
        echo "$message" > /proc/1/fd/2 2>/dev/null || true
    fi
}

REAL_FFMPEG="${FFMPEG_REAL_PATH:-/usr/local/bin/ffmpeg-real}"
if [ ! -x "$REAL_FFMPEG" ]; then
    REAL_FFMPEG="$(command -v ffmpeg-real || true)"
fi

if [ -z "$REAL_FFMPEG" ]; then
    exit 1
fi

ORIG_ARGS=("$@")
NVENC_CHANGES=()

if [ "${#ORIG_ARGS[@]}" -eq 1 ]; then
    case "${ORIG_ARGS[0]}" in
        -encoders|-decoders|-formats|-version|-buildconf|-codecs|-protocols|-filters|-pix_fmts)
            exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
            ;;
    esac
fi

for arg in "${ORIG_ARGS[@]}"; do
    case "$arg" in
        libx264)
            NVENC_CHANGES+=("libx264 -> h264_nvenc")
            ;;
        libx265)
            NVENC_CHANGES+=("libx265 -> hevc_nvenc")
            ;;
    esac
done

if [ "${#NVENC_CHANGES[@]}" -eq 0 ]; then
    exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
fi

NEW_ARGS=()
skip_next=false
for i in "${!ORIG_ARGS[@]}"; do
    if $skip_next; then
        skip_next=false
        continue
    fi

    arg="${ORIG_ARGS[$i]}"
    case "$arg" in
        libx264)
            NEW_ARGS+=("h264_nvenc")
            ;;
        libx265)
            NEW_ARGS+=("hevc_nvenc")
            ;;
        -preset)
            NEW_ARGS+=("-preset" "fast")
            skip_next=true
            ;;
        -bf)
            NEW_ARGS+=("-bf" "3")
            skip_next=true
            ;;
        -b_strategy)
            skip_next=true
            ;;
        *)
            NEW_ARGS+=("$arg")
            ;;
    esac
done

IFS=", "
log_wrapper "NVENC attempt: ${NVENC_CHANGES[*]}"
unset IFS

set +e
"$REAL_FFMPEG" "${NEW_ARGS[@]}"
ffmpeg_status=$?
set -e

if [ "$ffmpeg_status" -eq 0 ]; then
    log_wrapper "NVENC command completed successfully"
    exit 0
fi

log_wrapper "NVENC command failed with status $ffmpeg_status; falling back to original FFmpeg command"
exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
