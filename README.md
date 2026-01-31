# PeerTube Runner with CUDA Support

![Docker Pulls](https://img.shields.io/docker/pulls/bvdcode/peertube-runner-gpu)
![Docker Tag](https://img.shields.io/docker/v/bvdcode/peertube-runner-gpu)

**A Docker container for running PeerTube Runner with GPU acceleration for video transcoding and transcription tasks.**

## TL;DR

```bash
docker run -d --name peertube-runner-gpu \
  --gpus all --restart unless-stopped \
  -e PEERTUBE_RUNNER_URL=https://your-peertube-instance.com \
  -e PEERTUBE_RUNNER_TOKEN=your_token_here \
  bvdcode/peertube-runner-gpu:latest
```

**Key Features:**

- ✅ **Smart NVENC Auto-Detection**: Automatically detects GPU availability and falls back to CPU if needed
- ✅ **Reliable Registration**: Fixed registration logic that accurately reports success/failure
- ✅ **GPU Transcription**: Whisper models run on GPU via CTranslate2
- ✅ **Model Auto-Download**: Whisper models download automatically on first use
- ✅ **Persistent Cache**: Mount `/home/runner/.cache/` to preserve downloaded models across restarts

**Important Notes:**

- The wrapper automatically tests NVENC on first run and caches the result (`/tmp/nvenc_ok` or `/tmp/nvenc_disabled`)
- Runner registration tokens differ from web UI tokens—this is PeerTube's design
- Registration only reports success when `runnerToken` is actually written to config

## Overview

This project provides a containerized PeerTube Runner with NVIDIA CUDA support, designed for hardware-accelerated video processing including transcoding and transcription using Whisper and CTranslate2. The container supports all major PeerTube job types and is optimized for efficient processing in a PeerTube environment.

## Features

- 🚀 **GPU Acceleration**: NVIDIA CUDA 12.8.0 support with cuDNN runtime
- � **Video Transcoding**: Support for VOD web video, HLS, audio merge transcoding
- 📺 **Live Streaming**: Live RTMP to HLS transcoding support
- 🎬 **Video Studio**: Video studio transcoding capabilities
- 🎵 **Video Transcription**: AI-powered transcription using Whisper-CTranslate2
- 🐳 **Docker Ready**: Easy deployment with Docker and Docker Compose
- 🔧 **Flexible Configuration**: Environment variables or config file support
- ⚙️ **Auto-building**: GitHub Actions for automated Docker image builds
- 🏃 **Production Ready**: Based on Ubuntu 22.04 with optimized dependencies

## Supported Job Types

- `vod-web-video-transcoding` - Video-on-demand web video transcoding
- `vod-hls-transcoding` - HLS video transcoding
- `vod-audio-merge-transcoding` - Audio merge transcoding
- `live-rtmp-hls-transcoding` - Live streaming transcoding
- `video-studio-transcoding` - Video studio editing transcoding
- `video-transcription` - AI-powered video transcription

## Prerequisites

- Docker and Docker Compose installed
- NVIDIA GPU with CUDA support (optional, container can run without GPU)
- NVIDIA Container Toolkit for GPU acceleration

### Installing NVIDIA Container Toolkit

For Ubuntu/Debian:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

## Quick Start

**Using Docker Compose (Recommended):**

```bash
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner
# Edit docker-compose.yml with your URL and token
docker-compose up -d
```

**Using Docker Run:**

```bash
docker run -d --name peertube-runner-gpu --gpus all --restart unless-stopped \
  -e PEERTUBE_RUNNER_URL=https://your-instance.com \
  -e PEERTUBE_RUNNER_TOKEN=your_token \
  bvdcode/peertube-runner-gpu:latest
```

**With Config File:**

Mount your `config.toml` to `/home/runner/config.toml:ro` in volumes.

## Configuration Options

### Environment Variables

| Variable                         | Default               | Description                                     |
| -------------------------------- | --------------------- | ----------------------------------------------- |
| `PEERTUBE_RUNNER_URL`            | _Required_            | Your PeerTube instance URL                      |
| `PEERTUBE_RUNNER_TOKEN`          | _Required_            | Runner registration token                       |
| `PEERTUBE_RUNNER_NAME`           | `peertube-runner-gpu` | Custom name for the runner                      |
| `PEERTUBE_RUNNER_NAME_CONFLICT`  | `exit`                | Action on name conflict: `exit`, `auto`, `wait` |
| `PEERTUBE_RUNNER_CONCURRENCY`    | `2`                   | Number of concurrent jobs                       |
| `PEERTUBE_RUNNER_FFMPEG_THREADS` | `4`                   | FFmpeg thread count                             |
| `PEERTUBE_RUNNER_FFMPEG_NICE`    | `20`                  | FFmpeg process priority                         |
| `PEERTUBE_RUNNER_ENGINE`         | `whisper-ctranslate2` | Transcription engine                            |
| `PEERTUBE_RUNNER_WHISPER_MODEL`  | `large-v3`            | Whisper model size                              |
| `PEERTUBE_RUNNER_JOB_TYPES`      | _All jobs_            | Comma-separated job types                       |

### Configuration File Format

Alternatively, you can use a `config.toml` file:

```toml
[jobs]
concurrency = 2

[ffmpeg]
threads = 4
nice = 20

[transcription]
engine = "whisper-ctranslate2"
model = "large-v3"

[[registeredInstances]]
url = "https://your-peertube-instance.com"
runnerToken = "your_runner_token_here"
runnerName = "my-custom-runner"
```

### Whisper Models Available

- `tiny` - Fastest, least accurate (39 MB)
- `base` - Good speed/accuracy balance (74 MB)
- `small` - Better accuracy (244 MB)
- `medium` - High accuracy (769 MB)
- `large-v2` - Very high accuracy (1550 MB)
- `large-v3` - Best accuracy (1550 MB, **default**)

### Job Type Configuration

You can limit the runner to specific job types by setting `PEERTUBE_RUNNER_JOB_TYPES`:

```bash
# Only transcription jobs
PEERTUBE_RUNNER_JOB_TYPES=video-transcription

# Multiple job types
PEERTUBE_RUNNER_JOB_TYPES=vod-hls-transcoding,video-transcription,video-studio-transcoding

# All jobs (default if not specified)
# Leave empty or omit the variable
```

### Name Conflict Resolution

Control how the runner behaves when a runner with the same name already exists on the PeerTube instance:

#### `PEERTUBE_RUNNER_NAME_CONFLICT=exit` (default)

Exits with an error message and instructions when a name conflict occurs:

```bash
PEERTUBE_RUNNER_NAME_CONFLICT=exit
```

**Use case**: Strict environments where you want to manually manage runner names.

#### `PEERTUBE_RUNNER_NAME_CONFLICT=auto`

Automatically generates unique names by appending a timestamp:

```bash
PEERTUBE_RUNNER_NAME_CONFLICT=auto
```

**Example**: `peertube-runner-gpu` → `peertube-runner-gpu-1753501234`

**Use case**: Development or testing environments where you want hassle-free deployment.

#### `PEERTUBE_RUNNER_NAME_CONFLICT=wait`

Waits for the existing runner to be removed, checking every 30 seconds:

```bash
PEERTUBE_RUNNER_NAME_CONFLICT=wait
```

**Use case**: When replacing an existing runner and you want to wait for manual cleanup.

## Docker Images

### Available Tags

- `bvdcode/peertube-runner-gpu:latest` - Latest stable version
- `ghcr.io/bvdcode/peertube-runner-gpu:latest` - GitHub Container Registry

### Automated Builds

The project uses GitHub Actions for automated builds:

- Builds trigger on pushes to `main` branch
- Images are published to both Docker Hub and GitHub Container Registry
- Manual builds can be triggered via workflow dispatch

## Architecture & Components

### Software Stack

- **Base Image**: NVIDIA CUDA 12.8.0 with cuDNN runtime on Ubuntu 22.04
- **Python**: Python 3 with pip
- **Node.js**: Node.js 20.x LTS
- **FFmpeg**: For video processing and transcoding
- **PeerTube Runner**: Latest version from npm

### Python Packages

- **CTranslate2 4.6.0**: Optimized inference library for Transformer models
- **Whisper-CTranslate2 0.5.3**: Fast implementation of OpenAI's Whisper speech recognition

### Container Features

- Non-root user execution for security
- Automatic configuration generation from environment variables
- Flexible job type selection
- GPU resource reservation with Docker Compose
- Persistent configuration via volume mounts

## Building from Source

To build the Docker image locally:

```bash
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner
docker build -t peertube-runner-gpu .
```

### Build Arguments

The Dockerfile supports standard Docker build arguments and will automatically install all dependencies.

## How It Works

When the container starts, it will:

1. **Configuration Setup**: Check for existing config file or generate from environment variables
2. **PeerTube Connection**: Connect to your PeerTube instance using provided URL and token
3. **Runner Registration**: Register as a runner with specified capabilities
4. **Job Processing**: Accept and process jobs based on configured job types:
   - Video transcoding jobs use FFmpeg with specified thread/nice settings
   - Transcription jobs use Whisper with GPU acceleration
   - All jobs respect concurrency limits 5.**Smart NVENC Handling**: Auto-detects GPU capabilities on first ffmpeg run, caches result per container

- **Automatic Fallback**: Gracefully falls back to CPU encoding if NVENC unavailable
- **Reliable Registration**: Only reports success when runner token is actually saved to config
- **Non-root Execution**: Runs as `runner` user for security
  **Transcription Only (GPU):**

```yaml
environment:
  - PEERTUBE_RUNNER_JOB_TYPES=video-transcription
  - PEERTUBE_RUNNER_WHISPER_MODEL=medium
```

**High-Performance Transcoding:**

```yaml
environment:
  - PEERTUBE_RUNNER_CONCURRENCY=4
  - PEERTUBE_RUNNER_FFMPEG_THREADS=8
```

**CPU-Only (No GPU):**

```yaml
environment:
  - PEERTUBE_RUNNER_ENGINE=whisper-ffmpeg
  - PEERTUBE_RUNNER_WHISPER_MODEL=base
# Remove deploy.resources section
```

**Auto-Generated Names (Dev/Testing):**

```yaml
environment:
  - PEERTUBE_RUNNER_NAME_CONFLICT=auto  # Adds timestamp if name exists
          devices:
            - capabilities: [gpu]
```

## Monitoring & Management

### Viewing Logs

```bash
# Real-time logs
docker-compose logs -f peertube-runner-gpu

# Last 100 lines
docker-compose logs --tail 100 peertube-runner-gpu
```

### Container Status

```bash
# Check container status
docker-compose ps

# Check resource usage
docker stats peertube-runner-gpu
```

### GPU Monitoring

```bash
# Check GPU usage inside container
docker exec peertube-runner-gpu nvidia-smi

# Monitor GPU usage in real-time
watch -n 1 'docker exec peertube-runner-gpu nvidia-smi'
```

## Troubleshooting

### Common Issues

#### 1. GPU Not Available

**Error**: `CUDA driver version is insufficient` or `nvidia-smi not found`

**Solution**:

1. Verify NVIDIA drivers are installed:

```bash
nvidia-smi
```

2. Check Docker can access GPU:

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-runtime-ubuntu22.04 nvidia-smi
```

3. Ensure nvidia-container-toolkit is installed and Docker is restarted.

#### 2. Configuration Issues

**Error**: `PEERTUBE_RUNNER_URL and PEERTUBE_RUNNER_TOKEN environment variables are required`

**Solution**:

- Verify environment variables are set in docker-compose.yml
- Check that config.toml file exists if using file-based configuration
- Ensure proper escaping of special characters in tokens

#### 3. Connection Issues

**Error**: `Failed to connect to PeerTube instance`

**Solution**:

- Verify PeerTube instance URL is accessible from the container
- Check firewall rules and network connectivity
- Ensure runner token is valid and not expired
- Test connection: `curl -I https://your-peertube-instance.com`

#### 4. Job Processing Issues

**Error**: Jobs not being picked up or failing

**Solution**:

- Check PeerTube instance runner configuration
- Verify job types are properly configured
- Monitor logs for specific error messages
- Ensure sufficient disk space and memory

### Performance Tuning

#### Memory Optimization

**GPU Not Detected:**

- Check: `nvidia-smi` on host
- Verify: `docker run --rm --gpus all nvidia/cuda:12.8.0-runtime-ubuntu22.04 nvidia-smi`
- Install nvidia-container-toolkit if missing

**"NVENC not available" in logs:**

- Normal behavior—container automatically falls back to CPU encoding
- Container works fine without GPU, just slower for transcoding

**Registration Failed:**

- Check URL is accessible: `curl -I https://your-instance.com`
- Verify token format: `ptrrt-...` (registration token, not runner token)
- Name conflict? Use `PEERTUBE_RUNNER_NAME_CONFLICT=auto`

**Performance Tuning:**

````yaml
# Low memory:
- PEERTUBE_RUNNER_WHISPER_MODEL=small
- PEERTUBE_RUNNER_CONCURRENCY=1

# High performance:
- PEERTUBE_RUNNER_CONCURRENCY=6
- PEERTUBE_RUNNER_FFMPEG_THREADS=12
### Q: How do I update to the latest version?

**A**: Run `docker-compose pull` followed by `docker-compose up -d`.

## Support & Community

- **Issues**: [GitHub Issues](https://github.com/bvdcode/peertube-runner/issues)
- **PeerTube Documentation**: [Official Docs](https://docs.joinpeertube.org/maintain/tools#configuration)
- **Docker Hub**: [bvdcode/peertube-runner-gpu](https://hub.docker.com/r/bvdcode/peertube-runner-gpu)

## License

This project is open source. Please check the license file for details.

## Related Projects & Links

- **[PeerTube](https://github.com/Chocobozzz/PeerTube)** - Federated video hosting network
- **[PeerTube Runner](https://www.npmjs.com/package/@peertube/peertube-runner)** - Official PeerTube runner package
- **[Whisper-CTranslate2](https://github.com/guillaumekln/faster-whisper)** - Fast Whisper implementation
- **[CTranslate2](https://github.com/OpenNMT/CTranslate2)** - Optimized inference library
- **[NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)** - GPU support for containers

## Acknowledgments

- PeerTube team for the excellent video platform and runner system
- OpenAI for Whisper speech recognition model
- NVIDIA for CUDA toolkit and container support
- Contributors and users of this project

---

**Built with ❤️ for the PeerTube community**

For more information about PeerTube runners, visit the [official documentation](https://docs.joinpeertube.org/maintain/tools#configuration).
FAQ

**Q: Does it work without GPU?**
A: Yes! Auto-detects and falls back to CPU. Remove `deploy.resources` section for CPU-only.

**Q: Which Whisper model?**
A: Quality: `large-v3` > `large-v2` > `medium` > `small` > `base` > `tiny`. Use `small`/`base` for CPU.

**Q: Multiple runners on one machine?**
A: Yes, use different container/runner names for each.

**Q: Runner name already exists?**
A: Set `PEERTUBE_RUNNER_NAME_CONFLICT=auto` to auto-generate unique names with timestamp.

**Q: How to update?**
A: `docker-compose pull && docker-compose up -d`

## Contributing

```bash
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner
docker build -t peertube-runner-gpu:dev .
docker run --rm --gpus all -e PEERTUBE_RUNNER_URL=... -e PEERTUBE_RUNNER_TOKEN=... peertube-runner-gpu:dev
````

Pull requests welcome!
