#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${AWS_ID:-}}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${AWS_SECRET:-}}"

if [[ -z "${AWS_ACCESS_KEY_ID}" || -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
  echo "ERROR: set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or AWS_ID/AWS_SECRET" >&2
  exit 1
fi

echo "[check] region=${AWS_REGION}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
AWS_DEFAULT_REGION="${AWS_REGION}" \
aws connect list-instances --output table
