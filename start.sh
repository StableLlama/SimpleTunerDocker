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

# Setup /workspace links for SimpleTuner configuration
excluded_dirs=("huggingface" "cache" "output")
non_excluded_found=false
has_files=$(find /workspace -mindepth 1 -maxdepth 1 -not -type d -print -quit 2>/dev/null)

# First check if we have any non-excluded directories to link
for dir in /workspace/*/; do
  [ -d "$dir" ] || continue
  dir_name=$(basename "$dir")
  # Check if directory is in the excluded list
  if ! printf '%s\0' "${excluded_dirs[@]}" | grep -qFxz "$dir_name"; then
    non_excluded_found=true
    break
  fi
done

# Link directories or whole workspace based on conditions
if [ -z "$has_files" ] && [ "$non_excluded_found" = true ]; then
  # Link individual non-excluded directories
  for dir in /workspace/*/; do
    [ -d "$dir" ] || continue
    dir_name=$(basename "$dir")
    if ! printf '%s\0' "${excluded_dirs[@]}" | grep -qFxz "$dir_name"; then
      ln -sf "$dir" "/app/SimpleTuner/config/$dir_name"
    fi
  done
else
  # Link whole workspace if it has files or only excluded directories
  ln -sf /workspace /app/SimpleTuner/config/workspace
  echo "export ENV=workspace" >>/etc/rp_environment
fi

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
