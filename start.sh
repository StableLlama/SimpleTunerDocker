#!/bin/bash

cp /etc/rp_build_environment /etc/rp_environment
# useful information
# see also: https://github.com/bghira/SimpleTuner/blob/main/OPTIONS.md#environment-configuration-variables
echo "export GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)" >>/etc/rp_environment
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

echo "export SIMPLETUNER_VERSION='$(simpletuner --version 2>/dev/null | xargs)'" >>/etc/rp_environment
echo "export START_TIME=$(date -u +"%Y%m%d_%H%M%S")" >>/etc/rp_environment
echo "export START_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6N%:z")" >>/etc/rp_environment

# Add it to Bash login script only if it doesn't already exist
grep -qxF 'source /etc/rp_environment' ~/.bashrc || echo 'source /etc/rp_environment' >>~/.bashrc
source /etc/rp_environment

# Vast.ai uses $SSH_PUBLIC_KEY
if [[ $SSH_PUBLIC_KEY ]]; then
  echo "INFO: Found SSH_PUBLIC_KEY, using it as PUBLIC_KEY"
  PUBLIC_KEY="${SSH_PUBLIC_KEY}"
fi

# Runpod uses $PUBLIC_KEY
if [[ $PUBLIC_KEY ]]; then
  echo "INFO: Setting up SSH, adding PUBLIC_KEY to authorized_keys"
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  echo "${PUBLIC_KEY}" >>~/.ssh/authorized_keys
  chmod 700 -R ~/.ssh
fi

# disable SSH password login - use key instead!
sed -i -E 's/#?PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Start SSH server
service ssh start

nvidia-smi
echo "Version: ${SIMPLETUNER_VERSION}"

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
if [[ -v NO_DYNAMO ]]; then
  echo "Dynamo disabled - removing it from accelerate config"
  sed -i "/dynamo/d" /workspace/huggingface/accelerate/default_config.yaml
fi

if [[ -v GIT_USER && -v GIT_PAT && -v GIT_REPOSITORY ]]; then
  echo "Setting up GitHub based config"
  if [[ ! -e /workspace/simpletuner/config ]]; then
    pushd /workspace/simpletuner > /dev/null
    git config --global user.email "${GIT_EMAIL:-you@example.com}"
    git config --global user.name "${GIT_USER}"
    git clone --depth 1 "https://${GIT_USER}:${GIT_PAT}@github.com/${GIT_REPOSITORY}" config
    popd > /dev/null
  else
    pushd /workspace/simpletuner/config > /dev/null
    git reset --hard
    git pull
    popd > /dev/null
  fi
else
  echo "ERROR: Git access not properly setup! All three environment variables are needed!"
  echo "GIT_USER: '${GIT_USER}'"
  echo "GIT_PAT: '${GIT_PAT}'"
  echo "GIT_REPOSITORY: '${GIT_REPOSITORY}'"
  exit
fi

# Setup the SimpleTuner onboarding config with the correct paths for this setup
TIMESTAMP="${START_TIMESTAMP}s"

mkdir -p /workspace/simpletuner/datasets
mkdir -p /workspace/simpletuner/output

