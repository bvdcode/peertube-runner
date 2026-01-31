#!/usr/bin/env bash

set -e

# Logging function
log_info() {
    local timestamp=$(date '+%H:%M:%S')
    local milliseconds=$(date '+%3N')
    echo "[${timestamp}.${milliseconds}] INFO ($$): $1"
}

CONFIG_SOURCE="/home/runner/config.toml"
CONFIG_TARGET="/home/runner/.config/peertube-runner-nodejs/default/config.toml"
CONFIG_DIR="/home/runner/.config/peertube-runner-nodejs/default"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check if config already exists in target location
if [ -f "$CONFIG_TARGET" ]; then
    log_info "Config file already exists at $CONFIG_TARGET, using existing configuration"
    
    # Update dynamic parameters if environment variables are set
    if [ -n "$PEERTUBE_RUNNER_CONCURRENCY" ] || [ -n "$PEERTUBE_RUNNER_FFMPEG_THREADS" ] || [ -n "$PEERTUBE_RUNNER_FFMPEG_NICE" ] || [ -n "$PEERTUBE_RUNNER_ENGINE" ] || [ -n "$PEERTUBE_RUNNER_WHISPER_MODEL" ]; then
        log_info "Updating dynamic parameters in existing config..."
        
        # Set default values for optional variables
        PEERTUBE_RUNNER_CONCURRENCY=${PEERTUBE_RUNNER_CONCURRENCY:-2}
        PEERTUBE_RUNNER_FFMPEG_THREADS=${PEERTUBE_RUNNER_FFMPEG_THREADS:-4}
        PEERTUBE_RUNNER_FFMPEG_NICE=${PEERTUBE_RUNNER_FFMPEG_NICE:-20}
        PEERTUBE_RUNNER_ENGINE=${PEERTUBE_RUNNER_ENGINE:-whisper-ctranslate2}
        PEERTUBE_RUNNER_WHISPER_MODEL=${PEERTUBE_RUNNER_WHISPER_MODEL:-large-v3}
        
        log_info "  Concurrency: $PEERTUBE_RUNNER_CONCURRENCY"
        log_info "  FFmpeg Threads: $PEERTUBE_RUNNER_FFMPEG_THREADS"
        log_info "  FFmpeg Nice: $PEERTUBE_RUNNER_FFMPEG_NICE"
        log_info "  Transcription Engine: $PEERTUBE_RUNNER_ENGINE"
        log_info "  Whisper Model: $PEERTUBE_RUNNER_WHISPER_MODEL"
        
        # Update config values in-place (compatible with GNU and BusyBox sed)
        sed -i "s/^concurrency *=.*/concurrency = $PEERTUBE_RUNNER_CONCURRENCY/" "$CONFIG_TARGET"
        sed -i "s/^threads *=.*/threads = $PEERTUBE_RUNNER_FFMPEG_THREADS/" "$CONFIG_TARGET"
        sed -i "s/^nice *=.*/nice = $PEERTUBE_RUNNER_FFMPEG_NICE/" "$CONFIG_TARGET"
        sed -i "s/^engine *=.*/engine = \"$PEERTUBE_RUNNER_ENGINE\"/" "$CONFIG_TARGET"
        sed -i "s/^model *=.*/model = \"$PEERTUBE_RUNNER_WHISPER_MODEL\"/" "$CONFIG_TARGET"
        log_info "Dynamic parameters updated successfully"
    fi
# Check if external config file exists in source location
elif [ -f "$CONFIG_SOURCE" ]; then
    log_info "Found external config file at $CONFIG_SOURCE, copying to $CONFIG_TARGET"
    cp "$CONFIG_SOURCE" "$CONFIG_TARGET"
else
    log_info "No config file found, generating from environment variables"
    
    # Check required environment variables
    if [ -z "$PEERTUBE_RUNNER_URL" ] || [ -z "$PEERTUBE_RUNNER_TOKEN" ]; then
        log_info "ERROR: PEERTUBE_RUNNER_URL and PEERTUBE_RUNNER_TOKEN environment variables are required"
        exit 1
    fi
    
    # Set default values for optional variables
    PEERTUBE_RUNNER_CONCURRENCY=${PEERTUBE_RUNNER_CONCURRENCY:-2}
    PEERTUBE_RUNNER_FFMPEG_THREADS=${PEERTUBE_RUNNER_FFMPEG_THREADS:-4}
    PEERTUBE_RUNNER_FFMPEG_NICE=${PEERTUBE_RUNNER_FFMPEG_NICE:-20}
    PEERTUBE_RUNNER_ENGINE=${PEERTUBE_RUNNER_ENGINE:-whisper-ctranslate2}
    PEERTUBE_RUNNER_WHISPER_MODEL=${PEERTUBE_RUNNER_WHISPER_MODEL:-large-v3}
    
    log_info "Generating config file with the following settings:"
    log_info "  URL: $PEERTUBE_RUNNER_URL"
    log_info "  Runner Name: $PEERTUBE_RUNNER_NAME"
    log_info "  Concurrency: $PEERTUBE_RUNNER_CONCURRENCY"
    log_info "  FFmpeg Threads: $PEERTUBE_RUNNER_FFMPEG_THREADS"
    log_info "  FFmpeg Nice: $PEERTUBE_RUNNER_FFMPEG_NICE"
    log_info "  Transcription Engine: $PEERTUBE_RUNNER_ENGINE"
    log_info "  Whisper Model: $PEERTUBE_RUNNER_WHISPER_MODEL"
    
    # Generate config.toml file without registeredInstances
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

    log_info "Config file generated successfully"
    CONFIG_GENERATED="true"
