#!/usr/bin/env bash
set -e

# Logging function
log_info() {
    local timestamp=$(date '+%H:%M:%S')
    local milliseconds=$(date '+%3N')
    echo "[${timestamp}.${milliseconds}] INFO ($$): $1"
}

# Path to the real ffmpeg binary
REAL_FFMPEG="${FFMPEG_REAL_PATH:-/usr/local/bin/ffmpeg-real}"

if [ ! -x "$REAL_FFMPEG" ]; then
    REAL_FFMPEG="$(command -v ffmpeg-real || true)"
fi

if [ -z "$REAL_FFMPEG" ]; then
    log_info "ERROR: ffmpeg-real not found"
    exit 1
fi

# NVENC state cache flags (per container lifetime)
NVENC_OK_FLAG="/tmp/nvenc_ok"
NVENC_DISABLED_FLAG="/tmp/nvenc_disabled"

# Preserve original args for CPU fallback
ORIG_ARGS=("$@")

use_nvenc=false

if [ -f "$NVENC_DISABLED_FLAG" ]; then
    exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
fi

if [ -f "$NVENC_OK_FLAG" ]; then
    use_nvenc=true
else
    # One-time NVENC probe (tiny encode test)
    if "$REAL_FFMPEG" -loglevel error \
    -f lavfi -i "testsrc=size=1280x720:rate=30" \
    -t 0.1 \
    -pix_fmt yuv420p \
    -c:v h264_nvenc \
    -f null - >/dev/null 2>&1; then
        touch "$NVENC_OK_FLAG"
        use_nvenc=true
    else
        log_info "NVENC not available, falling back to CPU ffmpeg"
        touch "$NVENC_DISABLED_FLAG"
        exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
    fi
fi

if [ "$use_nvenc" = true ]; then
    NEW_ARGS=()
    
    # Rewrite x264/x265 encoders to NVENC equivalents
    for arg in "${ORIG_ARGS[@]}"; do
        case "$arg" in
            libx264)
                NEW_ARGS+=("h264_nvenc")
            ;;
            libx265)
                NEW_ARGS+=("hevc_nvenc")
            ;;
            *)
                NEW_ARGS+=("$arg")
            ;;
        esac
    done
    
    # Attempt NVENC run; if it fails, fall back to CPU for this job
    if "$REAL_FFMPEG" -hwaccel cuda -hwaccel_output_format cuda "${NEW_ARGS[@]}"; then
        exit 0
    else
        log_info "NVENC encode failed, falling back to CPU ffmpeg"
        exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
    fi
fi

exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
