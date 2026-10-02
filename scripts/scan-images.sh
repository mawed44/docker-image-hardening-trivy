#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v trivy >/dev/null; then
    printf 'Installer Trivy et l ajouter au PATH.\n' >&2
    exit 1
fi
mkdir -p reports
rm -f reports/trivy-before.{json,txt} reports/trivy-after.{json,txt}

docker build --file Dockerfile.before --tag hardening-lab:before .
docker build --file Dockerfile --tag hardening-lab:after .

for stage in before after; do
    trivy image --scanners vuln --format json \
        --output "reports/trivy-$stage.json" "hardening-lab:$stage"
    trivy convert --scanners vuln --format table --table-mode summary --output "reports/trivy-$stage.txt" \
        "reports/trivy-$stage.json"
done

docker image ls --filter 'reference=hardening-lab:*'
printf '\nRapports disponibles dans reports/. Verification de l image durcie :\n'
trivy convert --scanners vuln --format table --severity HIGH,CRITICAL --exit-code 1 reports/trivy-after.json
