[![Build Docker Images](https://github.com/StableLlama/SimpleTunerDocker/actions/workflows/docker-build.yml/badge.svg)](https://github.com/StableLlama/SimpleTunerDocker/actions/workflows/docker-build.yml)

# SimpleTuner Docker Containers

This project provides Docker containers for running [SimpleTuner](https://github.com/bghira/SimpleTuner) with different CUDA versions for cloud GPU environments.

Available from https://hub.docker.com/r/stablellama/simpletuner

Relevant environment variables:

- **`TRAINING_NAME`**
  The "Environment" to use in SimpleTuner.
- **`DIRECT_TRAINING`**
  When set the training will start directly, otherwise the SimpleTuner server
  will be started and the training must be started from the UI.
- **`GIT_USER`**
  GitHub username.
- **`GIT_EMAIL`**
  GitHub user mail.
- **`GIT_PAT`**
  GitHub personal access token.
- **`GIT_REPOSITORY`**
  GitHub repository with the training configuration.
- **`HF_TOKEN`**
  Hugging Face token.
- **`WANDB_API_KEY`**
  Wandb API key.
- **`NO_DYNAMO`**
  Do not use Dynamo / inductor.
