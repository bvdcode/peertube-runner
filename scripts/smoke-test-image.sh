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
    grep -Fq h264_nvenc ffmpeg-encoders.txt
    docker run --rm --entrypoint python "$IMAGE" -c "import ctranslate2; print(ctranslate2.__version__)"
    docker run --rm --entrypoint whisper-ctranslate2 "$IMAGE" --help
    docker run --rm --entrypoint peertube-runner "$IMAGE" --help
}

test_runner_logger_hides_objects_without_verbose() {
    docker run --rm \
        --entrypoint sh \
        "$IMAGE" \
        -lc 'grep -Fq '\''hideObject: !process.argv.includes("--verbose")'\'' "$(npm root -g)/@peertube/peertube-runner/dist/peertube-runner.mjs"'
}

test_ffmpeg_wrapper_reports_nvenc_fallback() {
    local output_file="ffmpeg-wrapper-fallback.log"
    local ffmpeg_status

    set +e
    docker run --rm \
        --entrypoint ffmpeg \
        "$IMAGE" \
        -hide_banner \
        -f lavfi \
        -i testsrc2=duration=0.1:size=16x16:rate=1 \
        -c:v libx264 \
        -f null - > "$output_file" 2>&1
    ffmpeg_status=$?
    set -e

    cat "$output_file"

    if [ "$ffmpeg_status" -ne 0 ]; then
        echo "Expected FFmpeg wrapper to fall back after NVENC failure" >&2
        exit 1
    fi

    grep -Fq "[peertube-runner-gpu ffmpeg] NVENC attempt: libx264 -> h264_nvenc" "$output_file"
    grep -Fq "[peertube-runner-gpu ffmpeg] NVENC command failed with status" "$output_file"
    grep -Fq "falling back to original FFmpeg command" "$output_file"
}

test_ffmpeg_wrapper_reports_selected_nvenc_encoder() {
    docker run --rm \
        --entrypoint /usr/local/bin/ffmpeg \
        -e FFMPEG_REAL_PATH=/bin/true \
        "$IMAGE" \
        -c:v h264_nvenc \
        -f null - > ffmpeg-wrapper-selected.log 2>&1

    cat ffmpeg-wrapper-selected.log

    grep -Fq "[peertube-runner-gpu ffmpeg] NVENC command selected: h264_nvenc" ffmpeg-wrapper-selected.log

    if [ "$(grep -Fc "[peertube-runner-gpu ffmpeg] NVENC command selected: h264_nvenc" ffmpeg-wrapper-selected.log)" -ne 1 ]; then
        echo "Expected exactly one selected NVENC encoder log line" >&2
        exit 1
    fi
}

wait_for_log_line() {
    local container_name="$1"
    local output_file="$2"
    local expected_line="$3"
    local attempts="$4"

    for _ in $(seq 1 "$attempts"); do
        docker logs "$container_name" > "$output_file" 2>&1 || true

        if grep -Fq "$expected_line" "$output_file"; then
            return 0
        fi

        sleep 1
    done

    docker logs "$container_name" > "$output_file" 2>&1 || true
    return 1
}

wait_for_log_line_count() {
    local container_name="$1"
    local output_file="$2"
    local expected_line="$3"
    local expected_count="$4"
    local attempts="$5"

    for _ in $(seq 1 "$attempts"); do
        docker logs "$container_name" > "$output_file" 2>&1 || true

        if [ "$(grep -Fc "$expected_line" "$output_file" || true)" -ge "$expected_count" ]; then
            return 0
        fi

        sleep 1
    done

    docker logs "$container_name" > "$output_file" 2>&1 || true
    return 1
}

