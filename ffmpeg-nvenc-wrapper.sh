#!/usr/bin/env bash
set -e

LOG_FILE="/tmp/ffmpeg-wrapper.log"

# Logging function
log_info() {
    local timestamp=$(date '+%H:%M:%S')
    local milliseconds=$(date '+%3N')
    echo "[${timestamp}.${milliseconds}] INFO ($$): $1"
    echo "[${timestamp}.${milliseconds}] INFO ($$): $1" >> "$LOG_FILE"
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

if [ "${#ORIG_ARGS[@]}" -eq 1 ]; then
    case "${ORIG_ARGS[0]}" in
        -encoders|-decoders|-formats|-version|-buildconf|-codecs|-protocols|-filters|-pix_fmts)
            exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
        ;;
    esac
fi

use_nvenc=false

if [ -f "$NVENC_DISABLED_FLAG" ]; then
    log_info "NVENC disabled flag present, using CPU ffmpeg"
    exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
fi

if [ -f "$NVENC_OK_FLAG" ]; then
    has_libx264=false
    for ((i=0; i<${#ORIG_ARGS[@]}-1; i++)); do
        case "${ORIG_ARGS[$i]}" in
            -c:v|-codec:v|-vcodec)
                if [ "${ORIG_ARGS[$((i+1))]}" = "libx264" ] || [ "${ORIG_ARGS[$((i+1))]}" = "libx265" ]; then
                    has_libx264=true
                    break
                fi
            ;;
        esac
    done
    
    if [ "$has_libx264" = true ]; then
        log_info "NVENC_OK flag found, libx264/libx265 detected, using NVENC path"
        use_nvenc=true
    else
        exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
    fi
else
    log_info "Probing NVENC support..."
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
    log_info "Attempting NVENC encode, rewriting libx264 -> h264_nvenc"
    log_info "Original ffmpeg args: ${ORIG_ARGS[*]}"
    NEW_ARGS=()
    if "$REAL_FFMPEG" -y -loglevel error -hwaccel cuda -hwaccel_output_format cuda "${NEW_ARGS[@]}" 2>>"$LOG_FILE"
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
    
    log_info "Rewritten ffmpeg args for NVENC: ${NEW_ARGS[*]}"
    # Attempt NVENC run; if it fails, fall back to CPU for this job
    if "$REAL_FFMPEG" -y -loglevel error -hwaccel cuda -hwaccel_output_format cuda "${NEW_ARGS[@]}" >> "$LOG_FILE" 2>&1; then
        log_info "NVENC encode completed successfully"
        exit 0
    else
        rc=$?
        log_info "NVENC encode failed with code $rc, falling back to CPU ffmpeg"
        exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
    fi
fi

exec "$REAL_FFMPEG" "${ORIG_ARGS[@]}"
