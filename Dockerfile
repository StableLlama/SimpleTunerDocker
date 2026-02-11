ARG BASE_IMAGE=simpletuner-base:cuda12.8.1
FROM ${BASE_IMAGE}
ARG CUDA_VERSION=12.8.1

# Set the working directory inside the container
WORKDIR /app

RUN mkdir -p /workspace/simpletuner \
 && echo "export BUILD_TIMESTAMP='$(date -u +"%Y-%m-%dT%H:%M:%S.%6N%:z")'" >/etc/rp_build_environment
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
ENV SIMPLETUNER_BRANCH=release
#ENV SIMPLETUNER_BRANCH=main
### TMP: try a PR \
#ENV SIMPLETUNER_BRANCH="feature/track-grad-absmax-separately-for-regularisation"
SHELL ["/bin/bash", "-c"]
RUN echo "Installing SimpleTuner from Git" \
 && echo "export SIMPLETUNER_INSTALL_TYPE=git" >>/etc/rp_build_environment \
 && git clone --depth 1 https://github.com/bghira/SimpleTuner --branch $SIMPLETUNER_BRANCH \
 && cd SimpleTuner \
 && echo "SimpleTuner git branch: $SIMPLETUNER_BRANCH" \
 && echo "SimpleTuner git rev: $(git rev-parse HEAD)" \
 && echo "SimpleTuner git rev short: $(git rev-parse --short HEAD)" \
 && echo "export SIMPLETUNER_GIT_REV='$(git rev-parse HEAD)'" >>/etc/rp_build_environment \
 && echo "export SIMPLETUNER_GIT_REV_SHORT='$(git rev-parse --short HEAD)'" >>/etc/rp_build_environment \
 #   ### TMP: try a PR \
 # && git switch feature/track-grad-absmax-separately-for-regularisation \
 && export FORCE_CUDA=1 \
 && echo "Installing SimpleTuner" \
 && source ${VENV_PATH}/bin/activate \
 && CUDA_MAJOR=$(echo $CUDA_VERSION | cut -d. -f1) \
 && if [ "$CUDA_MAJOR" -ge 13 ]; then \
      EXTRA_OPTIONS="[cuda13,jxl]"; \
      EXTRA_INDEX_URL="--extra-index-url https://download.pytorch.org/whl/cu130"; \
    else \
      EXTRA_OPTIONS="[cuda,jxl]"; \
      EXTRA_INDEX_URL=""; \
    fi \
 && pip install --no-cache-dir -e .$EXTRA_OPTIONS $EXTRA_INDEX_URL \
 && echo "Installing SageAttention" \
 && pip install --no-build-isolation --no-cache-dir sageattention==1.0.6 \
 && echo "Installing finished" \
 && pip cache purge \
 && rm -rf /root/.cache 

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

# Ensure SSH access
EXPOSE 22/tcp
# WebUI
EXPOSE 8001/tcp

ENTRYPOINT [ "/start.sh" ]
