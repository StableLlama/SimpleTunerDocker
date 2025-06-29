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
  && curl https://rclone.org/install.sh | bash \
  && rm -rf /var/lib/apt/lists/*

# ----- new RUN for new layer to keep the above stable and frozen -----

RUN (PIP_ROOT_USER_ACTION=ignore; python3 -m pip install pip --upgrade \
 && pip3 install \
      "huggingface_hub[cli,hf_transfer]" \
      wandb  \
      poetry \
 && pip3 cache purge)

# ----- new RUN for new layer to keep the above stable and frozen -----

# NOTE: Disabled, as it's currently too big to build on GitHub
#RUN --mount=type=secret,id=HF_TOKEN,env=HF_TOKEN \
#    huggingface-cli login --token $HF_TOKEN \
# && HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download black-forest-labs/FLUX.1-dev --local-dir /app/FLUX.1-dev
# && HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download stablellama/TEST --local-dir /app/FLUX.1-dev

# ----- new RUN for new layer to keep the above stable and frozen -----

# Clone and install SimpleTuner
# decide for branch "release" or "main" (possibly unstable)
ENV SIMPLETUNER_BRANCH=release
#ENV SIMPLETUNER_BRANCH=main
SHELL ["/bin/bash", "-c"]
RUN git config --global credential.helper cache \
 && git clone https://github.com/bghira/SimpleTuner --branch $SIMPLETUNER_BRANCH \
 && cd SimpleTuner \
 && python3 -m venv .venv \
 && export FORCE_CUDA=1 \
 && poetry config virtualenvs.create false \
 && poetry install --no-root --with jxl \
 && source .venv/bin/activate \
 && pip3 install https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.0.post2/flash_attn-2.8.0.post2+cu12torch2.7cxx11abiFALSE-cp310-cp310-linux_x86_64.whl \
 && pip3 cache purge \
 && poetry cache clear --all pypi \
 && chmod +x train.sh \
 && touch /etc/rp_environment \
 && echo 'source /etc/rp_environment' >> ~/.bashrc

# test FA install:
#RUN cd SimpleTuner && source .venv/bin/activate \
# && pip install ninja \
# && ninja --version \
# && echo $? \
# && git clone https://github.com/Dao-AILab/flash-attention \
# && cd flash-attention/hopper \
# && MAX_JOBS=4 python3 setup.py install

# Copy start script with exec permissions
COPY --chmod=755 start.sh /start.sh

# Ensure SSH access. Not needed for Runpod but is required on Vast and other Docker hosts
EXPOSE 22/tcp

# Dummy entrypoint
ENTRYPOINT [ "/start.sh" ]
