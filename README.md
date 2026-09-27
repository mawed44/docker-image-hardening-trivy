# Durcissement de conteneur & sécurité au runtime (Docker, Cosign & Falco)

Ce laboratoire a pour objectif de construire une image Docker selon le principe du **moindre privilège**, de vérifier son intégrité et l'identité de son signataire avec **Cosign (Sigstore)**, puis de détecter des comportements suspects au runtime avec **Falco et eBPF**. Une petite API HTTP en Go servira de support de démonstration.

> **Projet en cours de construction.** Ce README décrit la solution prévue et les résultats attendus. L'application, les configurations et les preuves seront ajoutées et validées étape par étape.

## Problématique

Un conteneur exécuté avec l'utilisateur `root`, des privilèges inutiles et un système de fichiers modifiable augmente l'impact potentiel d'une compromission. Une image déployée sans vérification de signature ne fournit pas de garantie sur l'identité de son signataire. Enfin, sans surveillance au runtime, une ouverture de shell ou une tentative de modification de fichiers sensibles peut passer inaperçue.

Ces risques nécessitent des contrôles complémentaires : **réduire les privilèges**, **scanner et vérifier l'image avant son lancement**, puis **surveiller son comportement pendant l'exécution**.

## Solution apportée

L'image sera construite avec un **Dockerfile multi-stage commenté** : un premier stage compilera l'application, puis un stage final Alpine minimal exécutera le binaire avec un utilisateur non-root. Les images de base seront fixées par version et digest.

La configuration d'exécution dans `compose.yaml` supprimera toutes les capacités Linux avec `cap_drop: [ALL]`, activera un système de fichiers racine en lecture seule et interdira l'acquisition de nouveaux privilèges avec `no-new-privileges:true`. Des limites de ressources compléteront ces protections.

Le workflow GitHub Actions prévu construira et scannera l'image sur les `pull_request` vers `main`. Sur les `push` sur `main`, il publiera également l'image validée dans **GitHub Container Registry (GHCR)**, puis la signera et vérifiera sa signature.

| Outil | Contrôle | Échec du job |
| --- | --- | --- |
| **Docker** | Construction multi-stage et vérification des protections du conteneur | Construction impossible ou propriété de durcissement non respectée |
| **Trivy** | Vulnérabilités connues de l'image et de ses composants | Sévérité `HIGH` ou `CRITICAL` détectée |
| **Cosign (Sigstore)** | Signature du digest et vérification de l'identité du workflow signataire | Signature absente, invalide ou identité non autorisée |
| **Falco** | Détection d'un shell et d'ouvertures en écriture sur des fichiers sensibles de démonstration | Sans objet : émission d'une alerte au runtime, en dehors de la CI |

La signature Cosign utilisera l'identité **OIDC de GitHub Actions**, sans clé privée permanente stockée dans le dépôt. Le script de lancement vérifiera une référence immuable `image@sha256:…`, avec l'identité exacte du workflow et l'émetteur OIDC attendu, puis lancera ce même digest uniquement si la vérification réussit. Une signature valide ne garantit pas l'absence de vulnérabilités.

Les règles personnalisées seront placées dans `falco/falco_rules.local.yaml`. Falco assurera la détection et la journalisation ; aucun blocage automatique n'est prévu dans ce laboratoire.

## Résultats attendus

- API accessible sur `http://127.0.0.1:8080`, avec un endpoint `/health` renvoyant un statut `200`.
- Application exécutée avec un UID non nul, sans capacités Linux effectives et avec un système de fichiers racine en lecture seule.
- Rapport Trivy conservé dans les artefacts GitHub Actions et publication interrompue si le seuil de vulnérabilités est dépassé.
- Signature de l'image vérifiée avant son lancement ; refus avec une identité de signataire incorrecte ou une image non signée.
- Alerte Falco lors de l'exécution d'un shell dans un conteneur du laboratoire.
- Refus d'écriture dans le conteneur durci, puis alerte Falco lors d'une ouverture en écriture sur un fichier factice dans un conteneur de simulation dédié.
- Captures réelles et journaux associés conservés dans `docs/screenshots/` et `docs/evidence/` après exécution des scénarios.

Alpine conserve un shell, ce qui permet de démontrer sa détection sans abandonner les protections du conteneur. La simulation d'écriture utilisera un fichier factice et ne modifiera aucun fichier sensible de l'hôte. Le refus d'une écriture et la détection d'une ouverture réussie seront vérifiés séparément : une règle portant sur une ouverture réussie ne prouve pas la détection d'une ouverture refusée.

## Lancer le projet

À ce stade, seul le README est présent. Les commandes de construction, de lancement et de simulation seront ajoutées avec les fichiers correspondants.

Prérequis prévus :

- **Git** et un dépôt GitHub pour héberger le code et exécuter les workflows.
- **Docker avec des conteneurs Linux** pour construire et exécuter l'image.
- **Trivy** pour scanner l'image et **Cosign** pour vérifier sa signature.
- **Falco** sur le noyau Linux exécutant les conteneurs, avec les fonctionnalités nécessaires à sa sonde eBPF, notamment BTF et BPF ring buffer.

Sous Windows, commencer par ouvrir Docker Desktop, puis vérifier l'environnement dans **PowerShell** :

```powershell
git --version
docker version
docker info --format '{{.OSType}} | {{.KernelVersion}}'
wsl --list --verbose
```

Docker doit afficher les informations **Client** et **Server**, et le système annoncé doit être `linux`. Si Docker Desktop utilise le moteur WSL2, vérifier également sa configuration et les distributions disponibles.

Pour Falco, la compatibilité eBPF et l'observation des conteneurs devront être confirmées sur l'environnement choisi. Une installation dans une distribution WSL ne suffit pas à elle seule à valider cette observation. Une VM Linux avec Docker Engine et Falco sur le même hôte pourra servir d'environnement de laboratoire.

Ordre de réalisation :

1. Vérifier Docker et choisir l'environnement Linux pour Falco.
2. Créer et valider l'API HTTP.
3. Construire l'image multi-stage avec un utilisateur non-root.
4. Configurer et vérifier les restrictions d'exécution.
5. Scanner l'image avec Trivy.
6. Publier, signer et vérifier l'image avec GitHub Actions et Cosign.
7. Configurer Falco et ses règles locales.
8. Exécuter les simulations, enregistrer les preuves et mettre à jour ce README.

## Licence

La licence prévue est **MIT**. Le fichier `LICENSE` sera ajouté avant la publication du projet.
