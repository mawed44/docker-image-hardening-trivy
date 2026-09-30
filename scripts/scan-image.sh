#!/usr/bin/env bash
set -euo pipefail

image="${1:-container-hardening-lab:local}"
cd "$(dirname "$0")/.."
mkdir -p reports

trivy image --scanners vuln --severity HIGH,CRITICAL --exit-code 1 \
    --format json --output reports/trivy.json "$image"
