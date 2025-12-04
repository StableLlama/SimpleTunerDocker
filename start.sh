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

# Setup /workspace/trainconfig/... as default config for SimpleTuner configuration
ln -sf /workspace/trainconfig /app/SimpleTuner/config/trainconfig
echo "export ENV=trainconfig" >>/etc/rp_environment

# Add it to Bash login script only if it doesn't already exist
grep -qxF 'source /etc/rp_environment' ~/.bashrc || echo 'source /etc/rp_environment' >>~/.bashrc

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

nvidia-smi
simpletuner --version

# Login to HF
if [[ -n "${HF_TOKEN:-$HUGGING_FACE_HUB_TOKEN}" ]]; then
  hf auth login --token "${HF_TOKEN:-$HUGGING_FACE_HUB_TOKEN}" --add-to-git-credential
else
  echo "HF_TOKEN or HUGGING_FACE_HUB_TOKEN not set; skipping login"
fi

# Login to WanDB
if [[ -n "${WANDB_API_KEY:-$WANDB_TOKEN}" ]]; then
  wandb login "${WANDB_API_KEY:-$WANDB_TOKEN}"
else
  echo "WANDB_API_KEY or WANDB_TOKEN not set; skipping login"
fi

R2_BUCKET=${R2_BUCKET:-traindata-transfer}
if [[ -v R2_access_key_id ]]; then
  mkdir -p /root/.config/rclone
  cat >/root/.config/rclone/rclone.conf <<EOL
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_access_key_id}
secret_access_key = ${R2_secret_access_key}
endpoint = ${R2_endpoint}
EOL
  echo "Cloudflare R2 configured"
  echo "Bucket: '${R2_BUCKET}'"

  if [[ -v TRAINING_NAME ]]; then
    echo "Training name set to '${TRAINING_NAME}' - trying automated training"
    rclone copy r2:${R2_BUCKET}/${TRAINING_NAME}/trainscript.sh /app
  else
    echo "Training name NOT set"
  fi
else
  echo "NO Cloudflare R2 configured, set environment!"
fi


if [[ -e /app/trainscript.sh ]]; then
  echo "trainscript available - running it"
  echo ""

  bash /app/trainscript.sh
else
  echo "NO trainscript found, starting SimpleTuner server"
  echo ""

  # 🫡
  #sleep infinity
  simpletuner server
fi
