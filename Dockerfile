FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip ffmpeg curl ca-certificates

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

RUN pip3 install --no-cache-dir \
        ctranslate2==4.6.0 \
        whisper-ctranslate2==0.5.3

RUN npm install -g @peertube/peertube-runner
RUN rm -rf /var/lib/apt/lists/*

# Copy and set permissions as root before switching user
COPY start.sh /home/runner/start.sh
RUN chmod +x /home/runner/start.sh

# Create user and switch
RUN useradd -ms /bin/bash runner
RUN chown -R runner:runner /home/runner
USER runner
WORKDIR /home/runner

ENTRYPOINT ["./start.sh"]