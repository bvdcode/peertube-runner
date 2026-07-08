# PeerTube Runner with CUDA Support

![Docker Pulls](https://img.shields.io/docker/pulls/bvdcode/peertube-runner-gpu)
![Docker Tag](https://img.shields.io/docker/v/bvdcode/peertube-runner-gpu)

Docker image for running PeerTube Runner with NVIDIA acceleration for video transcoding and speech transcription tasks.

## Quick Start

```bash
docker run -d --name peertube-runner-gpu \
  --gpus all \
  --restart unless-stopped \
  -e PEERTUBE_RUNNER_URL=https://your-peertube-instance.com \
  -e PEERTUBE_RUNNER_TOKEN=your_registration_token_here \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
  -v peertube-runner-config:/home/runner/.config/peertube-runner-nodejs \
  -v peertube-runner-cache:/home/runner/.cache \
  bvdcode/peertube-runner-gpu:latest
```

## Features

- NVIDIA CUDA 12.8.0 with cuDNN runtime on Ubuntu 24.04
- FFmpeg with NVENC wrapper for H.264 and H.265 transcoding
- Whisper-CTranslate2 transcription support
- Environment-variable or file-based runner configuration
- Non-root container user
- Automated image publishing to Docker Hub and GitHub Container Registry

## Supported Job Types

- `vod-web-video-transcoding`
- `vod-hls-transcoding`
- `vod-audio-merge-transcoding`
- `live-rtmp-hls-transcoding`
- `video-studio-transcoding`
- `video-transcription`
- `generate-video-storyboard`

## Prerequisites

- Docker and Docker Compose
- NVIDIA Container Toolkit for GPU access
- NVIDIA driver compatible with CUDA 12.8

The container can start without a GPU if `--gpus all` is omitted. GPU transcoding and GPU transcription require the NVIDIA runtime.

## Docker Compose

Edit `docker-compose.yml` with your PeerTube URL and registration token, then run:

```bash
docker compose up -d
```

The compose file persists `/home/runner/.config/peertube-runner-nodejs` and `/home/runner/.cache` in named volumes. Keep these volumes unless you intentionally want to re-register the runner and re-download cached transcription models.

The compose file uses environment variables by default. To seed runner settings from a config file, copy `config.example.toml` to `config.toml`, edit it, and add `./config.toml:/home/runner/config.toml:ro` to the existing `volumes` list. Keep `PEERTUBE_RUNNER_URL` and `PEERTUBE_RUNNER_TOKEN` set for first-time registration unless your persisted runtime config already contains a registered runner token.

For CPU-only use, remove the `deploy.resources.reservations.devices` section from `docker-compose.yml`.

## Configuration

| Variable                         | Default               | Description                                     |
| -------------------------------- | --------------------- | ----------------------------------------------- |
| `PEERTUBE_RUNNER_URL`            | Required              | PeerTube instance URL                           |
| `PEERTUBE_RUNNER_TOKEN`          | Required              | PeerTube runner registration token              |
| `PEERTUBE_RUNNER_NAME`           | `peertube-runner-gpu` | Runner name                                     |
| `PEERTUBE_RUNNER_NAME_CONFLICT`  | `exit`                | `exit`, `auto`, or `wait`                       |
| `PEERTUBE_RUNNER_CONCURRENCY`    | `2`                   | Number of concurrent jobs                       |
| `PEERTUBE_RUNNER_FFMPEG_THREADS` | `4`                   | FFmpeg thread count                             |
| `PEERTUBE_RUNNER_FFMPEG_NICE`    | `20`                  | FFmpeg process priority                         |
| `PEERTUBE_RUNNER_ENGINE`         | `whisper-ctranslate2` | Transcription engine                            |
| `PEERTUBE_RUNNER_WHISPER_MODEL`  | `large-v3`            | Whisper model                                   |
| `PEERTUBE_RUNNER_JOB_TYPES`      | All jobs              | Comma-separated job types                       |

Example `config.toml` for runner settings:

```toml
[jobs]
concurrency = 2

[ffmpeg]
threads = 4
nice = 20

[transcription]
engine = "whisper-ctranslate2"
model = "large-v3"
```

PeerTube Runner writes `[[registeredInstances]]` to its runtime config after successful registration. If you provide a fully registered config file yourself, use the runner token stored by PeerTube Runner, not the first-time registration token.

Persisting `/home/runner/.config/peertube-runner-nodejs` preserves that registered runner token across container recreates. Without a persistent config volume, each recreated container starts from a blank config and registers again.

## Runner Name Conflicts

`PEERTUBE_RUNNER_NAME_CONFLICT` controls behavior when the configured runner name already exists on the PeerTube instance:

- `exit`: stop with an error
- `auto`: append a timestamp to the runner name
- `wait`: retry every 30 seconds until the existing runner is removed

With `auto`, a `400 Bad Request` response saying the runner name already exists is expected when the original name is already registered. The container then registers a timestamped runner name. This is useful for recovery, but a persistent config volume is the preferred way to keep one stable runner identity.

## Building

```bash
docker build -t peertube-runner-gpu .
```

The PeerTube Runner npm package is pinned by the `PEERTUBE_RUNNER_VERSION` build argument.

```bash
docker build --build-arg PEERTUBE_RUNNER_VERSION=0.6.0 -t peertube-runner-gpu .
```

## Smoke Tests

```bash
docker run --rm --entrypoint ffmpeg peertube-runner-gpu -version
docker run --rm --entrypoint ffmpeg peertube-runner-gpu -encoders
docker run --rm --entrypoint python peertube-runner-gpu -c "import ctranslate2; print(ctranslate2.__version__)"
docker run --rm --entrypoint whisper-ctranslate2 peertube-runner-gpu --help
docker run --rm --entrypoint peertube-runner peertube-runner-gpu --help
docker run --rm --gpus all --entrypoint nvidia-smi peertube-runner-gpu
```

## Monitoring

```bash
docker compose logs -f peertube-runner-gpu
docker compose ps
docker stats peertube-runner-gpu
docker exec peertube-runner-gpu nvidia-smi
```

## Troubleshooting

For GPU issues, verify the host driver and Docker runtime:

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.8.0-runtime-ubuntu24.04 nvidia-smi
```

For registration issues, verify:

- `PEERTUBE_RUNNER_URL` is reachable from the container
- `PEERTUBE_RUNNER_TOKEN` is a registration token
- `PEERTUBE_RUNNER_NAME` is unique, or `PEERTUBE_RUNNER_NAME_CONFLICT` is set to `auto` or `wait`

## Images

- `bvdcode/peertube-runner-gpu:latest`
- `ghcr.io/bvdcode/peertube-runner-gpu:latest`

## Related Projects

- [PeerTube](https://github.com/Chocobozzz/PeerTube)
- [PeerTube Runner](https://www.npmjs.com/package/@peertube/peertube-runner)
- [Whisper-CTranslate2](https://github.com/Softcatala/whisper-ctranslate2)
- [CTranslate2](https://github.com/OpenNMT/CTranslate2)
- [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)
