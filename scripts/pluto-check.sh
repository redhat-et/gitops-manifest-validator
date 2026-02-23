#!/bin/bash
set -uo pipefail

WORK_DIR="$1"
TARGET_K8S_VERSION="$2"

pluto detect-files \
    -d "$WORK_DIR" \
    --target-versions "k8s=$TARGET_K8S_VERSION" \
    -o json