if [[ ! -e /workspace/simpletuner/webui/onboarding.json ]]; then
  mkdir -p /workspace/simpletuner/webui
  cat >/workspace/simpletuner/webui/onboarding.json <<EOL
{
  "steps": {
    "accelerate_defaults": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 2,
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
      "completed_version": 3,
      "value": "/workspace/simpletuner/config"
    },
    "default_datasets_dir": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 3,
      "value": "/workspace/simpletuner/datasets"
    },
    "default_output_dir": {
      "completed_at": "$TIMESTAMP",
      "completed_version": 2,
      "value": "/workspace/simpletuner/output"
    }
  }
}
EOL
  cat >/workspace/simpletuner/webui/defaults.json <<EOL
{
  "accelerate_overrides": {},
  "active_config": "${TRAINING_NAME}",
  "admin_dismissed_hints": [],
  "admin_tab_enabled": true,
  "allow_dataset_paths_outside_dir": false,
  "audit_export_auth_token": null,
  "audit_export_format": "json",
  "audit_export_security_only": false,
  "audit_export_webhook_url": null,
  "auto_preserve_defaults": true,
  "cloud_data_consent": "ask",
  "cloud_dataloader_hint_dismissed": false,
  "cloud_git_hint_dismissed": false,
  "cloud_job_polling_enabled": null,
  "cloud_outputs_dir": null,
  "cloud_tab_enabled": null,
  "cloud_webhook_url": null,
  "configs_dir": "/workspace/simpletuner/config",
  "credential_early_warning_enabled": false,
  "credential_early_warning_percent": 75,
  "credential_rotation_threshold_days": 90,
  "credential_security_configured": false,
  "credential_security_skipped": false,
  "datasets_dir": "/workspace/simpletuner/datasets",
  "event_polling_interval": 5,
  "event_stream_enabled": true,
  "git_auto_commit": false,
  "git_branch": null,
  "git_include_untracked": false,
  "git_mirror_enabled": false,
  "git_push_on_snapshot": false,
  "git_remote": null,
  "git_require_clean": false,
  "local_gpu_max_concurrent": null,
  "local_job_max_concurrent": 1,
  "metrics_dismissed_hints": [],
  "metrics_prometheus_categories": [
    "jobs",
    "http"
  ],
  "metrics_prometheus_enabled": false,
  "metrics_tab_enabled": true,
  "metrics_tensorboard_enabled": false,
  "onboarding_sync_opt_out": [],
  "output_dir": "/workspace/simpletuner/output",
  "public_registration_default_level": null,
  "public_registration_enabled": null,
  "show_documentation_links": true,
  "sounds_enabled": true,
  "sounds_error_enabled": true,
  "sounds_info_enabled": true,
  "sounds_retro_hover_enabled": false,
  "sounds_success_enabled": true,
  "sounds_volume": 50,
  "sounds_warning_enabled": true,
  "sync_onboarding_defaults": false,
  "theme": "dark"
}
EOL
fi

mkdir -p /var/log/portal/

if [[ -v TRAINING_NAME && -e /workspace/simpletuner/config/$TRAINING_NAME/preparation.sh ]]; then
  echo "running preparation for '${TRAINING_NAME}'"
  rm -f /var/log/portal/preparation.sh.log
  source "/workspace/simpletuner/config/${TRAINING_NAME}/preparation.sh" | tee -a "/var/log/portal/preparation.sh.log"
fi

rm -f /var/log/portal/simpletuner.log
source ${VENV_PATH}/bin/activate
if [[ -v USE_SSL ]]; then
  echo "Starting SimpleTuner server (with SSL)"
  SSL_OPTION="--ssl"
else
  echo "Starting SimpleTuner server (without SSL)"
  SSL_OPTION=""
fi
if [[ -v DIRECT_TRAINING ]]; then
  echo "Configured to start training immediately"
  if [[ -v TRAINING_NAME ]]; then
    echo ""
    cd "/workspace/simpletuner/config/${TRAINING_NAME}/"
    GIT_TRAINING_TAG="${TRAINING_NAME}_${START_TIME}"
    git tag "${GIT_TRAINING_TAG}" -m "Training of '${TRAINING_NAME}' started at ${START_TIMESTAMP}"
    git push origin "${GIT_TRAINING_TAG}"
    export SIMPLETUNER_JOB_ID="${GIT_TRAINING_TAG}"
    simpletuner server $SSL_OPTION --env "${TRAINING_NAME}" --host 0.0.0.0 --port 8001 2>&1 | tee -a "/var/log/portal/simpletuner.log"
  else
    echo "ERROR: TRAINING_NAME not set, please set it to define what should be trained!"
  fi
else
  echo ""
  simpletuner server $SSL_OPTION --host 0.0.0.0 --port 8001 2>&1 | tee -a "/var/log/portal/simpletuner.log"
fi

if [[ -v SLEEP_WHEN_FINISHED ]]; then
  echo "Finished, now going to sleep as requested"
  sleep infinity
fi
