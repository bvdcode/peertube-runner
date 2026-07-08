#!/usr/bin/env bash

set -euo pipefail

IMAGE="${1:-}"

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 <image>" >&2
    exit 1
fi

run_tool_smoke_tests() {
    docker run --rm --entrypoint ffmpeg "$IMAGE" -version
    docker run --rm --entrypoint ffmpeg "$IMAGE" -encoders > ffmpeg-encoders.txt
    grep -q h264_nvenc ffmpeg-encoders.txt
    docker run --rm --entrypoint python "$IMAGE" -c "import ctranslate2; print(ctranslate2.__version__)"
    docker run --rm --entrypoint whisper-ctranslate2 "$IMAGE" --help
    docker run --rm --entrypoint peertube-runner "$IMAGE" --help
}

test_entrypoint_repairs_root_owned_volumes() {
    local run_id="${GITHUB_RUN_ID:-local}"
    local run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
    local volume_suffix="${run_id}-${run_attempt}-$$"
    local config_volume="peertube-runner-config-smoke-${volume_suffix}"
    local cache_volume="peertube-runner-cache-smoke-${volume_suffix}"
    local output_file="entrypoint-volume.log"
    local entrypoint_status

    docker volume rm -f "$config_volume" "$cache_volume" >/dev/null 2>&1 || true
    docker volume create "$config_volume" >/dev/null
    docker volume create "$cache_volume" >/dev/null

    trap "docker volume rm -f '$config_volume' '$cache_volume' >/dev/null 2>&1 || true" EXIT

    docker run --rm \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        -v "$cache_volume:/home/runner/.cache" \
        --entrypoint bash \
        "$IMAGE" \
        -lc 'mkdir -p /home/runner/.config/peertube-runner-nodejs/default /home/runner/.cache && chown -R root:root /home/runner/.config/peertube-runner-nodejs /home/runner/.cache'

    set +e
    docker run --rm \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        -v "$cache_volume:/home/runner/.cache" \
        "$IMAGE" > "$output_file" 2>&1
    entrypoint_status=$?
    set -e

    cat "$output_file"

    if [ "$entrypoint_status" -eq 0 ]; then
        echo "Expected entrypoint to fail without required registration environment" >&2
        exit 1
    fi

    grep -q "PEERTUBE_RUNNER_URL and PEERTUBE_RUNNER_TOKEN environment variables are required" "$output_file"

    if grep -q "Cannot create config directory" "$output_file"; then
        echo "Entrypoint did not repair the config volume ownership" >&2
        exit 1
    fi

    docker run --rm \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        -v "$cache_volume:/home/runner/.cache" \
        --entrypoint bash \
        "$IMAGE" \
        -lc 'gosu runner test -w /home/runner/.config/peertube-runner-nodejs/default && gosu runner test -w /home/runner/.cache'

    docker volume rm -f "$config_volume" "$cache_volume" >/dev/null 2>&1 || true
    trap - EXIT
}

test_registration_logs_are_concise() {
    local output_file="entrypoint-registration.log"
    local entrypoint_status

    set +e
    docker run --rm \
        -e PEERTUBE_RUNNER_URL=http://127.0.0.1:9 \
        -e PEERTUBE_RUNNER_TOKEN=ptrrt-00000000-0000-0000-0000-000000000000 \
        -e PEERTUBE_RUNNER_NAME=peertube-runner-smoke \
        -e PEERTUBE_RUNNER_NAME_CONFLICT=exit \
        "$IMAGE" > "$output_file" 2>&1
    entrypoint_status=$?
    set -e

    cat "$output_file"

    if [ "$entrypoint_status" -eq 0 ]; then
        echo "Expected registration to fail against an unavailable test endpoint" >&2
        exit 1
    fi

    grep -q "Failed to register runner" "$output_file"

    if grep -q '    err: {' "$output_file"; then
        echo "Default logs should not include structured runner error details" >&2
        exit 1
    fi

    if grep -q '"registrationToken"\|"stack"\|ptrrt-00000000-0000-0000-0000-000000000000' "$output_file"; then
        echo "Default logs exposed registration diagnostics that should be hidden" >&2
        exit 1
    fi

    if grep -q "Config file location\|Starting PeerTube Runner with command\|  URL:" "$output_file"; then
        echo "Default logs should not include wrapper startup details" >&2
        exit 1
    fi
}

run_tool_smoke_tests
test_entrypoint_repairs_root_owned_volumes
test_registration_logs_are_concise
