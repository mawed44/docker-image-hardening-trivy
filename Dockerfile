FROM python:3.12.16-alpine3.24@sha256:e6dae589c1c05976188fd3bd019afd091445fc533ed2ea29001beddc7368a9c8

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && python -m pip uninstall --yes pip \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app -h /nonexistent -s /sbin/nologin app

COPY main.py .

USER 10001:10001
EXPOSE 8080

CMD ["gunicorn", "--bind=0.0.0.0:8080", "--threads=2", "--no-control-socket", "main:app"]
