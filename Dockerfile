# Base image with CUDA 12.4.1 and cuDNN
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

# Prevents different commands from being stuck by waiting
# on user input during build
ENV DEBIAN_FRONTEND=noninteractive

# HF
ENV HF_HOME=/workspace/huggingface

# /workspace is a common volume for hosts like Runpod
VOLUME /workspace

# Set the working directory inside the container
WORKDIR /app

# Install system dependencies
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      openssh-server \
      openssh-client \
      git \
      git-lfs \
      wget \
      curl \
      tmux \
      tldr \
      nvtop \
      vim \
      rsync \
      net-tools \
      less \
      iputils-ping \
      7zip \
      zip \
      unzip \
      htop \
      inotify-tools \
      nvidia-cuda-toolkit \
      libgl1-mesa-glx \
      libglib2.0-0 \
      ffmpeg \
      libsm6 \
      libxext6 \
      python3 \
      python3-pip \
      python3.10-venv \
      python3.10-dev \
  && rm -rf /var/lib/apt/lists/*

# ----- new RUN for new layer to keep the above stable and frozen -----

RUN python3 -m pip install pip --upgrade \
 && pip3 install \
      "huggingface_hub[cli,hf_transfer]" \
      wandb  \
      poetry \
 && pip3 cache purge

# ----- new RUN for new layer to keep the above stable and frozen -----

#RUN --mount=type=secret,id=HF_TOKEN,env=HF_TOKEN \
#    huggingface-cli login --token $HF_TOKEN \
# && HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download black-forest-labs/FLUX.1-dev --local-dir /app/FLUX.1-dev
# && HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download stablellama/TEST --local-dir /app/FLUX.1-dev

# ----- new RUN for new layer to keep the above stable and frozen -----

# Clone and install SimpleTuner
# decide for branch "release" or "main" (possibly unstable)
#RUN git clone https://github.com/bghira/SimpleTuner --branch release
RUN git clone https://github.com/bghira/SimpleTuner --branch main \
 && cd SimpleTuner \
 && python3 -m venv .venv \
 && export FORCE_CUDA=1 \
 && poetry config virtualenvs.create false \
 && poetry install --no-root --with jxl \
 && chmod +x train.sh \
 && touch /etc/rp_environment \
 && echo 'source /etc/rp_environment' >> ~/.bashrc

# Copy start script with exec permissions
COPY --chmod=755 docker-start.sh /start.sh

# Ensure SSH access. Not needed for Runpod but is required on Vast and other Docker hosts
EXPOSE 22/tcp

# Dummy entrypoint
ENTRYPOINT [ "/start.sh" ]
