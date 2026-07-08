FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV VIRTUAL_ENV="/opt/peertube-runner-venv"
ENV PATH="${VIRTUAL_ENV}/bin:/usr/local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv ffmpeg curl ca-certificates && \
    mv /usr/bin/ffmpeg /usr/local/bin/ffmpeg-real && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m venv "${VIRTUAL_ENV}" && \
    pip install --no-cache-dir \
    ctranslate2==4.6.0 \
    whisper-ctranslate2==0.5.3

RUN npm install -g @peertube/peertube-runner

COPY start.sh /home/runner/start.sh
RUN chmod +x /home/runner/start.sh

COPY ffmpeg-nvenc-wrapper.sh /usr/local/bin/ffmpeg
RUN chmod +x /usr/local/bin/ffmpeg

RUN useradd -ms /bin/bash runner && \
    chown -R runner:runner /home/runner
USER runner
WORKDIR /home/runner

ENTRYPOINT ["./start.sh"]
