#!/usr/bin/env bash

set -euo pipefail

log_info() {
    local timestamp
    local milliseconds
    timestamp=$(date '+%H:%M:%S')
    milliseconds=$(date '+%3N')
    echo "[${timestamp}.${milliseconds}] INFO ($$): $1"
}

CONFIG_SOURCE="/home/runner/config.toml"
CONFIG_ROOT="/home/runner/.config/peertube-runner-nodejs"
CONFIG_DIR="$CONFIG_ROOT/default"
CONFIG_TARGET="$CONFIG_DIR/config.toml"
RUNNER_DATA_ROOT="/home/runner/.local/share/peertube-runner-nodejs"
RUNNER_DATA_DIR="$RUNNER_DATA_ROOT/default"
SOCKET_PATH="$RUNNER_DATA_DIR/peertube-runner.sock"
CACHE_DIR="/home/runner/.cache"
CONFIG_GENERATED=false
NEEDS_REGISTRATION=false
SERVER_PID=""

PEERTUBE_RUNNER_NAME="${PEERTUBE_RUNNER_NAME:-peertube-runner-gpu}"

prepare_runner_storage() {
    mkdir -p "$CONFIG_DIR" "$CACHE_DIR" "$RUNNER_DATA_DIR"
    chown -R runner:runner "$CONFIG_ROOT" "$CACHE_DIR" "$RUNNER_DATA_ROOT"
}

if [ "$(id -u)" -eq 0 ]; then
    prepare_runner_storage
    exec gosu runner "$0" "$@"
fi

ensure_writable_directory() {
    local directory="$1"
    local description="$2"

    if ! mkdir -p "$directory"; then
        log_info "ERROR: Cannot create $description directory at $directory"
        log_info "Check that the mounted Docker volume is writable by the runner user"
        exit 1
    fi

    if [ ! -w "$directory" ]; then
        log_info "ERROR: $description directory is not writable at $directory"
        log_info "Check that the mounted Docker volume is writable by the runner user"
        exit 1
    fi
}

ensure_writable_directory "$CONFIG_DIR" "config"
ensure_writable_directory "$CACHE_DIR" "cache"
ensure_writable_directory "$RUNNER_DATA_DIR" "runtime data"

runner_token_written() {
    grep -q '^\[\[registeredInstances\]\]' "$CONFIG_TARGET" 2>/dev/null &&
        grep -q '^runnerToken *= *"ptrt-' "$CONFIG_TARGET" 2>/dev/null
}

apply_dynamic_config() {
    if [ -z "${PEERTUBE_RUNNER_CONCURRENCY:-}" ] &&
        [ -z "${PEERTUBE_RUNNER_FFMPEG_THREADS:-}" ] &&
        [ -z "${PEERTUBE_RUNNER_FFMPEG_NICE:-}" ] &&
        [ -z "${PEERTUBE_RUNNER_ENGINE:-}" ] &&
        [ -z "${PEERTUBE_RUNNER_WHISPER_MODEL:-}" ]; then
        return
    fi

    PEERTUBE_RUNNER_CONCURRENCY="${PEERTUBE_RUNNER_CONCURRENCY:-2}"
    PEERTUBE_RUNNER_FFMPEG_THREADS="${PEERTUBE_RUNNER_FFMPEG_THREADS:-4}"
    PEERTUBE_RUNNER_FFMPEG_NICE="${PEERTUBE_RUNNER_FFMPEG_NICE:-20}"
    PEERTUBE_RUNNER_ENGINE="${PEERTUBE_RUNNER_ENGINE:-whisper-ctranslate2}"
    PEERTUBE_RUNNER_WHISPER_MODEL="${PEERTUBE_RUNNER_WHISPER_MODEL:-large-v3}"

    log_info "Updating config parameters"
    log_info "  Concurrency: $PEERTUBE_RUNNER_CONCURRENCY"
    log_info "  FFmpeg Threads: $PEERTUBE_RUNNER_FFMPEG_THREADS"
    log_info "  FFmpeg Nice: $PEERTUBE_RUNNER_FFMPEG_NICE"
    log_info "  Transcription Engine: $PEERTUBE_RUNNER_ENGINE"
    log_info "  Whisper Model: $PEERTUBE_RUNNER_WHISPER_MODEL"

    sed -i "s/^concurrency *=.*/concurrency = $PEERTUBE_RUNNER_CONCURRENCY/" "$CONFIG_TARGET"
    sed -i "s/^threads *=.*/threads = $PEERTUBE_RUNNER_FFMPEG_THREADS/" "$CONFIG_TARGET"
    sed -i "s/^nice *=.*/nice = $PEERTUBE_RUNNER_FFMPEG_NICE/" "$CONFIG_TARGET"
    sed -i "s/^engine *=.*/engine = \"$PEERTUBE_RUNNER_ENGINE\"/" "$CONFIG_TARGET"
    sed -i "s/^model *=.*/model = \"$PEERTUBE_RUNNER_WHISPER_MODEL\"/" "$CONFIG_TARGET"
}

