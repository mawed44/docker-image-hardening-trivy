# Durcissement d’images Docker & scan de conteneurs (Trivy)

[![Docker image scans](https://github.com/mawed44/docker-security-hardening-sigstore/actions/workflows/container-security.yml/badge.svg)](https://github.com/mawed44/docker-security-hardening-sigstore/actions/workflows/container-security.yml)

Ce laboratoire compare deux images Docker d’une même petite API Python : une image Debian complète exécutée en root, puis une image Alpine minimale exécutée avec l’utilisateur `10001`. **Trivy** mesure les vulnérabilités avant et après le durcissement.

## Problématique

Une image peut embarquer des bibliothèques vulnérables et des outils inutiles à l’application. Exécuter cette application en root augmente aussi l’impact d’une compromission.

## Solution apportée

L’[API Flask](main.py) expose `GET /` et `GET /health`. Les deux images utilisent Python `3.12.16`, les mêmes [dépendances](requirements.txt) et le même serveur Gunicorn.

| Fichier | Rôle |
| --- | --- |
| [Dockerfile.before](Dockerfile.before) | Image Debian complète, avec les outils de développement et l’utilisateur root par défaut |
| [Dockerfile](Dockerfile) | Image Alpine, utilisateur `10001:10001`, installation sans cache et suppression de pip |
| [scripts/scan-images.sh](scripts/scan-images.sh) | Construction des deux images, scans Trivy et génération des rapports |
| [Workflow GitHub Actions](.github/workflows/container-security.yml) | Exécution du script à chaque `push` sur `main` et `pull_request` vers `main` |

La base Alpine ne contient pas `curl`, `apt`, `bash` ou `gcc`. Elle conserve le shell BusyBox `sh` et le gestionnaire `apk` : cette image n’est pas Distroless. Les bases sont fixées par version et digest.

Le script conserve **toutes les sévérités** dans les rapports JSON et génère des résumés texte. Il termine en erreur si l’image durcie contient une vulnérabilité `HIGH` ou `CRITICAL`. Les failles de l’image de départ servent au comparatif et ne bloquent pas ce contrôle.

## Résultats attendus

- Réduire la taille de l’image et le nombre de vulnérabilités détectées.
- Faire fonctionner la même API sans utiliser root.
- Conserver un rapport lisible et un rapport JSON pour chaque image.
- Télécharger les rapports depuis GitHub Actions pendant 30 jours, même si le contrôle final échoue.

## Comparatif avant / après

Mesures locales du **30 octobre 2026**, avec Trivy `0.76.1`, sa base de vulnérabilités mise à jour le même jour et Docker Desktop sur `linux/amd64`.

| Critère | Avant | Après |
| --- | --- | --- |
| Base Linux | Debian Bookworm `12.15` | Alpine `3.24.3` |
| Occupation disque affichée par Docker | 1,48 Go | 84,3 Mo |
| Utilisateur | root, UID `0` | app, UID `10001` |
| Paquets du système détectés | 429 | 38 |
| Vulnérabilités `CRITICAL` | 20 | 0 |
| Vulnérabilités `HIGH` | 467 | 0 |
| Vulnérabilités `MEDIUM` | 2 004 | 0 |
| Vulnérabilités `LOW` | 1 905 | 0 |
| Sévérité `UNKNOWN` | 62 | 0 |
| **Total des détections** | **4 458** | **0** |
| Réponse de `/health` | `200`, `{"status":"ok"}` | `200`, `{"status":"ok"}` |

L’occupation disque diminue d’environ **94 %**. Les totaux comptent les couples paquet/vulnérabilité, pas les CVE uniques. Le changement de base et le retrait de pip réduisent les composants exposés ; l’utilisateur non-root limite les privilèges mais ne corrige pas les CVE.

Ces résultats dépendent des images, de la plateforme et de la base Trivy à la date du scan. Zéro détection ne garantit pas l’absence de vulnérabilités. Le nouveau workflow devra être validé sur GitHub après le prochain push.

Consulter les rapports [avant](reports/trivy-before.txt) et [après](reports/trivy-after.txt), ainsi que leurs versions JSON [avant](reports/trivy-before.json) et [après](reports/trivy-after.json).

## Lancer le projet

Installer **Docker Desktop en mode conteneurs Linux** et [Trivy](https://trivy.dev/docs/latest/getting-started/installation/). Les commandes suivantes s’exécutent depuis la racine du projet dans **Bash** ; sous Windows, utiliser Git Bash avec `trivy.exe` accessible dans le `PATH`.

**1. Vérifier les outils**

```bash
docker info --format '{{.OSType}}'
trivy --version
```

Docker doit afficher `linux`. Aucun Python local n’est nécessaire.

**2. Construire et scanner les deux images**

```bash
bash scripts/scan-images.sh
```

Le premier scan télécharge la base de vulnérabilités Trivy. Les résultats remplacent les fichiers dans `reports/`. Le script affiche les tailles des images puis le résultat du contrôle `HIGH,CRITICAL` de l’image durcie. Pour consulter les détails :

```bash
cat reports/trivy-before.txt
cat reports/trivy-after.txt
```

**3. Lancer l’image durcie**

```bash
docker run --detach --name hardening-api \
  --publish 127.0.0.1:18080:8080 hardening-lab:after
curl http://127.0.0.1:18080/health
docker exec hardening-api id
```

La réponse attendue est `{"status":"ok"}`. La commande `id` doit afficher `uid=10001(app) gid=10001(app)`. Ouvrir aussi [http://localhost:18080](http://localhost:18080) dans le navigateur.

**4. Arrêter l’application**

```bash
docker stop hardening-api
docker rm hardening-api
```

Dans GitHub Actions, le job `scan` effectue les mêmes constructions et scans. Les résultats sont disponibles dans l’artefact `trivy-reports` de chaque exécution. Le comparatif du README est une mesure datée ; il ne se met pas à jour automatiquement.

## Licence

La licence prévue est **MIT**. Le fichier `LICENSE` reste à ajouter.
