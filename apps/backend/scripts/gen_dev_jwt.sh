#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy .env.example to .env first." >&2
  exit 1
fi

JWT_SECRET="$(
  grep -E '^JWT_SECRET=' "${ENV_FILE}" | head -n 1 | cut -d'=' -f2-
)"

if [[ -z "${JWT_SECRET}" ]]; then
  echo "JWT_SECRET is missing in ${ENV_FILE}" >&2
  exit 1
fi

SUB="${1:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
NAME="${2:-Dev User}"
PROVIDER="${3:-google}"

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

HEADER='{"alg":"HS256","typ":"JWT"}'
PAYLOAD=$(printf '{"sub":"%s","provider":"%s","name":"%s"}' "${SUB}" "${PROVIDER}" "${NAME}")

ENCODED_HEADER=$(printf '%s' "${HEADER}" | b64url)
ENCODED_PAYLOAD=$(printf '%s' "${PAYLOAD}" | b64url)
UNSIGNED="${ENCODED_HEADER}.${ENCODED_PAYLOAD}"
SIGNATURE=$(printf '%s' "${UNSIGNED}" | openssl dgst -sha256 -hmac "${JWT_SECRET}" -binary | b64url)
TOKEN="${UNSIGNED}.${SIGNATURE}"

cat <<EOF
SUB=${SUB}
TOKEN=${TOKEN}
EOF
