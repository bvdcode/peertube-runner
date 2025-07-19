#!/usr/bin/env bash

set -e

# Start the PeerTube runner
exec peertube-runner server --enable-job video-transcription






      - ./config.toml:/home/runner/.config/peertube-runner-nodejs/default/config.toml:ro



      /home/runner/config.toml:ro