dump_container_state() {
    local container_name="$1"
    local config_path="/home/runner/.config/peertube-runner-nodejs/default/config.toml"

    echo "Container state:"
    docker inspect -f 'status={{.State.Status}} running={{.State.Running}} exit={{.State.ExitCode}} error={{.State.Error}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' "$container_name" || true

    echo "Container processes:"
    docker top "$container_name" || true

    echo "Runner directories:"
    docker exec "$container_name" sh -lc 'ls -ld /home/runner /home/runner/.config /home/runner/.config/peertube-runner-nodejs /home/runner/.config/peertube-runner-nodejs/default /home/runner/.cache /home/runner/.local/share/peertube-runner-nodejs/default' || true

    echo "Runner config:"
    docker exec "$container_name" sh -lc "sed -E 's/ptrrt-[[:alnum:]-]+/<registration-token>/g; s/ptrt-[[:alnum:]-]+/<runner-token>/g' '$config_path'" || true

    echo "Container logs:"
    docker logs "$container_name" || true
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

    grep -Fq "PEERTUBE_RUNNER_URL and PEERTUBE_RUNNER_TOKEN environment variables are required" "$output_file"

    if grep -Fq "Cannot create config directory" "$output_file"; then
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

    grep -Fq "Failed to register runner" "$output_file"

    if grep -Fq '    err: {' "$output_file"; then
        echo "Default logs should not include structured runner error details" >&2
        exit 1
    fi

    if grep -Eq '"registrationToken"|"stack"|ptrrt-00000000-0000-0000-0000-000000000000' "$output_file"; then
        echo "Default logs exposed registration diagnostics that should be hidden" >&2
        exit 1
    fi

    if grep -Eq "Config file location|Starting PeerTube Runner with command|  URL:" "$output_file"; then
        echo "Default logs should not include wrapper startup details" >&2
        exit 1
    fi
}

test_debug_logs_use_debug_level() {
    local output_file="entrypoint-debug.log"
    local entrypoint_status

    set +e
    docker run --rm \
        -e PEERTUBE_RUNNER_DEBUG=true \
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

    grep -Fq "DEBUG (1):   URL:" "$output_file"
    grep -Fq "peertube-runner --verbose server" "$output_file"

    if grep -Fq "INFO (1):   URL:" "$output_file"; then
        echo "Debug wrapper logs should use DEBUG level" >&2
        exit 1
    fi
}

test_existing_config_default_logs_are_useful() {
    local run_id="${GITHUB_RUN_ID:-local}"
    local run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
    local volume_suffix="${run_id}-${run_attempt}-existing-$$"
    local config_volume="peertube-runner-config-smoke-${volume_suffix}"
    local container_name="peertube-runner-existing-smoke-${volume_suffix}"
    local output_file="entrypoint-existing-config.log"

    docker rm -f "$container_name" >/dev/null 2>&1 || true
    docker volume rm -f "$config_volume" >/dev/null 2>&1 || true
    docker volume create "$config_volume" >/dev/null
    trap "docker rm -f '$container_name' >/dev/null 2>&1 || true; docker volume rm -f '$config_volume' >/dev/null 2>&1 || true" EXIT

    docker run --rm \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        --entrypoint bash \
        "$IMAGE" \
        -lc 'mkdir -p /home/runner/.config/peertube-runner-nodejs/default && cat > /home/runner/.config/peertube-runner-nodejs/default/config.toml << EOF
[jobs]
concurrency = 2

[ffmpeg]
threads = 4
nice = 20

[transcription]
engine = "whisper-ctranslate2"
model = "large-v3"

[[registeredInstances]]
url = "http://127.0.0.1:9"
runnerToken = "ptrt-00000000-0000-0000-0000-000000000000"
runnerName = "peertube-runner-smoke"
EOF'

    docker run -d \
        --name "$container_name" \
        -e PEERTUBE_RUNNER_CONCURRENCY=1 \
        -e PEERTUBE_RUNNER_FFMPEG_THREADS=1 \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        "$IMAGE" >/dev/null

    if ! wait_for_log_line "$container_name" "$output_file" "Running PeerTube runner in server mode" 8; then
        cat "$output_file"
        dump_container_state "$container_name"
        echo "Expected existing-config runner to write startup logs" >&2
        exit 1
    fi

    cat "$output_file"

    if [ "$(docker inspect -f '{{.State.Running}}' "$container_name")" != "true" ]; then
        echo "Expected existing-config runner to keep running" >&2
        exit 1
    fi

    if grep -Eq "Using existing config file|Updating config parameters|Applying runtime config overrides|Config file location|Starting PeerTube Runner with command" "$output_file"; then
        echo "Default existing-config logs should not include wrapper startup details" >&2
        exit 1
    fi

    docker rm -f "$container_name" >/dev/null 2>&1 || true
    docker volume rm -f "$config_volume" >/dev/null 2>&1 || true
    trap - EXIT
}

