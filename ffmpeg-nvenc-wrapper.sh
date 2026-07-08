#!/usr/bin/env bash

set -euo pipefail

REAL_FFMPEG="${FFMPEG_REAL_PATH:-/usr/local/bin/ffmpeg-real}"
if [ ! -x "$REAL_FFMPEG" ]; then
    REAL_FFMPEG="$(command -v ffmpeg-real || true)"
fi

if [ -z "$REAL_FFMPEG" ]; then
    exit 1
fi

ORIG_ARGS=("$@")

if [ "${#ORIG_ARGS[@]}" -eq 1 ]; then
    case "${ORIG_ARGS[0]}" in
        -encoders|-decoders|-formats|-version|-buildconf|-codecs|-protocols|-filters|-pix_fmts)
            exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
            ;;
    esac
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

if "$REAL_FFMPEG" "${NEW_ARGS[@]}" 2>/dev/null; then
    exit 0
fi

exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
