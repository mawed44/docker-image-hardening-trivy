# Durcissement de conteneur & sécurité au runtime (Docker, Cosign & Falco)

Ce projet a pour objectif de construire une image Docker selon le principe du **moindre privilège**, de vérifier son intégrité et l'identité de son signataire avec **Cosign (Sigstore)**, puis de détecter des comportements suspects au runtime avec **Falco et eBPF**. Une petite API HTTP en **Python avec Flask** sert de support de démonstration. Les vérifications de l'environnement utilisent un script **Bash**.

> **Étapes 2 à 5 vérifiées localement.** Le workflow de publication et de signature est prêt ; sa première exécution sur GitHub reste à valider. L'accès à Docker depuis Ubuntu WSL et les étapes Falco restent à finaliser.

## Problématique

Un conteneur exécuté avec l'utilisateur `root`, des privilèges inutiles et un système de fichiers modifiable augmente l'impact potentiel d'une compromission. Une image déployée sans vérification de signature ne fournit pas de garantie sur l'identité de son signataire. Enfin, sans surveillance au runtime, une ouverture de shell ou une tentative de modification de fichiers sensibles peut passer inaperçue.

Ces risques nécessitent des contrôles complémentaires : **réduire les privilèges**, **scanner et vérifier l'image avant son lancement**, puis **surveiller son comportement pendant l'exécution**.

## Solution apportée

L'[API](app/main.py) utilise **Flask**, dont la version est fixée dans `app/requirements.txt`. Elle expose deux routes : `GET /` pour présenter le laboratoire et `GET /health` pour vérifier son état. Les chemins inconnus renvoient `404` et les requêtes `POST` sur ces routes renvoient `405`. Les journaux du serveur sont envoyés vers la sortie standard.

Le [Dockerfile multi-stage commenté](Dockerfile) utilise **Python 3.12.16 sur Alpine 3.24**, fixé par version et digest dans les deux stages. Le premier installe les dépendances dans un environnement virtuel ; le second reçoit cet environnement et le code de l'API. Le compte applicatif utilise l'UID et le GID `10001`, sans répertoire personnel ni shell de connexion. Le code appartient à root avec des permissions `0444`, et pip est retiré de l'image finale.

**Gunicorn 26.2.0** exécute l'API sur le port `8080`. Son `ENTRYPOINT` au format JSON lui transmet directement les signaux d'arrêt. Ses fichiers temporaires vont dans `/tmp` et son socket de contrôle est désactivé.

Le fichier [compose.yaml](compose.yaml) supprime toutes les capacités Linux, active `no-new-privileges` et monte la racine en lecture seule. Un `tmpfs` de **16 Mio** fournit l'espace temporaire de Gunicorn avec les protections `noexec`, `nosuid` et `nodev`. Les limites sont de **0,5 CPU, 128 Mio de RAM et 64 processus**. La limite totale mémoire + swap vaut également 128 Mio, sans swap supplémentaire. Un healthcheck Python vérifie `/health` et la publication du port est limitée à `127.0.0.1`.

Le [workflow Container security](.github/workflows/container-security.yml) comporte deux jobs :

- **`scan`** construit l'image et lance **Trivy 0.76.1** sur les `pull_request` vers `main` et les `push` sur `main`. Le rapport JSON est conservé 30 jours dans les artefacts, même lorsque le scan détecte des vulnérabilités bloquantes.
- **`publish`** s'exécute après un scan réussi, uniquement sur un `push` sur `main`. Il récupère la même image par une archive `image.tar`, sans la reconstruire, puis appelle [publish-image.sh](scripts/publish-image.sh) pour la publier dans **GHCR**, la signer et vérifier sa signature. Le SHA du commit sert de tag.

| Outil | Contrôle | Échec du job |
| --- | --- | --- |
| **Docker** | Construction de l'image multi-stage | Construction impossible |
| **Trivy** | Vulnérabilités connues de l'image et de ses composants | Sévérité `HIGH` ou `CRITICAL` détectée |
| **Cosign (Sigstore)** | Signature du digest et vérification de l'identité du workflow signataire | Signature absente, invalide ou identité non autorisée |
| **Falco** | Détection d'un shell et d'ouvertures en écriture sur des fichiers sensibles de démonstration | Sans objet : émission d'une alerte au runtime, en dehors de la CI |

Après publication, **Cosign 3.1.4** signe le digest avec l'identité **OIDC de GitHub Actions**, puis vérifie la signature. Les actions sont fixées par SHA. GitHub fournit automatiquement `GITHUB_TOKEN` et l'identité OIDC avec les permissions déclarées dans le workflow : aucune clé de signature ni aucun secret manuel ne sont nécessaires.

