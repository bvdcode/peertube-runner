#!/usr/bin/env bash

set -e

CONFIG_SOURCE="/home/runner/config.toml"
CONFIG_TARGET="/home/runner/.config/peertube-runner-nodejs/default/config.toml"
CONFIG_DIR="/home/runner/.config/peertube-runner-nodejs/default"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check if config already exists in target location
if [ -f "$CONFIG_TARGET" ]; then
    echo "Config file already exists at $CONFIG_TARGET, using existing configuration"
    
    # Update dynamic parameters if environment variables are set
    if [ -n "$PEERTUBE_RUNNER_CONCURRENCY" ] || [ -n "$PEERTUBE_RUNNER_FFMPEG_THREADS" ] || [ -n "$PEERTUBE_RUNNER_FFMPEG_NICE" ] || [ -n "$PEERTUBE_RUNNER_ENGINE" ] || [ -n "$PEERTUBE_RUNNER_WHISPER_MODEL" ]; then
        echo "Updating dynamic parameters in existing config..."
        
        # Set default values for optional variables
        PEERTUBE_RUNNER_CONCURRENCY=${PEERTUBE_RUNNER_CONCURRENCY:-2}
        PEERTUBE_RUNNER_FFMPEG_THREADS=${PEERTUBE_RUNNER_FFMPEG_THREADS:-4}
        PEERTUBE_RUNNER_FFMPEG_NICE=${PEERTUBE_RUNNER_FFMPEG_NICE:-20}
        PEERTUBE_RUNNER_ENGINE=${PEERTUBE_RUNNER_ENGINE:-whisper-ctranslate2}
        PEERTUBE_RUNNER_WHISPER_MODEL=${PEERTUBE_RUNNER_WHISPER_MODEL:-large-v3}
        
        echo "  Concurrency: $PEERTUBE_RUNNER_CONCURRENCY"
        echo "  FFmpeg Threads: $PEERTUBE_RUNNER_FFMPEG_THREADS"
        echo "  FFmpeg Nice: $PEERTUBE_RUNNER_FFMPEG_NICE"
        echo "  Transcription Engine: $PEERTUBE_RUNNER_ENGINE"
        echo "  Whisper Model: $PEERTUBE_RUNNER_WHISPER_MODEL"
        
        # Update specific sections in existing config
        # Update [jobs] section
        sed -i "/^\[jobs\]/,/^\[/ { /^concurrency/c\concurrency = $PEERTUBE_RUNNER_CONCURRENCY ; }" "$CONFIG_TARGET"
        
        # Update [ffmpeg] section
        sed -i "/^\[ffmpeg\]/,/^\[/ { /^threads/c\threads = $PEERTUBE_RUNNER_FFMPEG_THREADS ; /^nice/c\nice = $PEERTUBE_RUNNER_FFMPEG_NICE ; }" "$CONFIG_TARGET"
        
        # Update [transcription] section
        sed -i "/^\[transcription\]/,/^\[/ { /^engine/c\engine = \"$PEERTUBE_RUNNER_ENGINE\" ; /^model/c\model = \"$PEERTUBE_RUNNER_WHISPER_MODEL\" ; }" "$CONFIG_TARGET"
        
        echo "Dynamic parameters updated successfully"
    fi
# Check if external config file exists in source location
elif [ -f "$CONFIG_SOURCE" ]; then
    echo "Found external config file at $CONFIG_SOURCE, copying to $CONFIG_TARGET"
    cp "$CONFIG_SOURCE" "$CONFIG_TARGET"
else
    echo "No config file found, generating from environment variables"
    
    # Check required environment variables
    if [ -z "$PEERTUBE_RUNNER_URL" ] || [ -z "$PEERTUBE_RUNNER_TOKEN" ]; then
        echo "ERROR: PEERTUBE_RUNNER_URL and PEERTUBE_RUNNER_TOKEN environment variables are required"
        exit 1
    fi
    
    # Set default values for optional variables
    PEERTUBE_RUNNER_CONCURRENCY=${PEERTUBE_RUNNER_CONCURRENCY:-2}
    PEERTUBE_RUNNER_FFMPEG_THREADS=${PEERTUBE_RUNNER_FFMPEG_THREADS:-4}
    PEERTUBE_RUNNER_FFMPEG_NICE=${PEERTUBE_RUNNER_FFMPEG_NICE:-20}
    PEERTUBE_RUNNER_ENGINE=${PEERTUBE_RUNNER_ENGINE:-whisper-ctranslate2}
    PEERTUBE_RUNNER_WHISPER_MODEL=${PEERTUBE_RUNNER_WHISPER_MODEL:-large-v3}
    PEERTUBE_RUNNER_NAME=${PEERTUBE_RUNNER_NAME:-peertube-runner-gpu}
    
    echo "Generating config file with the following settings:"
    echo "  URL: $PEERTUBE_RUNNER_URL"
    echo "  Runner Name: $PEERTUBE_RUNNER_NAME"
    echo "  Concurrency: $PEERTUBE_RUNNER_CONCURRENCY"
    echo "  FFmpeg Threads: $PEERTUBE_RUNNER_FFMPEG_THREADS"
    echo "  FFmpeg Nice: $PEERTUBE_RUNNER_FFMPEG_NICE"
    echo "  Transcription Engine: $PEERTUBE_RUNNER_ENGINE"
    echo "  Whisper Model: $PEERTUBE_RUNNER_WHISPER_MODEL"
    
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

    echo "Config file generated successfully"
    CONFIG_GENERATED="true"
fi

# Build the server command
SERVER_CMD="peertube-runner server"

# Check if job types are specified
if [ -n "$PEERTUBE_RUNNER_JOB_TYPES" ]; then
    echo "Configuring specific job types: $PEERTUBE_RUNNER_JOB_TYPES"
    
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
    echo "No specific job types configured, enabling all jobs"
fi

echo "Starting PeerTube Runner with command: $SERVER_CMD"
echo "Config file location: $CONFIG_TARGET"
echo "Config file contents:"
cat "$CONFIG_TARGET"
echo "----------------------------------------"

# Function to register runner
register_runner() {
    echo "Waiting for server to start before registering..."
    sleep 5
    
    echo "Registering runner with PeerTube instance..."
    peertube-runner register --url "$PEERTUBE_RUNNER_URL" --registration-token "$PEERTUBE_RUNNER_TOKEN" --runner-name "$PEERTUBE_RUNNER_NAME"
    
    if [ $? -eq 0 ]; then
        echo "Runner registered successfully!"
    else
        echo "Failed to register runner. Please check your URL and registration token."
        exit 1
    fi
}

# Start registration in background only if config was generated from environment variables
if [ "$CONFIG_GENERATED" = "true" ]; then
    register_runner &
fi

# Start the server
exec $SERVER_CMD

