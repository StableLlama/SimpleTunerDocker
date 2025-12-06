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

# Add it to Bash login script only if it doesn't already exist
grep -qxF 'source /etc/rp_environment' ~/.bashrc || echo 'source /etc/rp_environment' >>~/.bashrc
source /etc/rp_environment

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

# Create the accelerate default config
if [[ ! -e /workspace/huggingface/accelerate/default_config.yaml ]]; then
  mkdir -p  /workspace/huggingface/accelerate
  cat >/workspace/huggingface/accelerate/default_config.yaml <<EOL
compute_environment: LOCAL_MACHINE
debug: false
distributed_type: 'NO'
downcast_bf16: 'no'
dynamo_config:
  dynamo_backend: INDUCTOR
  dynamo_mode: max-autotune
  dynamo_use_dynamic: false
  dynamo_use_fullgraph: false
enable_cpu_affinity: true
gpu_ids: all
machine_rank: 0
main_training_function: main
mixed_precision: bf16
num_machines: $TRAINING_NUM_MACHINES
num_processes: $TRAINING_NUM_PROCESSES
rdzv_backend: static
same_network: true
tpu_env: []
tpu_use_cluster: false
tpu_use_sudo: false
use_cpu: false
EOL
fi

if [[ -v GIT_USER && -v GIT_PAT && -v GIT_REPOSITORY ]]; then
  if [[ ! -e /workspace/simpletuner/config ]]; then
    pushd /workspace/simpletuner
    git clone https://$GIT_USER:$GIT_PAT@github.com/$GIT_REPOSITORY config
    popd
  else
    pushd /workspace/simpletuner/config
    git reset --hard
    git pull
    popd
  fi
else
  echo "Git access not properly setup! All three environment variables are needed!"
  echo "GIT_USER: '$GIT_USER'"
  echo "GIT_PAT: '$GIT_PAT'"
  echo "GIT_REPOSITORY: '$GIT_REPOSITORY'"
fi

# Setup the SimpleTuner onboarding config with the correct paths for this setup
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6N%:z")s

mkdir -p /workspace/simpletuner/datasets
mkdir -p /workspace/simpletuner/output

if [[ ! -e /workspace/simpletuner/webui/onboarding.json ]]; then
  mkdir -p /workspace/simpletuner/webui
  cat >/workspace/simpletuner/webui/onboarding.json <<EOL
{
  "steps": {
    "accelerate_defaults": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 1,
      "value": {
        "--num_processes": $TRAINING_NUM_PROCESSES,
        "mode": "auto"
      }
    },
    "create_initial_environment": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 1,
      "value": "$TRAINING_NAME"
    },
    "default_configs_dir": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 2,
      "value": "/workspace/simpletuner/config"
    },
    "default_datasets_dir": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 2,
      "value": "/workspace/simpletuner/datasets"
    },
    "default_output_dir": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 1,
      "value": "/workspace/simpletuner/output"
    }
  }
}
EOL
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
    rclone copy r2:${R2_BUCKET}/${TRAINING_NAME}/trainscript.sh /workspace
  else
    echo "Training name NOT set"
  fi
else
  echo "NO Cloudflare R2 configured, set environment!"
fi

if [[ -e /workspace/trainscript.sh ]]; then
  echo "trainscript available - running it"
  echo ""

  source /workspace/trainscript.sh
else
  echo "NO trainscript found, starting SimpleTuner server"
  echo ""

  # 🫡
  #sleep infinity
  simpletuner server
fi
