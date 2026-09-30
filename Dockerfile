# Installation des dependances.
FROM python:3.12.16-alpine3.24@sha256:e6dae589c1c05976188fd3bd019afd091445fc533ed2ea29001beddc7368a9c8 AS builder

WORKDIR /build
COPY requirements.txt .

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /opt/venv/bin/python -m pip uninstall --yes pip

# Image finale avec un utilisateur non-root.
FROM python:3.12.16-alpine3.24@sha256:e6dae589c1c05976188fd3bd019afd091445fc533ed2ea29001beddc7368a9c8 AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

RUN python -m pip uninstall --yes pip \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app -h /nonexistent -s /sbin/nologin app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv

COPY --chmod=0444 main.py ./main.py

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["gunicorn"]
CMD ["--bind=0.0.0.0:8080", "--workers=1", "--threads=2", "--worker-tmp-dir=/tmp", "--no-control-socket", "--access-logfile=-", "main:app"]