generate_config_from_environment() {
    if [ -z "${PEERTUBE_RUNNER_URL:-}" ] || [ -z "${PEERTUBE_RUNNER_TOKEN:-}" ]; then
        log_info "ERROR: PEERTUBE_RUNNER_URL and PEERTUBE_RUNNER_TOKEN environment variables are required"
        exit 1
    fi

    PEERTUBE_RUNNER_CONCURRENCY="${PEERTUBE_RUNNER_CONCURRENCY:-2}"
    PEERTUBE_RUNNER_FFMPEG_THREADS="${PEERTUBE_RUNNER_FFMPEG_THREADS:-4}"
    PEERTUBE_RUNNER_FFMPEG_NICE="${PEERTUBE_RUNNER_FFMPEG_NICE:-20}"
    PEERTUBE_RUNNER_ENGINE="${PEERTUBE_RUNNER_ENGINE:-whisper-ctranslate2}"
    PEERTUBE_RUNNER_WHISPER_MODEL="${PEERTUBE_RUNNER_WHISPER_MODEL:-large-v3}"

    log_info "Generating config file"
    log_info "  URL: $PEERTUBE_RUNNER_URL"
    log_info "  Runner Name: $PEERTUBE_RUNNER_NAME"
    log_info "  Concurrency: $PEERTUBE_RUNNER_CONCURRENCY"
    log_info "  FFmpeg Threads: $PEERTUBE_RUNNER_FFMPEG_THREADS"
    log_info "  FFmpeg Nice: $PEERTUBE_RUNNER_FFMPEG_NICE"
    log_info "  Transcription Engine: $PEERTUBE_RUNNER_ENGINE"
    log_info "  Whisper Model: $PEERTUBE_RUNNER_WHISPER_MODEL"

    cat > "$CONFIG_TARGET" << EOF
[jobs]
concurrency = $PEERTUBE_RUNNER_CONCURRENCY

[ffmpeg]
threads = $PEERTUBE_RUNNER_FFMPEG_THREADS
nice = $PEERTUBE_RUNNER_FFMPEG_NICE

[transcription]
engine = "$PEERTUBE_RUNNER_ENGINE"
model = "$PEERTUBE_RUNNER_WHISPER_MODEL"
EOF

    CONFIG_GENERATED=true
}

if [ -f "$CONFIG_TARGET" ]; then
    log_info "Using existing config file at $CONFIG_TARGET"
    apply_dynamic_config
elif [ -f "$CONFIG_SOURCE" ]; then
    log_info "Copying config file from $CONFIG_SOURCE to $CONFIG_TARGET"
    cp "$CONFIG_SOURCE" "$CONFIG_TARGET"
else
    generate_config_from_environment
fi

if ! runner_token_written; then
    log_info "No registered runner token found in config"
    NEEDS_REGISTRATION=true
else
    log_info "Registered runner token found in config"
fi

SERVER_CMD=(peertube-runner server)

