#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose up --detach --wait --wait-timeout 30 falco simulation
mkdir -p docs
docker compose logs --no-color --no-log-prefix falco > docs/falco-startup.log
bash scripts/check-hardening.sh | tee docs/hardening.txt

api_id=$(docker compose ps -q api)
simulation_id=$(docker compose ps -q simulation)
if [[ -z "$api_id" || -z "$simulation_id" ]]; then
    printf '[ERREUR] Les conteneurs api et simulation doivent etre demarres.\n' >&2
    exit 1
fi
api_id=${api_id:0:12}
simulation_id=${simulation_id:0:12}

has_alert() {
    local rule="$1" container="$2" field="$3"
    grep -E "\"rule\"[[:space:]]*:[[:space:]]*\"$rule\"" docs/falco-alerts.jsonl \
        | grep -E "\"container[.]id\"[[:space:]]*:[[:space:]]*\"$container\"" \
        | grep -E "$field" >/dev/null
}

sleep 1
since=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
docker compose exec -T api sh -c 'printf "shell simulation\n"'
docker compose exec -T --user 0:0 simulation sh -c 'printf "lab simulation\n" > /etc/lab-sensitive.conf'

for attempt in {1..10}; do
    logs=$(docker compose logs --no-color --no-log-prefix --since "$since" falco)
    printf '%s\n' "$logs" | grep -E '^\{.*"rule"[[:space:]]*:[[:space:]]*"(Lab Shell|Lab Sensitive Write)"' \
        > docs/falco-alerts.jsonl || true

    if has_alert 'Lab Shell' "$api_id" '"user[.]uid"[[:space:]]*:[[:space:]]*10001[[:space:]]*[,}]' \
        && has_alert 'Lab Sensitive Write' "$simulation_id" '"fd[.]name"[[:space:]]*:[[:space:]]*"/etc/lab-sensitive[.]conf"'; then
        cat docs/falco-alerts.jsonl
        exit 0
    fi
    sleep 1
done

printf '[ERREUR] Alertes absentes apres %s tentatives. Consulter docker compose logs falco.\n' "$attempt" >&2
exit 1
