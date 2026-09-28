# Durcissement de conteneur & sécurité au runtime (Docker, Cosign & Falco)

Ce projet a pour objectif de construire une image Docker selon le principe du **moindre privilège**, de vérifier son intégrité et l'identité de son signataire avec **Cosign (Sigstore)**, puis de détecter des comportements suspects au runtime avec **Falco et eBPF**. Une petite API HTTP en **Python avec Flask** sert de support de démonstration. Les vérifications de l'environnement utilisent un script **Bash**.

> **Étapes 1 et 2 :** vérification de l'environnement et création de l'API. Le Dockerfile durci, les scans, la signature et la surveillance Falco seront ajoutés dans les étapes suivantes.

## Problématique

Un conteneur exécuté avec l'utilisateur `root`, des privilèges inutiles et un système de fichiers modifiable augmente l'impact potentiel d'une compromission. Une image déployée sans vérification de signature ne fournit pas de garantie sur l'identité de son signataire. Enfin, sans surveillance au runtime, une ouverture de shell ou une tentative de modification de fichiers sensibles peut passer inaperçue.

Ces risques nécessitent des contrôles complémentaires : **réduire les privilèges**, **scanner et vérifier l'image avant son lancement**, puis **surveiller son comportement pendant l'exécution**.

## Solution apportée

L'[API](app/main.py) utilise **Flask**, dont la version est fixée dans `app/requirements.txt`. Elle expose deux routes : `GET /` pour présenter le laboratoire et `GET /health` pour vérifier son état. Les chemins inconnus renvoient `404` et les requêtes `POST` sur ces routes renvoient `405`. Les journaux du serveur sont envoyés vers la sortie standard.

L'image sera construite avec un **Dockerfile multi-stage commenté** : un premier stage préparera les dépendances Python, puis un stage final minimal exécutera l'application avec un utilisateur non-root. Avec Python, le multi-stage permettra de laisser les outils de préparation hors de l'image finale. Les images de base seront fixées par version et digest.

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

**État des étapes 1 et 2 :** les six tests Python passent et un lancement réel de l'API a confirmé les réponses `200`, `404` et `405`, ainsi que les journaux sur la sortie standard. Docker Linux fonctionne depuis Windows ; son accès depuis Ubuntu WSL nécessite encore l'activation de l'intégration dans Docker Desktop. Le script Bash signale ce point avec un code de sortie `1`. Les protections et alertes des étapes suivantes restent à mettre en place.

Une base Alpine conserve un shell, ce qui permettra de démontrer sa détection sans abandonner les protections du conteneur. La simulation d'écriture utilisera un fichier factice et ne modifiera aucun fichier sensible de l'hôte. Le refus d'une écriture et la détection d'une ouverture réussie seront vérifiés séparément : une règle portant sur une ouverture réussie ne prouve pas la détection d'une ouverture refusée.

## Lancer le projet

Les commandes suivantes s'exécutent dans un terminal **Bash**, depuis la racine du projet. Sous Windows, ouvrir le profil **Ubuntu** de Windows Terminal ou utiliser le terminal Ubuntu de WSL.

Si le terminal affiche **MINGW64**, il s'agit de **Git Bash**. Ouvrir Ubuntu avec `wsl -d Ubuntu` avant de suivre les commandes ci-dessous. Un environnement virtuel créé dans WSL utilise Python Linux et ne fonctionne pas dans Git Bash. Le préfixe `(.venv)` indique seulement que le script d'activation a été exécuté ; il ne garantit pas que son interpréteur est utilisable dans le terminal courant.

Prérequis : **Python 3**, le module `venv`, **Git** et **Docker avec des conteneurs Linux**. Sous Ubuntu, si le module `venv` manque, installer le paquet `python3-venv` avec `sudo apt install python3-venv`.

Pour accéder à Docker depuis Ubuntu, démarrer Docker Desktop, puis activer **Settings > Resources > WSL Integration > Ubuntu** et appliquer les changements. Cette configuration est décrite dans la [documentation Docker](https://docs.docker.com/desktop/features/wsl/#enable-docker-in-a-wsl-2-distribution).

**1. Vérifier l'environnement**

```bash
bash scripts/check-environment.sh
```

Ce [script](scripts/check-environment.sh) vérifie Git, Python 3 et l'accès au moteur Docker Linux, puis affiche le noyau utilisé. Il n'installe rien et ne modifie pas la configuration de la machine.

L'environnement retenu pour commencer est **Ubuntu WSL2 avec Docker Desktop**. La compatibilité eBPF et l'observation des conteneurs par Falco restent à vérifier lors de son installation ; un noyau récent ne suffit pas à les garantir.

**2. Installer la dépendance et lancer l'API**

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r app/requirements.txt
python3 app/main.py
```

L'environnement virtuel `.venv` isole les dépendances du projet. Lors des prochains lancements, il suffit de l'activer avec `source .venv/bin/activate`, puis d'exécuter `python3 app/main.py`. Utiliser `Ctrl+C` pour arrêter l'API et `deactivate` pour quitter l'environnement virtuel.

Le serveur écoute sur `127.0.0.1:8080`, avec le mode debug désactivé. Ce serveur Flask sert à la validation locale ; le serveur de l'image sera configuré à l'étape 3, conformément aux [recommandations Flask](https://flask.palletsprojects.com/en/stable/deploying/).

Dans un second terminal Bash :

```bash
curl -i http://127.0.0.1:8080/
curl -i http://127.0.0.1:8080/health
```

Réponses attendues, toutes deux avec un statut `200` :

```json
{"message":"Container Hardening Lab"}
```

```json
{"status":"ok"}
```

**Exécuter les tests HTTP**

```bash
source .venv/bin/activate
python3 -m unittest discover -s app -v
```

Les six [tests](app/test_main.py) utilisent `unittest`, fourni avec Python, et le client de test de Flask. Ils vérifient les réponses JSON, leur type de contenu, les chemins inconnus et le rejet des requêtes `POST`. Ils ne nécessitent pas de serveur lancé séparément.

**Progression du projet**

- [ ] Finaliser l'accès à Docker depuis Ubuntu WSL avec le script Bash.
- [x] Créer et valider l'API HTTP.
- [ ] Construire l'image multi-stage avec un utilisateur non-root.
- [ ] Configurer et vérifier les restrictions d'exécution.
- [ ] Scanner l'image avec Trivy.
- [ ] Publier, signer et vérifier l'image avec GitHub Actions et Cosign.
- [ ] Configurer Falco, vérifier sa sonde eBPF et ajouter les règles locales.
- [ ] Exécuter les simulations, enregistrer les preuves et mettre à jour ce README.

Trivy, Cosign et Falco ne sont pas nécessaires pour lancer cette première version de l'API. Ils seront ajoutés aux étapes correspondantes.

## Licence

La licence prévue est **MIT**. Le fichier `LICENSE` sera ajouté avant la publication du projet.