if [ -n "${PEERTUBE_RUNNER_JOB_TYPES:-}" ]; then
    log_info "Configuring job types: $PEERTUBE_RUNNER_JOB_TYPES"

    IFS=',' read -r -a JOB_TYPES <<< "$PEERTUBE_RUNNER_JOB_TYPES"
    for job_type in "${JOB_TYPES[@]}"; do
        job_type=$(echo "$job_type" | xargs)
        if [ -n "$job_type" ]; then
            SERVER_CMD+=(--enable-job "$job_type")
        fi
    done
else
    log_info "No specific job types configured"
fi

printf -v SERVER_CMD_DISPLAY '%q ' "${SERVER_CMD[@]}"
log_info "Starting PeerTube Runner with command: ${SERVER_CMD_DISPLAY% }"
log_info "Config file location: $CONFIG_TARGET"

register_runner() {
    local runner_name="$PEERTUBE_RUNNER_NAME"
    local name_conflict_action="${PEERTUBE_RUNNER_NAME_CONFLICT:-exit}"
    local reg_output
    local reg_status

    log_info "Name conflict resolution mode: $name_conflict_action"

    while true; do
        log_info "Registering runner with name '$runner_name'"

        set +e
        reg_output=$(peertube-runner register --url "$PEERTUBE_RUNNER_URL" --registration-token "$PEERTUBE_RUNNER_TOKEN" --runner-name "$runner_name" 2>&1)
        reg_status=$?
        set -e

        if runner_token_written; then
            log_info "Runner registered successfully with name '$runner_name'"
            return 0
        fi

        if echo "$reg_output" | grep -q 'This runner name already exists on this instance' 2>/dev/null; then
            log_info "Runner name '$runner_name' already exists on this instance"

            case "$name_conflict_action" in
                "auto")
                    local timestamp
                    timestamp=$(date +%s)
                    runner_name="${PEERTUBE_RUNNER_NAME}-${timestamp}"
                    log_info "Using generated runner name '$runner_name'"
                    ;;
                "wait")
                    log_info "Waiting for existing runner to be removed"
                    sleep 30
                    ;;
                "exit"|*)
                    log_info "Runner name conflict detected"
                    log_info "Remove the existing runner, change PEERTUBE_RUNNER_NAME, or set PEERTUBE_RUNNER_NAME_CONFLICT to auto or wait"
                    return 1
                    ;;
            esac
        else
            if [ "$reg_status" -eq 0 ]; then
                log_info "Registration command exited successfully, but no runner token was written to config"
            fi
            log_info "Failed to register runner. Output: $reg_output"
            return 1
        fi
    done
}

wait_for_server_socket() {
    local server_pid="$1"
    local retries=0

    log_info "Waiting for PeerTube Runner server socket"
    while [ ! -S "$SOCKET_PATH" ] && [ "$retries" -lt 30 ]; do
        if ! kill -0 "$server_pid" 2>/dev/null; then
            log_info "ERROR: PeerTube Runner server exited before creating socket"
            wait "$server_pid" || true
            return 1
        fi

        sleep 1
        retries=$((retries + 1))
    done

    if [ ! -S "$SOCKET_PATH" ]; then
        log_info "ERROR: Server socket not available after 30 seconds"
        return 1
    fi

    log_info "Server socket is ready"
}

stop_server() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
        wait "$SERVER_PID" || true
    fi
}

if [ "$NEEDS_REGISTRATION" = "true" ] || [ "$CONFIG_GENERATED" = "true" ]; then
    if [ -z "${PEERTUBE_RUNNER_URL:-}" ] || [ -z "${PEERTUBE_RUNNER_TOKEN:-}" ]; then
        log_info "Registration needed but PEERTUBE_RUNNER_URL or PEERTUBE_RUNNER_TOKEN is missing"
        exit 1
    fi

    "${SERVER_CMD[@]}" &
    SERVER_PID=$!
    trap stop_server INT TERM EXIT

    wait_for_server_socket "$SERVER_PID"
    register_runner

    wait "$SERVER_PID"
else
    exec "${SERVER_CMD[@]}"
fi
