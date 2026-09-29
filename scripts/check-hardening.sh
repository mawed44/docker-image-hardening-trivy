#!/usr/bin/env bash
set -euo pipefail

docker compose exec -T api python - <<'PY'
import errno
import importlib.util
import json
import os
import tempfile
from urllib.request import urlopen


def check(condition, message):
    if not condition:
        raise SystemExit(f"[ERREUR] {message}")
    print(f"[OK] {message}")


with urlopen("http://127.0.0.1:8080/health", timeout=2) as response:
    check(response.status == 200 and json.load(response) == {"status": "ok"},
          "L'API repond avec le statut 200 et le JSON attendu.")

check(os.getuid() == 10001 and os.getgid() == 10001,
      "La commande de verification utilise l'UID et le GID 10001.")

status = {}
with open("/proc/1/status") as status_file:
    for line in status_file:
        name, value = line.split(":", 1)
        status[name] = value.strip()

check(status["Uid"].split() == ["10001"] * 4 and status["Gid"].split() == ["10001"] * 4,
      "Le processus principal utilise l'UID et le GID 10001.")

for name in ("CapInh", "CapPrm", "CapEff", "CapBnd", "CapAmb"):
    check(int(status[name], 16) == 0, f"{name} : aucune capacite Linux.")
check(status["NoNewPrivs"].strip() == "1", "L'acquisition de nouveaux privileges est interdite.")
check(os.statvfs("/").f_flag & os.ST_RDONLY, "Le systeme de fichiers racine est en lecture seule.")

try:
    with open("/app/.hardening-check", "x"):
        pass
except OSError as error:
    check(error.errno == errno.EROFS, "Une creation de fichier dans /app est refusee (EROFS).")
else:
    os.unlink("/app/.hardening-check")
    check(False, "Une creation de fichier dans /app a ete autorisee.")

with tempfile.TemporaryFile(dir="/tmp") as temporary_file:
    temporary_file.write(b"verification")
    temporary_file.flush()
check(True, "L'espace temporaire /tmp est inscriptible.")

tmp_flags = os.statvfs("/tmp").f_flag
for flag, name in ((os.ST_NOEXEC, "noexec"), (os.ST_NOSUID, "nosuid"), (os.ST_NODEV, "nodev")):
    check(tmp_flags & flag, f"/tmp : protection {name} active.")

check(importlib.util.find_spec("pip") is None, "pip est absent de l'environnement applicatif.")
PY
