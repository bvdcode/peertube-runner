#!/usr/bin/env bash

REAL_FFMPEG="${FFMPEG_REAL_PATH:-/usr/local/bin/ffmpeg-real}"
[ ! -x "$REAL_FFMPEG" ] && REAL_FFMPEG="$(command -v ffmpeg-real || true)"
[ -z "$REAL_FFMPEG" ] && exit 1

ORIG_ARGS=("$@")

if [ "${#ORIG_ARGS[@]}" -eq 1 ]; then
    case "${ORIG_ARGS[0]}" in
        -encoders|-decoders|-formats|-version|-buildconf|-codecs|-protocols|-filters|-pix_fmts)
            exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
        ;;
    esac
fi

NEW_ARGS=()
for arg in "${ORIG_ARGS[@]}"; do
    case "$arg" in
        libx264) NEW_ARGS+=("h264_nvenc") ;;
        libx265) NEW_ARGS+=("hevc_nvenc") ;;
        *) NEW_ARGS+=("$arg") ;;
    esac
done

if "$REAL_FFMPEG" -hwaccel cuda -hwaccel_output_format cuda "${NEW_ARGS[@]}" 2>/dev/null; then
    exit 0
else
    exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
fi
