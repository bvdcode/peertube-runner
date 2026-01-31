#!/usr/bin/env bash

set -e

# Logging function
log_info() {
    local timestamp=$(date '+%H:%M:%S')
    local milliseconds=$(date '+%3N')
    echo "[${timestamp}.${milliseconds}] INFO ($$): $1"
}


#!/usr/bin/env bash
set -e

# Where is the real ffmpeg located
REAL_FFMPEG="${FFMPEG_REAL_PATH:-/usr/local/bin/ffmpeg-real}"

# If the specified path is not executable, try to find ffmpeg-real in PATH
if [ ! -x "$REAL_FFMPEG" ]; then
    REAL_FFMPEG="$(command -v ffmpeg-real || true)"
    if [ -z "$REAL_FFMPEG" ]; then
        echo "ffmpeg-real not found" >&2
        exit 1
    fi
fi

NEW_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        libx264)
            # Change libx264 to h264_nvenc for NVIDIA hardware acceleration
            NEW_ARGS+=("h264_nvenc")
        ;;
        libx265)
            NEW_ARGS+=("hevc_nvenc")
        ;;
        *)
            NEW_ARGS+=("$1")
        ;;
    esac
    shift
done

# Add hardware acceleration flags
exec "$REAL_FFMPEG" -hwaccel cuda -hwaccel_output_format cuda "${NEW_ARGS[@]}"
