#!/bin/bash

# useful information
# see also: https://github.com/bghira/SimpleTuner/blob/main/OPTIONS.md#environment-configuration-variables
echo "export GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)" >/etc/rp_environment
echo "export DISABLE_UPDATES=true" >>/etc/rp_environment
echo "export TRAINING_NUM_PROCESSES=$(nvidia-smi --list-gpus | wc -l)" >>/etc/rp_environment
echo "export TRAINING_NUM_MACHINES=1" >>/etc/rp_environment
echo "export MIXED_PRECISION=bf16" >>/etc/rp_environment
# for substantial speed improvements on NVIDIA hardware
echo "export TRAINING_DYNAMO_BACKEND=inductor" >>/etc/rp_environment

# Export useful ENV variables, including all Runpod specific vars, to /etc/rp_environment
# This file can then later be sourced in a login shell
echo "Exporting environment variables..."
printenv |
  grep -E '^RUNPOD_|^PATH=|^HF_HOME=|^HF_TOKEN=|^HUGGING_FACE_HUB_TOKEN=|^WANDB_API_KEY=|^WANDB_TOKEN=|^_=' |
  sed 's/^\(.*\)=\(.*\)$/export \1="\2"/' >>/etc/rp_environment

# Vast.ai uses $SSH_PUBLIC_KEY
if [[ $SSH_PUBLIC_KEY ]]; then
  PUBLIC_KEY="${SSH_PUBLIC_KEY}"
fi

# Runpod uses $PUBLIC_KEY
if [[ $PUBLIC_KEY ]]; then
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  echo "${PUBLIC_KEY}" >>~/.ssh/authorized_keys
  chmod 700 -R ~/.ssh
fi

# Start SSH server
service ssh start

# Setup /workspace/trainconfig/... as default config for SimpleTuner configuration
ln -sf /workspace/trainconfig /app/SimpleTuner/config/trainconfig
echo "export ENV=trainconfig" >>/etc/rp_environment

# Login to HF
if [[ -n "${HF_TOKEN:-$HUGGING_FACE_HUB_TOKEN}" ]]; then
  echo "export HF_TOKEN_PATH=/root/.cache/huggingface/" >>/etc/rp_environment
  HF_TOKEN_PATH=/root/.cache/huggingface/
  huggingface-cli login --token "${HF_TOKEN:-$HUGGING_FACE_HUB_TOKEN}" --add-to-git-credential
else
  echo "HF_TOKEN or HUGGING_FACE_HUB_TOKEN not set; skipping login"
fi

# Login to WanDB
if [[ -n "${WANDB_API_KEY:-$WANDB_TOKEN}" ]]; then
  wandb login "${WANDB_API_KEY:-$WANDB_TOKEN}"
else
  echo "WANDB_API_KEY or WANDB_TOKEN not set; skipping login"
fi

nvidia-smi

# 🫡
sleep infinity
