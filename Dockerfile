# Base image with CUDA 12.8.1 and cuDNN
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

ENV VENV_PATH=/opt/venv

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
  && touch /etc/rp_environment \
  && echo 'source /etc/rp_environment' >> ~/.bashrc \
  && echo 'echo ""' >> ~/.bashrc \
  && echo 'echo "------------------------"' >> ~/.bashrc \
  && echo 'echo "Live log of start.sh: /var/log/portal/start.sh.log"' >> ~/.bashrc \
  && echo 'echo "Live log of preparation.sh: /var/log/portal/preparation.sh.log"' >> ~/.bashrc \
  && echo 'echo "Live log of SimpleTuner: /var/log/portal/simpletuner.log"' >> ~/.bashrc \
  && echo 'echo "tail -n 999 -f /var/log/portal/simpletuner.log"' >> ~/.bashrc \
  && echo 'echo "------------------------"' >> ~/.bashrc \
  && python${PYTHON_VERSION} -m venv ${VENV_PATH}

# Use the virtual environment for all subsequent Python work
ENV PATH="${VENV_PATH}/bin:${PATH}"

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

RUN mkdir -p /workspace/simpletuner \
 && echo "export BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6N%:z")" >/etc/rp_build_environment
ENV SIMPLETUNER_WORKSPACE=/workspace/simpletuner

# === new way of installing: ===
ENV SIMPLETUNER_PLATFORM=cuda

# Install SimpleTuner from PyPI to match published releases
#RUN echo "Installing SimpleTuner" \
# && echo "export SIMPLETUNER_INSTALL_TYPE=pip" >>/etc/rp_build_environment" \
# && pip install --no-cache-dir simpletuner[cuda,jxl] \
# && echo "Installing SageAttention" \
# && pip install --no-build-isolation --no-cache-dir \
#      sageattention==1.0.6 \
# && echo "Installing finished" \
# && pip cache purge

# === old way of installing: ===
# Clone and install SimpleTuner
# decide for branch "release" or "main" (possibly unstable)
#ENV SIMPLETUNER_BRANCH=release
ENV SIMPLETUNER_BRANCH=main
### TMP: try a PR \
#ENV SIMPLETUNER_BRANCH="feature/track-grad-absmax-separately-for-regularisation"
SHELL ["/bin/bash", "-c"]
RUN echo "Installing SimpleTuner from Git" \
 && echo "export SIMPLETUNER_INSTALL_TYPE=git" >>/etc/rp_build_environment \
 && git clone --depth 1 https://github.com/bghira/SimpleTuner --branch $SIMPLETUNER_BRANCH \
 && cd SimpleTuner \
 && echo "export SIMPLETUNER_GIT_REV=$(git rev-parse HEAD)" >>/etc/rp_build_environment \
 && echo "export SIMPLETUNER_GIT_REV_SHORT=$(git rev-parse --short HEAD)" >>/etc/rp_build_environment \
 #   ### TMP: try a PR \
 # && git switch feature/track-grad-absmax-separately-for-regularisation \
 && export FORCE_CUDA=1 \
 && echo "Installing SimpleTuner" \
 && source ${VENV_PATH}/bin/activate \
 && pip install --no-cache-dir -e .[cuda,jxl] \
 && echo "Installing SageAttention" \
 && pip install --no-build-isolation --no-cache-dir sageattention==1.0.6 \
 && echo "Installing finished" \
 && pip cache purge

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
# WebUI
EXPOSE 8001/tcp

# Dummy entrypoint
ENTRYPOINT [ "/start.sh" ]