Le [script de lancement signé](scripts/verify-and-run.sh) accepte uniquement une référence `ghcr.io/mawed44/docker-security-hardening-sigstore@sha256:…`. Il vérifie l'identité exacte du workflow sur `main` et l'émetteur `https://token.actions.githubusercontent.com`, puis transmet ce même digest à Compose. Un échec de vérification interrompt le lancement. Une signature valide ne garantit pas l'absence de vulnérabilités.

Les règles personnalisées seront placées dans `falco/falco_rules.local.yaml`. Falco assurera la détection et la journalisation ; aucun blocage automatique n'est prévu dans ce laboratoire.

## Résultats attendus

- API accessible sur `http://127.0.0.1:8080`, avec un endpoint `/health` renvoyant un statut `200`.
- Application exécutée avec un UID non nul, sans capacités Linux effectives et avec un système de fichiers racine en lecture seule.
- Rapport Trivy conservé dans les artefacts GitHub Actions et publication interrompue si le seuil de vulnérabilités est dépassé.
- Signature de l'image vérifiée avant son lancement ; refus avec une identité de signataire incorrecte ou une image non signée.
- Alerte Falco lors de l'exécution d'un shell dans un conteneur du laboratoire.
- Refus d'écriture dans le conteneur durci, puis alerte Falco lors d'une ouverture en écriture sur un fichier factice dans un conteneur de simulation dédié.
- Captures réelles et journaux associés conservés dans `docs/screenshots/` et `docs/evidence/` après exécution des scénarios.

**Vérifié pour les étapes 2 à 4 :** image construite, conteneur `healthy`, six tests Python réussis dans l'image, réponses HTTP `200`, `404` et `405`, et 16 contrôles de durcissement réussis. L'écriture dans `/app` échoue avec `EROFS` (système de fichiers en lecture seule), tandis que `/tmp` reste utilisable. Les limites CPU, mémoire et processus ont également été confirmées avec Docker. Le test réel a utilisé le port hôte `18080`, car le port `8080` était déjà occupé.

**Vérifié pour les étapes 5 et 6 :** le scan Trivy de l'image locale ne détecte aucune vulnérabilité `HIGH` ou `CRITICAL`. `actionlint` et ShellCheck passent, ainsi que les scénarios de simulation des scripts, dont le refus de démarrer après un échec Cosign. La publication GHCR et la signature de l'image du projet avec GitHub OIDC attendent encore le premier `push` sur `main`. Les tests HTTP et le contrôle de durcissement ci-dessus sont des validations locales ; ils ne sont pas lancés par ce workflow.

Une base Alpine conserve un shell, ce qui permettra de démontrer sa détection sans abandonner les protections du conteneur. La simulation d'écriture utilisera un fichier factice et ne modifiera aucun fichier sensible de l'hôte. Le refus d'une écriture et la détection d'une ouverture réussie seront vérifiés séparément : une règle portant sur une ouverture réussie ne prouve pas la détection d'une ouverture refusée.

## Lancer le projet

Le lancement avec **Docker Compose** nécessite Docker et son plugin Compose. Sous Windows, démarrer Docker Desktop en mode conteneurs Linux. Les commandes `docker compose` fonctionnent depuis **Git Bash ou PowerShell**, sans environnement virtuel ni Python installé sur Windows.

