#!/usr/bin/env bash
set -euo pipefail

image_name="ghcr.io/${GITHUB_REPOSITORY,,}"
signer="https://github.com/${GITHUB_REPOSITORY}/.github/workflows/container-security.yml@refs/heads/main"

docker load --input "$RUNNER_TEMP/image.tar"
printf '%s' "$GITHUB_TOKEN" | docker login ghcr.io --username "$GITHUB_ACTOR" --password-stdin
docker tag container-hardening-lab:local "$image_name:$GITHUB_SHA"
docker push "$image_name:$GITHUB_SHA"

image_ref=$(docker image inspect --format '{{index .RepoDigests 0}}' "$image_name:$GITHUB_SHA")
[[ "$image_ref" == "$image_name@sha256:"* ]]

cosign sign --yes "$image_ref"
cosign verify --certificate-identity "$signer" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com "$image_ref"

printf 'Image signee : %s\n' "$image_ref" >> "$GITHUB_STEP_SUMMARY"
