import logging
import sys

from flask import Flask


# Envoyer les journaux vers stdout pour les retrouver ensuite dans Docker.
logging.basicConfig(level=logging.INFO, stream=sys.stdout)

app = Flask(__name__, static_folder=None)


@app.get("/")
def home():
    return {"message": "Container Hardening Lab"}


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    # Serveur local de developpement ; le mode debug reste desactive.
    app.run(host="127.0.0.1", port=8080, debug=False)
