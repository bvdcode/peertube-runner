# PeerTube Runner with CUDA Support

A Docker container for running PeerTube Runner with GPU acceleration for video transcoding and transcription tasks.

## TL;DR

```bash
docker run -d --name peertube-runner-gpu \
  --gpus all --restart unless-stopped \
  -e PEERTUBE_RUNNER_URL=https://your-peertube-instance.com \
  -e PEERTUBE_RUNNER_TOKEN=your_token_here \
  bvdcode/peertube-runner-gpu:latest
```

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

### Method 1: Using Docker Compose with Environment Variables (Recommended)

1. Clone this repository:

```bash
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner
```

2. Edit the `docker-compose.yml` file and update the environment variables:

```yaml
environment:
  - PEERTUBE_RUNNER_URL=https://your-peertube-instance.com # Your PeerTube URL
  - PEERTUBE_RUNNER_TOKEN=your_actual_token_here # Your runner token
  - PEERTUBE_RUNNER_NAME=my-gpu-runner # Custom runner name
```

3. Start the container:

```bash
docker-compose up -d
```

### Method 2: Using Docker Compose with Config File

1. Create your own `config.toml` file (see configuration section below)
2. Mount it in the docker-compose.yml:

```yaml
volumes:
  - ./config.toml:/home/runner/config.toml:ro
```

3. Start the container:

```bash
docker-compose up -d
```

### Method 3: Using Docker Run with Environment Variables

```bash
docker run -d \
  --name peertube-runner-gpu \
  --gpus all \
  --restart unless-stopped \
  -e PEERTUBE_RUNNER_URL=https://your-peertube-instance.com \
  -e PEERTUBE_RUNNER_TOKEN=your_token_here \
  -e PEERTUBE_RUNNER_NAME=my-runner \
  bvdcode/peertube-runner-gpu:latest
```

## Configuration Options

### Environment Variables

| Variable                         | Default               | Description                |
| -------------------------------- | --------------------- | -------------------------- |
| `PEERTUBE_RUNNER_URL`            | _Required_            | Your PeerTube instance URL |
| `PEERTUBE_RUNNER_TOKEN`          | _Required_            | Runner registration token  |
| `PEERTUBE_RUNNER_NAME`           | `peertube-runner-gpu` | Custom name for the runner |
| `PEERTUBE_RUNNER_CONCURRENCY`    | `2`                   | Number of concurrent jobs  |
| `PEERTUBE_RUNNER_FFMPEG_THREADS` | `4`                   | FFmpeg thread count        |
| `PEERTUBE_RUNNER_FFMPEG_NICE`    | `20`                  | FFmpeg process priority    |
| `PEERTUBE_RUNNER_ENGINE`         | `whisper-ctranslate2` | Transcription engine       |
| `PEERTUBE_RUNNER_WHISPER_MODEL`  | `large-v3`            | Whisper model size         |
| `PEERTUBE_RUNNER_JOB_TYPES`      | _All jobs_            | Comma-separated job types  |

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
   - All jobs respect concurrency limits
5. **Result Delivery**: Return processed content to PeerTube instance

## Usage Examples

### Basic Setup for Transcription Only

```yaml
services:
  peertube-runner-gpu:
    image: bvdcode/peertube-runner-gpu:latest
    environment:
      - PEERTUBE_RUNNER_URL=https://your-instance.com
      - PEERTUBE_RUNNER_TOKEN=your_token
      - PEERTUBE_RUNNER_JOB_TYPES=video-transcription
      - PEERTUBE_RUNNER_WHISPER_MODEL=medium
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
```

### High-Performance Transcoding Setup

```yaml
services:
  peertube-runner-gpu:
    image: bvdcode/peertube-runner-gpu:latest
    environment:
      - PEERTUBE_RUNNER_URL=https://your-instance.com
      - PEERTUBE_RUNNER_TOKEN=your_token
      - PEERTUBE_RUNNER_CONCURRENCY=4
      - PEERTUBE_RUNNER_FFMPEG_THREADS=8
      - PEERTUBE_RUNNER_JOB_TYPES=vod-hls-transcoding,vod-web-video-transcoding
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
```

### CPU-Only Setup (No GPU)

```yaml
services:
  peertube-runner:
    image: bvdcode/peertube-runner-gpu:latest
    environment:
      - PEERTUBE_RUNNER_URL=https://your-instance.com
      - PEERTUBE_RUNNER_TOKEN=your_token
      - PEERTUBE_RUNNER_ENGINE=whisper-ffmpeg # CPU-based transcription
      - PEERTUBE_RUNNER_WHISPER_MODEL=base # Smaller model for CPU
    # No GPU deployment section
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

For systems with limited RAM:

```yaml
environment:
  - PEERTUBE_RUNNER_WHISPER_MODEL=small # Use smaller model
  - PEERTUBE_RUNNER_CONCURRENCY=1 # Reduce concurrency
  - PEERTUBE_RUNNER_FFMPEG_THREADS=2 # Reduce threads
```

#### High-Performance Setup

For powerful systems:

```yaml
environment:
  - PEERTUBE_RUNNER_CONCURRENCY=6 # Increase concurrency
  - PEERTUBE_RUNNER_FFMPEG_THREADS=12 # More threads
  - PEERTUBE_RUNNER_FFMPEG_NICE=10 # Higher priority
```

## Security Considerations

- Container runs as non-root user (`runner`)
- Configuration files mounted as read-only
- No unnecessary network ports exposed
- Use secrets management for sensitive tokens in production

## Development

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with your PeerTube instance
5. Submit a pull request

### Local Development

```bash
# Clone repository
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner

# Build local image
docker build -t peertube-runner-gpu:dev .

# Test with your configuration
docker run --rm --gpus all \
  -e PEERTUBE_RUNNER_URL=https://your-instance.com \
  -e PEERTUBE_RUNNER_TOKEN=your_token \
  peertube-runner-gpu:dev
```

## FAQ

### Q: Can I run without a GPU?

**A**: Yes, remove the `deploy` section from docker-compose.yml and consider using `whisper-ffmpeg` engine for CPU-based transcription.

### Q: Which Whisper model should I use?

**A**: For transcription quality: `large-v3` > `large-v2` > `medium` > `small` > `base` > `tiny`. Choose based on your GPU memory and speed requirements.

### Q: Can I run multiple runners on one machine?

**A**: Yes, use different container names and runner names for each instance.

### Q: How do I update to the latest version?

**A**: Run `docker-compose pull` followed by `docker-compose up -d`.

## Support & Community

- **Issues**: [GitHub Issues](https://github.com/bvdcode/peertube-runner/issues)
- **PeerTube Documentation**: [Official Docs](https://docs.joinpeertube.org/maintain/tools#configuration)
- **Docker Hub**: [bvdcode/peertube-runner-gpu](https://hub.docker.com/r/bvdcode/peertube-runner-gpu)

## Version History

- **v1.0.0**: Initial release with basic transcription support
- **v2.0.0**: Added full transcoding support and environment variable configuration
- **v2.1.0**: Updated to CUDA 12.8.0 and improved job type selection

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
