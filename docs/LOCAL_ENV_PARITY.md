# Local (macOS) vs Cloud (Linux) Parity

This project is often developed on macOS but deployed to Linux containers. Use this checklist before production deploys.

## Official references
- Cloud Run container runtime contract (`PORT`, listen interface): https://cloud.google.com/run/docs/container-contract
- Cloud Run troubleshooting (ARM build mismatch symptom): https://cloud.google.com/run/docs/troubleshooting
- Docker Buildx `--platform`: https://docs.docker.com/reference/cli/docker/buildx/build/
- Docker Buildx install: https://docs.docker.com/build/buildx/install/
- Amazon ECS task `runtimePlatform` (`cpuArchitecture`): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#runtime_platform
- Go environment variables (`GOOS`, `GOARCH`, `CGO_ENABLED`): https://pkg.go.dev/cmd/go#hdr-Environment_variables

## High-impact differences
1. CPU architecture mismatch
   - Mac can be `arm64`, while many cloud targets run `linux/amd64`.
   - Build and test images for target platform explicitly.
2. OS/runtime mismatch
   - Local app can run with host defaults; Cloud Run/ECS containers must follow runtime contract and container networking.
3. Port binding mismatch
   - Cloud runtime injects `PORT`; app must listen on that port and on `0.0.0.0`.
4. CGO/system library mismatch
   - Native dependencies that work on macOS can fail in Linux runtime unless included in image.

## Required pre-deploy checks
1. Cross-compile backend binary:
   - `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build ./apps/backend/cmd/api`
2. Build container image for target platform:
   - `docker buildx build --platform linux/amd64 -f Dockerfile .`
3. Confirm runtime port handling:
   - Backend config must use `PORT` env in cloud.
4. Keep Go versions aligned:
   - `apps/backend/go.mod` and Docker `golang:` image should match major/minor.

## Project self-check script
Run:

```bash
./apps/backend/scripts/self_check_env_parity.sh
```

Optional (skip Docker build step):

```bash
SKIP_DOCKER_BUILD=1 ./apps/backend/scripts/self_check_env_parity.sh
```
