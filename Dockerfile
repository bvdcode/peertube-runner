FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip ffmpeg curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
        ctranslate2==4.6.0 \
        whisper-ctranslate2==0.5.3

RUN npm install -g @peertube/peertube-runner

RUN useradd -ms /bin/bash runner
USER runner
WORKDIR /home/runner

COPY start.sh .
RUN chmod +x start.sh

ENTRYPOINT ["start.sh"]