test_stale_runner_token_is_replaced() {
    local run_id="${GITHUB_RUN_ID:-local}"
    local run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
    local volume_suffix="${run_id}-${run_attempt}-stale-$$"
    local config_volume="peertube-runner-config-smoke-${volume_suffix}"
    local container_name="peertube-runner-stale-smoke-${volume_suffix}"
    local output_file="entrypoint-stale-token.log"
    local server_log="fake-peertube.log"
    local port=$((18080 + ($$ % 1000)))
    local fake_server_pid
    local base_url="http://host.docker.internal:${port}"

    python3 - "$port" > "$server_log" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = {}
        if length:
            body = json.loads(self.rfile.read(length).decode("utf-8"))

        if self.path == "/api/v1/runners/jobs/request":
            if body.get("runnerToken") == "ptrt-00000000-0000-0000-0000-000000000000":
                self.send_json(400, {"code": "unknown_runner_token", "detail": "Unknown runner token"})
                return

            self.send_json(200, {"availableJobs": []})
            return

        if self.path == "/api/v1/runners/register":
            self.send_json(200, {"runnerToken": "ptrt-11111111-1111-1111-1111-111111111111"})
            return

        if self.path == "/api/v1/runners/unregister":
            self.send_empty(204)
            return

        self.send_json(404, {"code": "not_found"})

    def do_GET(self):
        self.send_json(404, {"code": "not_found"})

    def log_message(self, format, *args):
        return

    def send_json(self, status, body):
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_empty(self, status):
        self.send_response(status)
        self.send_header("content-length", "0")
        self.end_headers()


ThreadingHTTPServer(("0.0.0.0", int(sys.argv[1])), Handler).serve_forever()
PY
    fake_server_pid=$!

    cleanup_stale_test() {
        kill "$fake_server_pid" >/dev/null 2>&1 || true
        docker rm -f "$container_name" >/dev/null 2>&1 || true
        docker volume rm -f "$config_volume" >/dev/null 2>&1 || true
    }

    trap cleanup_stale_test EXIT

    python3 - "$port" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
for _ in range(50):
    with socket.socket() as sock:
        sock.settimeout(0.2)
        if sock.connect_ex(("127.0.0.1", port)) == 0:
            sys.exit(0)
    time.sleep(0.1)

sys.exit(1)
PY

    docker volume rm -f "$config_volume" >/dev/null 2>&1 || true
    docker volume create "$config_volume" >/dev/null

    docker run --rm \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        --entrypoint bash \
        "$IMAGE" \
        -lc "mkdir -p /home/runner/.config/peertube-runner-nodejs/default && cat > /home/runner/.config/peertube-runner-nodejs/default/config.toml << EOF
[jobs]
concurrency = 2

[ffmpeg]
threads = 4
nice = 20

[transcription]
engine = \"whisper-ctranslate2\"
model = \"large-v3\"

[[registeredInstances]]
url = \"${base_url}\"
runnerToken = \"ptrt-00000000-0000-0000-0000-000000000000\"
runnerName = \"peertube-runner-smoke\"
EOF"

    docker run -d \
        --name "$container_name" \
        --add-host=host.docker.internal:host-gateway \
        -e PEERTUBE_RUNNER_URL="$base_url" \
        -e PEERTUBE_RUNNER_TOKEN=ptrrt-00000000-0000-0000-0000-000000000000 \
        -e PEERTUBE_RUNNER_NAME=peertube-runner-smoke \
        -e PEERTUBE_RUNNER_NAME_CONFLICT=exit \
        -v "$config_volume:/home/runner/.config/peertube-runner-nodejs" \
        "$IMAGE" >/dev/null

    if ! wait_for_log_line "$container_name" "$output_file" "Runner registered successfully with name 'peertube-runner-smoke'" 25; then
        cat "$output_file"
        dump_container_state "$container_name"
        echo "Expected stale runner token recovery to register a fresh runner" >&2
        exit 1
    fi

    if ! wait_for_log_line_count "$container_name" "$output_file" "Checking available jobs on $base_url" 2 25; then
        cat "$output_file"
        dump_container_state "$container_name"
        echo "Expected recovered runner to continue with visible job polling logs" >&2
        exit 1
    fi

    cat "$output_file"

    if [ "$(docker inspect -f '{{.State.Running}}' "$container_name")" != "true" ]; then
        echo "Expected recovered runner to keep running" >&2
        exit 1
    fi

    grep -Fq "Persisted runner registration is no longer accepted by PeerTube" "$output_file"

    cleanup_stale_test
    trap - EXIT
}

run_tool_smoke_tests
test_runner_logger_hides_objects_without_verbose
test_ffmpeg_wrapper_reports_nvenc_fallback
test_ffmpeg_wrapper_reports_selected_nvenc_encoder
test_entrypoint_repairs_root_owned_volumes
test_registration_logs_are_concise
test_debug_logs_use_debug_level
test_existing_config_default_logs_are_useful
test_stale_runner_token_is_replaced
