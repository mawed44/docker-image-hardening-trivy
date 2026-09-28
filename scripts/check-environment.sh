#!/usr/bin/env bash
set -euo pipefail

# Verification en lecture seule, depuis Linux ou Ubuntu dans WSL.
for tool in git python3 docker; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '[ERREUR] %s est introuvable.\n' "$tool" >&2
        if [[ "$tool" == "docker" ]]; then
            printf 'Sous WSL, verifier Docker Desktop et son integration avec Ubuntu.\n' >&2
        fi
        exit 1
    fi
    if ! "$tool" --version; then
        printf '[ERREUR] %s est present mais inutilisable.\n' "$tool" >&2
        if [[ "$tool" == "docker" ]]; then
            printf 'Activer Docker Desktop > Settings > Resources > WSL Integration > Ubuntu.\n' >&2
        fi
        exit 1
    fi
done

if ! docker_system=$(docker info --format '{{.OSType}}' 2>/dev/null); then
    printf '[ERREUR] Moteur Docker inaccessible. Verifier son demarrage et les droits d acces.\n' >&2
    printf 'Sous WSL, verifier aussi l integration Docker Desktop avec Ubuntu.\n' >&2
    exit 1
fi

if [[ "$docker_system" != "linux" ]]; then
    printf '[ERREUR] Ce projet necessite des conteneurs Linux.\n' >&2
    exit 1
fi

docker info --format '[INFO] Systeme Docker : {{.OSType}} ; noyau : {{.KernelVersion}}'
printf '[OK] Git, Python 3 et le moteur Docker Linux sont disponibles.\n'
printf '[A VALIDER] Compatibilite eBPF (BTF et ring buffer) et observation des conteneurs par Falco.\n'
