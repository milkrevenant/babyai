#!/usr/bin/env bash
set -euo pipefail

# Self-check for local(macOS) vs cloud(Linux) parity.
# Optional: SKIP_DOCKER_BUILD=1 ./apps/backend/scripts/self_check_env_parity.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

echo "== Host =="
uname -a
if command -v sw_vers >/dev/null 2>&1; then
  sw_vers
fi
echo "arch: $(uname -m)"
echo

echo "== Tool versions =="
go version
if command -v flutter >/dev/null 2>&1; then
  flutter --version | head -n 4
else
  echo "flutter: not installed"
fi
if command -v docker >/dev/null 2>&1; then
  docker version --format 'docker client: {{.Client.Version}}'
else
  echo "docker: not installed"
fi
echo

echo "== Go target =="
go env GOOS GOARCH CGO_ENABLED
echo

GO_MOD_VERSION="$(awk '/^go /{print $2; exit}' apps/backend/go.mod)"
DOCKER_GO_IMAGE="$(sed -n 's/^FROM golang:\([^ ]*\) AS builder/\1/p' Dockerfile | head -n 1)"
DOCKER_GO_VERSION="${DOCKER_GO_IMAGE%%-*}"
GO_MOD_MM="$(echo "$GO_MOD_VERSION" | awk -F. '{print $1 "." $2}')"
DOCKER_GO_MM="$(echo "$DOCKER_GO_VERSION" | awk -F. '{print $1 "." $2}')"

echo "go.mod version: ${GO_MOD_VERSION}"
echo "Docker builder Go image: ${DOCKER_GO_IMAGE}"
if [[ "$GO_MOD_MM" != "$DOCKER_GO_MM" ]]; then
  echo "WARN: go.mod and Docker Go versions differ in major/minor."
fi
echo

echo "== Build check (linux/amd64, CGO off) =="
TMP_BIN="$(mktemp /tmp/babyai-api-parity.XXXXXX)"
rm -f "$TMP_BIN"
(
  cd apps/backend
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$TMP_BIN" ./cmd/api
)
if command -v file >/dev/null 2>&1; then
  file "$TMP_BIN"
fi
rm -f "$TMP_BIN"
echo "ok: cross-build succeeded"
echo

if command -v docker >/dev/null 2>&1; then
  if [[ "${SKIP_DOCKER_BUILD:-0}" == "1" ]]; then
    echo "== Docker build check skipped (SKIP_DOCKER_BUILD=1) =="
    echo
  else
    echo "== Docker buildx check (linux/amd64, builder stage) =="
    if docker buildx inspect >/dev/null 2>&1; then
      docker buildx build \
        --platform linux/amd64 \
        --target builder \
        --progress=plain \
        -f Dockerfile \
        . >/tmp/babyai-docker-buildx-check.log
      echo "ok: docker buildx linux/amd64 builder-stage build succeeded"
      echo "log: /tmp/babyai-docker-buildx-check.log"
      echo
    else
      echo "WARN: docker buildx is not available. Skipping container parity build."
      echo "      install guide: https://docs.docker.com/build/buildx/install/"
      echo
    fi
  fi
fi

echo "Self-check complete."
