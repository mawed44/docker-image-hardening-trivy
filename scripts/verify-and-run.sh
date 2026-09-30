#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Usage: bash scripts/verify-and-run.sh IMAGE@sha256:DIGEST\n' >&2
    exit 1
fi

image="$1"
if [[ ! "$image" =~ ^ghcr\.io/mawed44/docker-security-hardening-sigstore@sha256:[a-f0-9]{64}$ ]]; then
    printf '[ERREUR] Utiliser le digest SHA-256 de l image GHCR de ce projet.\n' >&2
    exit 1
fi

if ! command -v cosign >/dev/null 2>&1; then
    printf '[ERREUR] Installer Cosign avant de lancer ce script.\n' >&2
    exit 1
fi

cosign verify \
    --certificate-identity 'https://github.com/mawed44/docker-security-hardening-sigstore/.github/workflows/container-security.yml@refs/heads/main' \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    "$image"

cd "$(dirname "$0")/.."
export IMAGE_REF="$image"
docker compose up --detach --wait --no-build --pull always api