fi

# Set default runner name (used for registration)
PEERTUBE_RUNNER_NAME=${PEERTUBE_RUNNER_NAME:-peertube-runner-gpu}

# Build the server command
SERVER_CMD="peertube-runner server"

# Check if job types are specified
if [ -n "$PEERTUBE_RUNNER_JOB_TYPES" ]; then
    log_info "Configuring specific job types: $PEERTUBE_RUNNER_JOB_TYPES"
    
    # Split job types by comma and add --enable-job for each
    IFS=',' read -ra JOB_TYPES <<< "$PEERTUBE_RUNNER_JOB_TYPES"
    for job_type in "${JOB_TYPES[@]}"; do
        # Trim whitespace
        job_type=$(echo "$job_type" | xargs)
        if [ -n "$job_type" ]; then
            SERVER_CMD="$SERVER_CMD --enable-job $job_type"
        fi
    done
else
    log_info "No specific job types configured, enabling all jobs"
fi

log_info "Starting PeerTube Runner with command: $SERVER_CMD"
log_info "Config file location: $CONFIG_TARGET"

# Check if runner is registered by looking for registeredInstances section
NEEDS_REGISTRATION=false
if ! grep -q "^\[\[registeredInstances\]\]" "$CONFIG_TARGET" 2>/dev/null; then
    log_info "No registered instances found in config, registration needed"
    NEEDS_REGISTRATION=true
else
    log_info "Found registered instances in config"
fi

# Function to register runner (must be called after server is started)
register_runner() {
    local runner_name="$PEERTUBE_RUNNER_NAME"
    local name_conflict_action="${PEERTUBE_RUNNER_NAME_CONFLICT:-exit}"
    local socket_path="/home/runner/.local/share/peertube-runner-nodejs/default/peertube-runner.sock"
    
    log_info "Name conflict resolution mode: $name_conflict_action"
    
    # Wait for server socket to be available
    log_info "Waiting for PeerTube Runner server socket..."
    local retries=0
    while [ ! -S "$socket_path" ] && [ $retries -lt 30 ]; do
        sleep 1
        retries=$((retries + 1))
    done
    
    if [ ! -S "$socket_path" ]; then
        log_info "ERROR: Server socket not available after 30 seconds"
        return 1
    fi
    log_info "Server socket is ready"
    
    while true; do
        log_info "Registering runner with name '$runner_name'..."
        
        # Capture output and status (set +e to prevent exit on registration failure)
        set +e
        REG_OUTPUT=$(peertube-runner register --url "$PEERTUBE_RUNNER_URL" --registration-token "$PEERTUBE_RUNNER_TOKEN" --runner-name "$runner_name" 2>&1)
        REG_STATUS=$?
        set -e
        
        # Treat registration as successful only if the config now contains a runner token.
        if grep -q '^\[\[registeredInstances\]\]' "$CONFIG_TARGET" 2>/dev/null && grep -q '^runnerToken *= *"ptrt-' "$CONFIG_TARGET" 2>/dev/null; then
            log_info "Runner registered successfully with name '$runner_name'!"
            return 0
        fi

        if echo "$REG_OUTPUT" | grep -q 'This runner name already exists on this instance' 2>/dev/null; then
            log_info "Runner name '$runner_name' already exists on this instance"

            case "$name_conflict_action" in
                "auto")
                    # Generate unique name with timestamp
                    local timestamp
                    timestamp=$(date +%s)
                    runner_name="${PEERTUBE_RUNNER_NAME}-${timestamp}"
                    log_info "Auto-generating unique name: '$runner_name'"
                    ;;
                "wait")
                    log_info "Waiting for existing runner to be removed. Will retry in 30 seconds..."
                    log_info "Please remove the existing runner '$runner_name' from your PeerTube instance or set PEERTUBE_RUNNER_NAME_CONFLICT=auto"
                    sleep 30
                    ;;
                "exit"|*)
                    log_info "Runner name conflict detected. Please either:"
                    log_info "  1. Remove the existing runner '$runner_name' from your PeerTube instance"
                    log_info "  2. Set PEERTUBE_RUNNER_NAME_CONFLICT=auto to auto-generate unique names"
                    log_info "  3. Set PEERTUBE_RUNNER_NAME_CONFLICT=wait to wait for manual removal"
                    log_info "  4. Change PEERTUBE_RUNNER_NAME to a different value"
                    exit 1
                    ;;
            esac
        else
            if [ $REG_STATUS -eq 0 ]; then
                log_info "Registration command exited successfully, but no runner token was written to config. Treating as failure."
            fi
            log_info "Failed to register runner. Output: $REG_OUTPUT"
            exit 1
        fi
    done
}

# Start registration in background if needed (server must be running first)
if [ "$CONFIG_GENERATED" = "true" ] || [ "$NEEDS_REGISTRATION" = "true" ]; then
    if [ -n "$PEERTUBE_RUNNER_URL" ] && [ -n "$PEERTUBE_RUNNER_TOKEN" ]; then
        register_runner &
        REGISTER_PID=$!
    else
        log_info "Registration needed but PEERTUBE_RUNNER_URL or PEERTUBE_RUNNER_TOKEN not provided"
        exit 1
    fi
fi

# Start the server (this will allow register_runner to connect via socket)
exec $SERVER_CMD

