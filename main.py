from flask import Flask


app = Flask(__name__, static_folder=None)


@app.get("/")
def home():
    return {"message": "Container Hardening Lab"}


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080, debug=False)
