# PeerTube Runner with CUDA Support

A Docker container for running PeerTube Runner with GPU acceleration for video transcription tasks.

## Overview

This project provides a containerized PeerTube Runner with NVIDIA CUDA support, specifically designed for hardware-accelerated video transcription using Whisper and CTranslate2. The container is optimized for efficient processing of video transcription jobs in a PeerTube environment.

## Features

- 🚀 **GPU Acceleration**: NVIDIA CUDA 12.8.0 support with cuDNN runtime
- 🎵 **Video Transcription**: Specialized for video-transcription jobs using Whisper-CTranslate2
- 🐳 **Docker Ready**: Easy deployment with Docker and Docker Compose
- 🔧 **Pre-configured**: Comes with all necessary dependencies installed
- 🏃 **Lightweight**: Based on Ubuntu 22.04 with minimal dependencies

## Prerequisites

- Docker and Docker Compose installed
- NVIDIA GPU with CUDA support
- NVIDIA Container Toolkit (nvidia-docker2)

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

### Using Docker Compose (Recommended)

1. Clone this repository:

```bash
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner
```

2. Create a configuration file:

```bash
mkdir -p config
# Copy your PeerTube runner configuration to config/config.toml
```

3. Start the container:

```bash
docker-compose up -d
```

### Using Docker Run

```bash
docker run -d \
  --name peertube-runner-gpu \
  --gpus all \
  --restart unless-stopped \
  -v $(pwd)/config/config.toml:/home/runner/.config/peertube-runner-nodejs/default/config.toml \
  bvdcode/peertube-runner-gpu:latest
```

## Configuration

The container expects a PeerTube runner configuration file at:

```
/home/runner/.config/peertube-runner-nodejs/default/config.toml
```

### Sample Configuration

Create a `config.toml` file with your PeerTube instance details:

```toml
[default]
  [default.peertube]
    url = "https://your-peertube-instance.com"
    runner_token = "your-runner-token"
    runner_name = "GPU Transcription Runner"
    runner_description = "CUDA-enabled runner for video transcription"
```

## What's Included

### Software Stack

- **Base Image**: NVIDIA CUDA 12.8.0 with cuDNN runtime on Ubuntu 22.04
- **Python**: Python 3 with pip
- **Node.js**: Node.js 20.x LTS
- **FFmpeg**: For video processing
- **PeerTube Runner**: Latest version from npm

### Python Packages

- **CTranslate2**: Optimized inference library for Transformer models
- **Whisper-CTranslate2**: Fast implementation of OpenAI's Whisper speech recognition model

## Building from Source

To build the Docker image locally:

```bash
git clone https://github.com/bvdcode/peertube-runner.git
cd peertube-runner
docker build -t peertube-runner-gpu .
```

## Usage

The container is specifically configured to handle video transcription jobs. When started, it will:

1. Connect to your PeerTube instance using the provided configuration
2. Register as a runner capable of handling video-transcription jobs
3. Process incoming transcription tasks using GPU acceleration
4. Return completed transcriptions to your PeerTube instance

## Monitoring

View container logs:

```bash
docker-compose logs -f peertube-runner-gpu
```

Check GPU usage:

```bash
docker exec peertube-runner-gpu nvidia-smi
```

## Troubleshooting

### GPU Not Available

If you encounter GPU-related issues:

1. Verify NVIDIA drivers are installed:

```bash
nvidia-smi
```

2. Check Docker can access GPU:

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-runtime-ubuntu22.04 nvidia-smi
```

3. Ensure nvidia-container-toolkit is properly installed and Docker is restarted.

### Configuration Issues

- Ensure your `config.toml` file has correct PeerTube instance URL and runner token
- Check that the configuration file is properly mounted in the container
- Verify network connectivity between the container and your PeerTube instance

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source. Please check the license file for details.

## Links

- [PeerTube](https://github.com/Chocobozzz/PeerTube)
- [PeerTube Runner](https://www.npmjs.com/package/@peertube/peertube-runner)
- [Whisper-CTranslate2](https://github.com/guillaumekln/faster-whisper)
- [CTranslate2](https://github.com/OpenNMT/CTranslate2)