Les scripts suivants utilisent **Bash**. Pour les exécuter localement, installer [Trivy](https://trivy.dev/docs/latest/getting-started/installation/) et [Cosign](https://docs.sigstore.dev/cosign/system_config/installation/) dans le `PATH` du terminal. Le workflow GitHub Actions installe automatiquement les versions indiquées plus haut.

**Construire et scanner l'image locale**

```bash
docker compose build api
bash scripts/scan-image.sh
```

Le [script Trivy](scripts/scan-image.sh) produit `reports/trivy.json`, ignoré par Git, et renvoie un code d'échec si une vulnérabilité `HIGH` ou `CRITICAL` est détectée. Il est aussi possible de lui transmettre un nom d'image en argument.

**Construire et démarrer pour le développement**

Depuis la racine du projet :

```bash
docker compose up --build -d --wait
docker compose ps
```

Ouvrir `http://127.0.0.1:8080/health`. La réponse attendue est un statut `200` avec `{"status":"ok"}`. La racine `/` renvoie `{"message":"Container Hardening Lab"}`.

Si le port `8080` est déjà utilisé par l'API locale, l'arrêter avec `Ctrl+C` avant le lancement. Il est aussi possible de choisir un autre port avec `API_PORT`. Exemple dans **Bash** :

```bash
API_PORT=18080 docker compose up --build -d --wait
curl -i http://127.0.0.1:18080/health
```

Le port interne du conteneur reste `8080`.

Ce lancement construit une image locale sans vérifier de signature. Pour déployer l'image publiée dans GHCR, utiliser le script suivant.

**Lancer une image signée après publication**

Après un `push` sur `main`, ouvrir **Actions > Container security**. Lorsque le workflow réussit, copier la référence `ghcr.io/mawed44/docker-security-hardening-sigstore@sha256:…` depuis le résumé de l'exécution.

Dans cette commande Bash, remplacer `<digest>` par les **64 caractères hexadécimaux** du digest obtenu :

```bash
API_PORT=18080 bash scripts/verify-and-run.sh \
  'ghcr.io/mawed44/docker-security-hardening-sigstore@sha256:<digest>'
```

Le script vérifie la signature, puis Compose télécharge et lance ce même digest, sans construction locale, avec les protections de `compose.yaml`. L'API est ensuite accessible sur `http://127.0.0.1:18080/health`.

Pour télécharger sans authentification, rendre le package GHCR public. S'il reste privé, se connecter avec `docker login ghcr.io --username mawed44` et un jeton disposant de `read:packages`, comme indiqué dans la [documentation GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

**Vérifier le durcissement**

Depuis Git Bash, Ubuntu WSL ou Linux :

```bash
bash scripts/check-hardening.sh
```

Ce [script](scripts/check-hardening.sh) exécute Python **dans le conteneur**. Il vérifie l'API, les UID/GID, les capacités Linux, `NoNewPrivs`, la racine en lecture seule, le refus d'écriture dans `/app`, les protections de `/tmp` et l'absence de pip. Les 16 contrôles doivent afficher `[OK]` ; une erreur interrompt le script avec un code de sortie non nul.

**Consulter les journaux et arrêter le projet**

```bash
docker compose logs api
docker compose down
```

**Développement local et tests Python — option Ubuntu WSL ou Linux**

Cette option utilise Python 3 et le module `venv` sur Linux. Sous Ubuntu, installer au besoin le paquet `python3-venv`. Si le terminal affiche `MINGW64`, il s'agit de Git Bash : ouvrir Ubuntu avec `wsl -d Ubuntu` avant de suivre ces commandes. Un environnement virtuel créé dans WSL utilise Python Linux et ne fonctionne pas dans Git Bash.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r app/requirements.txt
python3 -m unittest discover -s app -v
python3 app/main.py
```

Les six [tests HTTP](app/test_main.py) utilisent `unittest` et le client de test de Flask. Ils vérifient les réponses JSON, les chemins inconnus et le rejet des requêtes `POST`, sans serveur à démarrer séparément.

Le lancement local utilise le serveur de développement Flask sur `127.0.0.1:8080`, avec le mode debug désactivé. Utiliser `Ctrl+C` pour l'arrêter et `deactivate` pour quitter l'environnement virtuel. Lors des prochains lancements, activer `.venv` puis exécuter `python3 app/main.py`.

**Vérification de l'environnement Ubuntu WSL — étape 1 à finaliser**

Pour accéder à Docker depuis Ubuntu, activer **Docker Desktop > Settings > Resources > WSL Integration > Ubuntu**, puis appliquer les changements. Voir la [documentation Docker](https://docs.docker.com/desktop/features/wsl/#enable-docker-in-a-wsl-2-distribution).

```bash
bash scripts/check-environment.sh
```

Ce [script](scripts/check-environment.sh), destiné à Ubuntu WSL ou Linux, vérifie Git, Python 3 et Docker. L'intégration Docker dans Ubuntu reste à activer sur l'environnement testé. La compatibilité eBPF et l'observation des conteneurs par Falco seront vérifiées à l'étape correspondante.

**Progression du projet**

- [ ] Finaliser l'accès à Docker depuis Ubuntu WSL avec le script Bash.
- [x] Créer et valider l'API HTTP.
- [x] Construire l'image multi-stage avec un utilisateur non-root.
- [x] Configurer et vérifier les restrictions d'exécution.
- [x] Scanner l'image avec Trivy et préparer le contrôle GitHub Actions.
- [ ] Valider la première publication, signature et vérification sur GitHub Actions ; configuration prête.
- [ ] Configurer Falco, vérifier sa sonde eBPF et ajouter les règles locales.
- [ ] Exécuter les simulations, enregistrer les preuves et mettre à jour ce README.

Falco sera ajouté à l'étape suivante pour surveiller le conteneur au runtime.

## Licence

La licence prévue est **MIT**. Le fichier `LICENSE` sera ajouté avant la publication du projet.
