# Base image with CUDA 12.4.1 and cuDNN
#FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
#FROM nvidia/cuda:12.6.1-base-ubuntu24.04
#FROM nvidia/cuda:12.6.1-cudnn-devel-ubuntu24.04
#FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# 8.9 = Ada
ENV TORCH_CUDA_ARCH_LIST=8.9
ENV CUDA_HOME=/usr/local/cuda-12.8
ENV LIBRARY_PATH=$CUDA_HOME/targets/x86_64-linux/lib/stubs:$LIBRARY_PATH
ENV LD_LIBRARY_PATH=$CUDA_HOME/lib64:$CUDA_HOME/targets/x86_64-linux/lib/stubs:$LD_LIBRARY_PATH

ARG PYTHON_VERSION=3.12

# Prevents different commands from being stuck by waiting
# on user input during build
ENV DEBIAN_FRONTEND=noninteractive

# /workspace is a common volume for hosts like Runpod
VOLUME /workspace

# Set the working directory inside the container
WORKDIR /app

# Install system dependencies
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
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
      libglib2.0-0 \
      libopenmpi-dev \
      openmpi-bin \
      ffmpeg \
      libsm6 \
      libxext6 \
      p7zip-full \
      python${PYTHON_VERSION} \
      python${PYTHON_VERSION}-dev \
      python${PYTHON_VERSION}-venv \
  && curl https://rclone.org/install.sh | bash \
  && git config --global credential.helper store \
  && git lfs install \
  && rm -rf /var/lib/apt/lists/* \
  && python${PYTHON_VERSION} -m venv /opt/venv

# Use the virtual environment for all subsequent Python work
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# ----- new RUN for new layer to keep the above stable and frozen -----

# HuggingFace cache location and platform hint for setup.py
ENV HF_HOME=/workspace/huggingface

RUN (PIP_ROOT_USER_ACTION=ignore; /opt/venv/bin/pip install --upgrade pip setuptools wheel \
 && pip install --no-cache-dir \
      "huggingface_hub[cli,hf_transfer]" \
      wandb  \
      poetry \
      mpi4py \
 && pip cache purge)

# ----- new RUN for new layer to keep the above stable and frozen -----

# NOTE: Disabled, as it's currently too big to build on GitHub
#RUN --mount=type=secret,id=HF_TOKEN,env=HF_TOKEN \
#    huggingface-cli login --token $HF_TOKEN \
# && HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download black-forest-labs/FLUX.1-dev --local-dir /app/FLUX.1-dev
# && HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download stablellama/TEST --local-dir /app/FLUX.1-dev

# ----- new RUN for new layer to keep the above stable and frozen -----

RUN mkdir -p /workspace/simpletuner
ENV SIMPLETUNER_WORKSPACE=/workspace/simpletuner

# === new way of installing: ===
ENV SIMPLETUNER_PLATFORM=cuda

# Install SimpleTuner from PyPI to match published releases
##RUN pip install --no-cache-dir simpletuner[cuda,jxl]
## && touch /etc/rp_environment \
## && echo 'source /etc/rp_environment' >> ~/.bashrc

# === old way of installing: ===
# Clone and install SimpleTuner
# decide for branch "release" or "main" (possibly unstable)
#ENV SIMPLETUNER_BRANCH=release
ENV SIMPLETUNER_BRANCH=main
SHELL ["/bin/bash", "-c"]
RUN git clone https://github.com/bghira/SimpleTuner --branch $SIMPLETUNER_BRANCH \
 && cd SimpleTuner \
 && export FORCE_CUDA=1 \
 && pip install --no-cache-dir -e .[jxl] \
 && pip install --no-build-isolation --no-cache-dir \
      urllib3>=2.2.2 \
      sageattention==2.2.0 \
 && pip cache purge \
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
